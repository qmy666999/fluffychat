// 语音播放的唯一状态源。
//
// 之前「谁在播」有两份答案：`MatrixState.audioPlayer`（just_audio 实例）和
// `voiceMessageEventId`（一个只在切换时才通知的 ValueNotifier）。播放中/暂停/播完
// 都不会触发通知，所以气泡上的波形只能靠碰巧重建才读到新状态 —— 于是出现
// 「声音读完了动画还在播」「亮着但不播」「灰色不动」这些表现。
//
// 现在所有播放状态都在这一个 ChangeNotifier 里，UI 只读它、不自己判断。
import 'dart:async';
import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

enum VoicePlaybackState { idle, loading, playing, paused, completed, error }

class VoicePlayback extends ChangeNotifier {
  VoicePlayback._();

  static final VoicePlayback instance = VoicePlayback._();

  AudioPlayer? _player;
  String? _eventId;
  VoicePlaybackState _state = VoicePlaybackState.idle;
  double? _downloadProgress;
  String? _error;
  final Set<String> _played = {};
  Timer? _watchdog;
  StreamSubscription<PlayerState>? _playerStateSub;

  /// 每次开始播新的语音都自增，用来丢弃过期的异步结果（下载慢于用户点击时）。
  int _token = 0;

  String? get currentEventId => _eventId;

  VoicePlaybackState get state => _state;

  VoicePlaybackState stateOf(String eventId) {
    if (_eventId == eventId) return _state;
    return _played.contains(eventId)
        ? VoicePlaybackState.completed
        : VoicePlaybackState.idle;
  }

  bool isPlaying(String eventId) =>
      _eventId == eventId && _state == VoicePlaybackState.playing;

  bool isPlayed(String eventId) => _played.contains(eventId);

  double? progressOf(String eventId) =>
      _eventId == eventId ? _downloadProgress : null;

  String? errorOf(String eventId) => _eventId == eventId ? _error : null;

  /// 点一下语音气泡：同一在播 → 暂停；同一暂停 → 继续；否则从头播新的。
  Future<void> toggle(
    Event event, {
    required L10n l10n,
    void Function(Object error, StackTrace stackTrace)? onDownloadError,
  }) async {
    final eventId = event.eventId;
    if (_eventId == eventId) {
      switch (_state) {
        case VoicePlaybackState.playing:
          await _player?.pause();
          _played.add(eventId);
          _set(VoicePlaybackState.paused);
          return;
        case VoicePlaybackState.paused:
          await _player?.play();
          _set(VoicePlaybackState.playing);
          _startWatchdog();
          return;
        case VoicePlaybackState.completed:
          await _start(event, l10n: l10n, onDownloadError: onDownloadError);
          return;
        case VoicePlaybackState.loading:
          // 正在下载，重复点击不再排队。
          return;
        case VoicePlaybackState.error:
        case VoicePlaybackState.idle:
          break;
      }
    }

    await _start(event, l10n: l10n, onDownloadError: onDownloadError);
  }

