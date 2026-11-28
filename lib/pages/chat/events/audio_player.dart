// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/utils/wechat/transcription_service.dart';
import 'package:fluffychat/utils/wechat/voice_playback.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'transcription_bubble.dart';

/// 微信样式的语音气泡：一个胶囊，里面是时长（例如 `2"`）和三条波形。
/// 宽度随时长变化，没有进度条，点击气泡播放 / 暂停。
///
/// 播放状态全部来自 [VoicePlayback]（单一数据源），这里只负责画。
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

class AudioPlayerState extends State<AudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  static const double _bubbleHeight = 40;
  static const double _minBubbleWidth = 80;
  static const double _maxBubbleWidth = 200;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  bool _pulseWanted = false;

  final VoicePlayback _playback = VoicePlayback.instance;

  @override
  void dispose() {
    // 注意：这里不停播放。列表滚出屏幕也会 dispose，停在这里会把正常播放打断。
    // 「退出聊天页就停」由 ChatController.dispose 负责。
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final l10n = L10n.of(context);
    await _playback.toggle(
      widget.event,
      l10n: l10n,
      onDownloadError: (error, stackTrace) {
        if (!mounted) return;
        AppToast.show(error.toLocalizedString(context), isError: true);
      },
    );
  }

  int _durationSeconds() {
    final durationMs = widget.event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('duration');
    if (durationMs != null) return (durationMs / 1000).round();
    return 5;
  }

  /// 播放中让波形跳动；状态一变就跟着开/停，且停止时归零。
  ///
  /// 放到帧后执行，避免在 build 期间通知动画监听者（会触发
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
    final l10n = L10n.of(context);
    final isOwn = widget.event.senderId == widget.event.room.client.userID;
    final seconds = _durationSeconds();
    final width = _bubbleWidth(seconds);

    return AnimatedBuilder(
      animation: _playback,
      builder: (context, _) {
        final state = _playback.stateOf(widget.event.eventId);
        final playing = state == VoicePlaybackState.playing;
        final loading = state == VoicePlaybackState.loading;
        final failed = state == VoicePlaybackState.error;
        final progress = _playback.progressOf(widget.event.eventId);

        _syncPulse(playing);

        // 播过就变浅（微信里播完的语音是灰的），正在播时保持实色。
        final faded = _playback.isPlayed(widget.event.eventId) && !playing;
        final barColor = faded
            ? widget.color.withValues(alpha: 0.5)
            : widget.color;

        final Widget icon;
        if (loading) {
          icon = SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.color,
              value: progress,
            ),
          );
        } else if (failed) {
          icon = Icon(
            Icons.error_outline,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          );
        } else {
          icon = VoiceBars(
            animation: _pulseController,
            playing: playing,
            color: barColor,
          );
        }

        final durationLabel = Text(
          '$seconds"',
          style: TextStyle(
            color: barColor,
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
                onTap: _onTap,
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
            ValueListenableBuilder<int>(
              valueListenable: TranscriptionService.revision,
              builder: (context, _, _) {
                final entry = TranscriptionService.entryOf(
                  widget.event.eventId,
                );
                if (entry == null) return const SizedBox.shrink();
                return TranscriptionBubble(
                  entry: entry,
                  color: widget.color,
                  onRetry: () => TranscriptionService.transcribe(widget.event),
                );
              },
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
            if (failed)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Text(
                  l10n.voicePlaybackFailed,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 微信式语音波形：三条竖线，只有正在播放时才跳。
///
/// 播放时用 [_animation] 驱动高度，暂停时回到固定的静止高度，
/// 这样“点一下就停”不会有残留动画。
class VoiceBars extends StatelessWidget {
  const VoiceBars({
    super.key,
    required this.animation,
    required this.playing,
    required this.color,
    this.barWidth = 3,
    this.gap = 2,
    this.maxHeight = 18,
  });

  final Animation<double> animation;
  final bool playing;
  final Color color;
  final double barWidth;
  final double gap;
  final double maxHeight;

  /// 暂停时的静止形状（中间那根高一点，像微信）。
  static const List<double> idleHeights = <double>[8, 16, 11];

  double _animatedHeight(double t, int index) {
    final phase = (t + index * 0.28) % 1.0;
    final wave = math.sin(phase * math.pi * 2).abs();
    return 6 + wave * (maxHeight - 6);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: barWidth * idleHeights.length + gap * (idleHeights.length - 1),
      height: maxHeight,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = playing ? animation.value : 0.0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              for (var i = 0; i < idleHeights.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == idleHeights.length - 1 ? 0 : gap,
                  ),
                  child: Container(
                    width: barWidth,
                    height: playing ? _animatedHeight(t, i) : idleHeights[i],
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(barWidth / 2),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
