// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../widgets/fluffy_chat_app.dart';
import '../../../widgets/matrix.dart';

/// 微信样式的语音气泡：一个胶囊，里面是时长（例如 `2"`）和一个喇叭图标。
/// 宽度随时长变化，没有进度条，点击气泡播放 / 暂停。
class AudioPlayerWidget extends StatefulWidget {
  final Color color;
  final Color linkColor;
  final double fontSize;
  final Event event;

  /// 录音波形采样数（录音界面在用，这里保留以保持兼容）。
  static const int wavesCount = 40;

  const AudioPlayerWidget(
    this.event, {
    required this.color,
    required this.linkColor,
    required this.fontSize,
    super.key,
  });

  @override
  AudioPlayerState createState() => AudioPlayerState();
}

enum AudioPlayerStatus { notDownloaded, downloading, downloaded }

class AudioPlayerState extends State<AudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  static const double _bubbleHeight = 40;
  static const double _minBubbleWidth = 80;
  static const double _maxBubbleWidth = 200;

  AudioPlayerStatus status = AudioPlayerStatus.notDownloaded;
  double? _downloadProgress;
  bool _pulseWanted = false;

  late final MatrixState matrix;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    matrix = Matrix.of(context);

    if (matrix.voiceMessageEventId.value == widget.event.eventId &&
        matrix.audioPlayer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
    final audioPlayer = matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (audioPlayer != null) {
      if (audioPlayer.playing && !audioPlayer.isAtEndPosition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(matrix.context).showMaterialBanner(
            MaterialBanner(
              padding: EdgeInsets.zero,
              leading: StreamBuilder(
                stream: audioPlayer.playerStateStream.asBroadcastStream(),
                builder: (context, _) => IconButton(
                  onPressed: () {
                    if (audioPlayer.isAtEndPosition) {
                      audioPlayer.seek(Duration.zero);
                    } else if (audioPlayer.playing) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play();
                    }
                  },
                  icon: audioPlayer.playing && !audioPlayer.isAtEndPosition
                      ? const Icon(Icons.pause_outlined)
                      : const Icon(Icons.play_arrow_outlined),
                ),
              ),
              content: StreamBuilder(
                stream: audioPlayer.positionStream.asBroadcastStream(),
                builder: (context, _) => GestureDetector(
                  onTap: () => FluffyChatApp.router.go(
                    '/rooms/${widget.event.room.id}?event=${widget.event.eventId}',
                  ),
                  child: Text(
                    '🎙️ ${audioPlayer.position.minuteSecondString} / ${audioPlayer.duration?.minuteSecondString} - ${widget.event.senderFromMemoryOrFallback.calcDisplayname()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    audioPlayer.pause();
                    audioPlayer.dispose();
                    matrix.voiceMessageEventId.value = matrix.audioPlayer =
                        null;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(
                        matrix.context,
                      ).clearMaterialBanners();
                    });
                  },
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
          );
        });
        return;
      }
      audioPlayer.pause();
      audioPlayer.dispose();
      matrix.voiceMessageEventId.value = matrix.audioPlayer = null;
    }
  }

  Future<void> _onButtonTap() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
    });
    final currentPlayer =
        matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (currentPlayer != null && !currentPlayer.isAtEndPosition) {
      if (currentPlayer.playing) {
        currentPlayer.pause();
      } else {
        currentPlayer.play();
      }
      return;
    }

    matrix.voiceMessageEventId.value = widget.event.eventId;
    matrix.audioPlayer
      ?..stop()
      ..dispose();
    File? file;
    MatrixFile? matrixFile;

    setState(() => status = AudioPlayerStatus.downloading);
    try {
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      matrixFile = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize != null && fileSize > 0
            ? (progress) {
                final progressPercentage = progress / fileSize;
                setState(() {
                  _downloadProgress = progressPercentage < 1
                      ? progressPercentage
                      : null;
                });
              }
            : null,
      );

      final attachmentUrl = widget.event.attachmentOrThumbnailMxcUrl();

      if (!kIsWeb && attachmentUrl != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = Uri.encodeComponent(attachmentUrl.pathSegments.last);
        file = File('${tempDir.path}/${fileName}_${matrixFile.name}');

        await file.writeAsBytes(matrixFile.bytes);

        if (Platform.isIOS &&
            matrixFile.mimeType.toLowerCase() == 'audio/ogg') {
          Logs().v('Convert ogg audio file for iOS...');
          final convertedFile = File('${file.path}.caf');
          if (await convertedFile.exists() == false) {
            await OggCafConverter().convertOggToCaf(
              input: file.path,
              output: convertedFile.path,
            );
          }
          file = convertedFile;
        }
      }

      setState(() {
        status = AudioPlayerStatus.downloaded;
      });
    } catch (e, s) {
      Logs().v('Could not download audio file', e, s);
      if (!mounted) rethrow;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      rethrow;
    }
    if (!context.mounted) return;
    if (matrix.voiceMessageEventId.value != widget.event.eventId) return;

    final audioPlayer = matrix.audioPlayer = AudioPlayer();

    if (file != null) {
      audioPlayer.setFilePath(file.path);
    } else {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(matrixFile.bytes, mimeType: matrixFile.mimeType),
        ),
      );
    }
    if (!mounted) return;

    audioPlayer.play().onError(
      ErrorReporter(context, 'Unable to play audio message').onErrorCallback,
    );
  }

  int? _durationSeconds(AudioPlayer? audioPlayer) {
    final durationMs = widget.event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('duration');
    if (durationMs != null) return (durationMs / 1000).round();
    return audioPlayer?.duration?.inSeconds;
  }

  /// 播放中让喇叭图标轻微跳动。
  ///
  /// 放到帧后执行，避免在 build 期间通知动画监听者（否则会触发
  /// “setState during build”）。
  void _syncPulse(bool playing) {
    if (playing == _pulseWanted) return;
    _pulseWanted = playing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pulseWanted) {
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    });
  }

  /// 微信的语音气泡宽度随时长变化：1 秒约 80px，60 秒约 200px。
  double _bubbleWidth(int seconds) {
    final s = seconds.clamp(1, 60);
    return _minBubbleWidth + (s / 60.0) * (_maxBubbleWidth - _minBubbleWidth);
  }

  @override
  Widget build(BuildContext context) {
    final fileDescription = widget.event.fileDescription;

    return ValueListenableBuilder(
      valueListenable: matrix.voiceMessageEventId,
      builder: (context, eventId, _) {
        final audioPlayer = eventId != widget.event.eventId
            ? null
            : matrix.audioPlayer;
        final playing =
            audioPlayer != null &&
            audioPlayer.playing &&
            !audioPlayer.isAtEndPosition;
        final isOwn = widget.event.senderId == widget.event.room.client.userID;

        _syncPulse(playing);

        final seconds = _durationSeconds(audioPlayer) ?? 5;
        final width = _bubbleWidth(seconds);

        final icon = status == AudioPlayerStatus.downloading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.color,
                  value: _downloadProgress,
                ),
              )
            : ScaleTransition(
                scale: Tween<double>(begin: 1, end: 1.18).animate(
                  CurvedAnimation(
                    parent: _pulseController,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: Icon(
                  playing ? Icons.graphic_eq : Icons.volume_up,
                  size: 18,
                  color: widget.color,
                ),
              );

        final durationLabel = Text(
          '$seconds"',
          style: TextStyle(
            color: widget.color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        );

        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onButtonTap,
                child: Container(
                  width: width,
                  height: _bubbleHeight,
                  alignment: isOwn
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: .min,
                    mainAxisAlignment: isOwn
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: isOwn
                        ? [durationLabel, const SizedBox(width: 6), icon]
                        : [icon, const SizedBox(width: 6), durationLabel],
                  ),
                ),
              ),
            ),
            if (fileDescription != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Linkify(
                  text: fileDescription,
                  textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                  style: TextStyle(
                    color: widget.color,
                    fontSize: widget.fontSize,
                  ),
                  options: const LinkifyOptions(humanize: false),
                  linkStyle: TextStyle(
                    color: widget.linkColor,
                    fontSize: widget.fontSize,
                    decoration: TextDecoration.underline,
                    decorationColor: widget.linkColor,
                  ),
                  onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                ),
              ),
          ],
        );
      },
    );
  }
}

extension on AudioPlayer {
  bool get isAtEndPosition {
    final duration = this.duration;
    if (duration == null) return true;
    return position >= duration;
  }
}

extension on Duration {
  String get minuteSecondString =>
      '${inMinutes.toString().padLeft(2, '0')}:${(inSeconds % 60).toString().padLeft(2, '0')}';
}