  Future<void> _start(
    Event event, {
    required L10n l10n,
    void Function(Object error, StackTrace stackTrace)? onDownloadError,
  }) async {
    await _hardStop();
    final token = ++_token;
    _eventId = event.eventId;
    _downloadProgress = 0;
    _error = null;
    _set(VoicePlaybackState.loading);

    try {
      final fileSize = event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      final matrixFile = await event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize != null && fileSize > 0
            ? (progress) {
                if (token != _token) return;
                final value = progress / fileSize;
                _downloadProgress = value < 1 ? value : null;
                notifyListeners();
              }
            : null,
      );
      if (token != _token) return;

      final path = await _materialize(event, matrixFile);
      if (token != _token) return;

      final player = AudioPlayer();
      _player = player;
      await player.setFilePath(path);
      if (token != _token) {
        await _releasePlayer();
        return;
      }

      // just_audio 0.10 起没有 onPlayerComplete，只能监听 processingState。
      await _playerStateSub?.cancel();
      _playerStateSub = player.playerStateStream.listen((playerState) {
        if (token != _token) return;
        if (playerState.processingState == ProcessingState.completed) {
          _onCompleted(token);
        }
      });

      _downloadProgress = null;
      _set(VoicePlaybackState.playing);
      _startWatchdog();
      unawaited(
        player.play().catchError((Object error, StackTrace stackTrace) {
          if (token != _token) return;
          Logs().w('[voice] 播放失败', error, stackTrace);
          _error = l10n.voicePlaybackFailed;
          _set(VoicePlaybackState.error);
        }),
      );
    } catch (error, stackTrace) {
      if (token != _token) return;
      Logs().w('[voice] 加载失败', error, stackTrace);
      _error = l10n.voicePlaybackFailed;
      _set(VoicePlaybackState.error);
      onDownloadError?.call(error, stackTrace);
    }
  }

  /// 把附件写到临时文件（just_audio 播本地文件最稳），iOS 的 ogg 顺手转 caf。
  Future<String> _materialize(Event event, MatrixFile matrixFile) async {
    final tempDir = await getTemporaryDirectory();
    final attachmentUrl = event.attachmentOrThumbnailMxcUrl();
    final safeName = attachmentUrl == null
        ? event.eventId
        : Uri.encodeComponent(attachmentUrl.pathSegments.last);
    var file = File('${tempDir.path}/${safeName}_${matrixFile.name}');
    await file.writeAsBytes(matrixFile.bytes);

    if (Platform.isIOS && matrixFile.mimeType.toLowerCase() == 'audio/ogg') {
      final converted = File('${file.path}.caf');
      if (!converted.existsSync()) {
        try {
          await OggCafConverter().convertOggToCaf(
            input: file.path,
            output: converted.path,
          );
        } catch (error, stackTrace) {
          Logs().w('[voice] ogg 转 caf 失败，直接播原文件', error, stackTrace);
          return file.path;
        }
      }
      file = converted;
    }
    return file.path;
  }

  /// 兜底：duration + 1.5 秒还没收到完成回调就强制复位。
  ///
  /// 某些设备上 onPlayerComplete 不一定触发（焦点被占、后台被掐），
  /// 没有这个兜底就会永远卡在 playing（就是「亮着不动」那种）。
  void _startWatchdog() {
    _watchdog?.cancel();
    final duration = _player?.duration ?? Duration.zero;
    _watchdog = Timer(duration + const Duration(milliseconds: 1500), () {
      if (_state != VoicePlaybackState.playing) return;
      Logs().v('[voice] watchdog 超时，强制复位');
      _onCompleted(_token);
    });
  }

  void _onCompleted(int token) {
    if (token != _token) return;
    final eventId = _eventId;
    if (eventId != null) _played.add(eventId);
    _watchdog?.cancel();
    _watchdog = null;
    _downloadProgress = null;
    _error = null;
    _state = VoicePlaybackState.completed;
    notifyListeners();
    unawaited(_releasePlayer());
  }

  void _set(VoicePlaybackState state) {
    _state = state;
    notifyListeners();
  }

  /// 彻底停掉并清空状态（切歌、退出页面、出错都用它）。
  Future<void> stop() async {
    _token++;
    _eventId = null;
    _downloadProgress = null;
    _error = null;
    _state = VoicePlaybackState.idle;
    await _hardStop();
    notifyListeners();
  }

  Future<void> _hardStop() async {
    _watchdog?.cancel();
    _watchdog = null;
    await _playerStateSub?.cancel();
    _playerStateSub = null;
    await _releasePlayer();
  }

  Future<void> _releasePlayer() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (error, stackTrace) {
      Logs().d('[voice] 停止播放器失败', error, stackTrace);
    }
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      Logs().d('[voice] 释放播放器失败', error, stackTrace);
    }
  }

  @override
  void dispose() {
    unawaited(_hardStop());
    super.dispose();
  }
}

/// 让「正在播的那条」在 App 退到后台时也停下来，避免和别的音频抢焦点。
Future<void> stopVoicePlayback() => VoicePlayback.instance.stop();

/// 供 UI 在出错时提示用。
void showVoicePlaybackError(String message) =>
    AppToast.show(message, isError: true);
