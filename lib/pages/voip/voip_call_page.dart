// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 微信风格的全屏通话页。
///
/// 语音通话显示头像 + 状态；视频通话把对方画面铺满，自己画面缩在右上角。
/// 页面只读 [MatrixVoip.activeCall]，通话结束时延迟 1.5 秒再清空，避免闪一下。
class VoipCallPage extends StatefulWidget {
  final MatrixVoip voip;

  const VoipCallPage({super.key, required this.voip});

  @override
  State<VoipCallPage> createState() => _VoipCallPageState();
}

class _VoipCallPageState extends State<VoipCallPage> {
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer _localRenderer = rtc.RTCVideoRenderer();

  Timer? _durationTimer;
  Timer? _endTimer;
  DateTime? _connectedAt;
  rtc.MediaStream? _remoteStream;
  rtc.MediaStream? _localStream;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _localRenderer.initialize();
    widget.voip.revision.addListener(_onRevision);
    _onRevision();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    widget.voip.revision.removeListener(_onRevision);
    _durationTimer?.cancel();
    _endTimer?.cancel();
    if (_connectedAt != null) WakelockPlus.disable();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  void _onRevision() {
    final call = widget.voip.activeCall.value;
    if (call == null) return;

    final remote = call.remoteUserMediaStream?.stream;
    if (remote != _remoteStream) {
      _remoteStream = remote;
      _remoteRenderer.srcObject = remote;
    }
    final local = call.localUserMediaStream?.stream;
    if (local != _localStream) {
      _localStream = local;
      _localRenderer.srcObject = local;
    }

    if (call.state == CallState.kConnected && _connectedAt == null) {
      _connectedAt = DateTime.now();
      _durationTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }

    if (call.state == CallState.kEnded && _endTimer == null) {
      _endTimer = Timer(const Duration(milliseconds: 1500), () {
        widget.voip.clear();
      });
    }

    if (mounted) setState(() {});
  }

  String _durationString() {
    final connectedAt = _connectedAt;
    if (connectedAt == null) return '';
    final seconds = DateTime.now().difference(connectedAt).inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  /// 1 对 1 房间里就是对方；群组房间这一版不发起通话，兜底返回 null。
  User? _peerOf(Room room) {
    final peerId = room.directChatMatrixID;
    if (peerId == null) return null;
    for (final user in room.getParticipants()) {
      if (user.id == peerId) return user;
    }
    return null;
  }

  String _statusText(BuildContext context, CallSession call, L10n l10n) {
    final isVideo = call.type == CallType.kVideo;
    switch (call.state) {
      case CallState.kEnded:
        switch (call.hangupReason) {
          case CallErrorCode.inviteTimeout:
            return call.isOutgoing ? l10n.callNoAnswer : l10n.callMissed;
          case CallErrorCode.userBusy:
            return l10n.callBusy;
          case CallErrorCode.userHangup:
            return l10n.callEnded;
          default:
            return call.hangupReason == null ? l10n.callEnded : l10n.callFailed;
        }
      case CallState.kConnected:
        return _durationString();
      default:
        if (!call.isOutgoing && !call.answeredByUs) {
          return isVideo ? l10n.callIncomingVideo : l10n.callIncomingVoice;
        }
        if (call.isOutgoing) return l10n.callWaiting;
        return l10n.callConnecting;
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.voip.activeCall.value;
    if (call == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    // 通话页统一用深色，但仍然从当前主题的种子色派生，避免写死颜色。
    final scheme = ColorScheme.fromSeed(
      seedColor: theme.colorScheme.primary,
      brightness: Brightness.dark,
    );

    final isVideo = call.type == CallType.kVideo;
    final room = call.room;
    final peer = _peerOf(room);
    final name = peer?.calcDisplayname() ?? room.getLocalizedDisplayname();
    final incoming =
        !call.isOutgoing &&
        !call.answeredByUs &&
        call.state != CallState.kEnded;

    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      ),
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        body: Stack(
          children: [
            if (isVideo && _remoteStream != null)
              Positioned.fill(
                child: rtc.RTCVideoView(
                  _remoteRenderer,
                  objectFit:
                      rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: false,
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  if (!isVideo)
                    Avatar(
                      mxContent: peer?.avatarUrl,
                      name: name,
                      client: room.client,
                      size: 128,
                    ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusText(context, call, l10n),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (incoming)
                    _IncomingControls(
                      scheme: scheme,
                      l10n: l10n,
                      onDecline: widget.voip.reject,
                      onAnswer: widget.voip.answer,
                    )
                  else
                    _CallControls(
                      scheme: scheme,
                      l10n: l10n,
                      voip: widget.voip,
                      call: call,
                      isVideo: isVideo,
                    ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
            if (isVideo && _localStream != null)
              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    height: 136,
                    child: rtc.RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncomingControls extends StatelessWidget {
  final ColorScheme scheme;
  final L10n l10n;
  final Future<void> Function() onDecline;
  final Future<void> Function() onAnswer;

  const _IncomingControls({
    required this.scheme,
    required this.l10n,
    required this.onDecline,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: Icons.call_end_rounded,
          label: l10n.callDecline,
          background: scheme.error,
          foreground: scheme.onError,
          onTap: onDecline,
        ),
        _CallButton(
          icon: Icons.call_rounded,
          label: l10n.callAnswer,
          background: scheme.primary,
          foreground: scheme.onPrimary,
          onTap: onAnswer,
        ),
      ],
    );
  }
}

class _CallControls extends StatelessWidget {
  final ColorScheme scheme;
  final L10n l10n;
  final MatrixVoip voip;
  final CallSession call;
  final bool isVideo;

  const _CallControls({
    required this.scheme,
    required this.l10n,
    required this.voip,
    required this.call,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    final muted = call.isMicrophoneMuted;
    final cameraOff = call.isLocalVideoMuted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: muted ? l10n.callUnmute : l10n.callMute,
          background: muted ? scheme.onSurface : scheme.surfaceContainerHighest,
          foreground: muted ? scheme.surface : scheme.onSurface,
          onTap: voip.toggleMute,
        ),
        if (isVideo)
          _CallButton(
            icon: cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            label: cameraOff ? l10n.callCameraOn : l10n.callCameraOff,
            background: cameraOff
                ? scheme.onSurface
                : scheme.surfaceContainerHighest,
            foreground: cameraOff ? scheme.surface : scheme.onSurface,
            onTap: voip.toggleVideo,
          ),
        if (isVideo)
          _CallButton(
            icon: Icons.cameraswitch_rounded,
            label: l10n.callSwitchCamera,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurface,
            onTap: voip.switchCamera,
          ),
        _CallButton(
          icon: voip.speakerOn
              ? Icons.volume_up_rounded
              : Icons.volume_down_rounded,
          label: voip.speakerOn ? l10n.callSpeakerOff : l10n.callSpeaker,
          background: voip.speakerOn
              ? scheme.onSurface
              : scheme.surfaceContainerHighest,
          foreground: voip.speakerOn ? scheme.surface : scheme.onSurface,
          onTap: voip.toggleSpeaker,
        ),
        _CallButton(
          icon: Icons.call_end_rounded,
          label: l10n.callHangup,
          background: scheme.error,
          foreground: scheme.onError,
          onTap: voip.hangup,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Future<void> Function() onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: foreground, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ],
    );
  }
}
