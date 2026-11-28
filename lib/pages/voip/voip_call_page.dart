// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/voip/loading_dots.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:fluffychat/utils/wechat/remark_service.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 微信风格的全屏通话页（拨打 / 来电 / 通话中 / 结束）。
///
/// 硬性要求：不管数据是否正常，顶部栏和底部按钮区永远渲染，
/// 挂断按钮永远可用（不依赖 `call != null`）。
class VoipCallPage extends StatefulWidget {
  /// 由 `/call` 路由打开时为空，自动使用当前通话的管理器。
  final MatrixVoip? voip;

  const VoipCallPage({super.key, this.voip});

  @override
  State<VoipCallPage> createState() => _VoipCallPageState();
}

class _VoipCallPageState extends State<VoipCallPage> {
  MatrixVoip? _voip;

  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer _localRenderer = rtc.RTCVideoRenderer();
  bool _renderersReady = false;

  Timer? _ticker;
  Timer? _endTimer;
  DateTime? _connectedAt;
  rtc.MediaStream? _remoteStream;
  rtc.MediaStream? _localStream;

  /// 自己按的挂断/拒绝：用来区分「对方已拒绝」和「通话结束」。
  bool _endedLocally = false;
  bool _closing = false;

  CallSession? get _call => _voip?.activeCall.value;

  @override
  void initState() {
    super.initState();
    final session = MatrixVoip.activeSession.value;
    _voip =
        widget.voip ??
        MatrixVoip.activeVoip ??
        (session == null
            ? null
            : MatrixVoip.of(session.room.client) ??
                  MatrixVoip.ensure(session.room.client));
    MatrixVoip.activeSession.addListener(_onChanged);
    _voip?.revision.addListener(_onChanged);
    unawaited(_prepareRenderers());
    WakelockPlus.enable();
    _onChanged();
  }

  Future<void> _prepareRenderers() async {
    try {
      await _remoteRenderer.initialize();
      await _localRenderer.initialize();
      if (!mounted) return;
      _renderersReady = true;
      _syncStreams();
      setState(() {});
    } catch (e) {
      // 某些平台没有 WebRTC，通话照样可以挂断，不能因为初始化失败白屏。
      Logs().w('[VoIP] 视频渲染器初始化失败', e);
    }
  }

  @override
  void dispose() {
    MatrixVoip.pageOpen = false;
    MatrixVoip.activeSession.removeListener(_onChanged);
    _voip?.revision.removeListener(_onChanged);
    _ticker?.cancel();
    _endTimer?.cancel();
    WakelockPlus.disable();
    if (_renderersReady) {
      _remoteRenderer.dispose();
      _localRenderer.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final call = _call;
    _syncStreams();

    if (call?.state == CallState.kConnected && _connectedAt == null) {
      _connectedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }

    if (call != null && call.state == CallState.kEnded) {
      _ticker?.cancel();
      _endTimer ??= Timer(const Duration(milliseconds: 1500), _finish);
    }

    setState(() {});
  }

  void _syncStreams() {
    if (!_renderersReady) return;
    final call = _call;
    final remote = call?.remoteUserMediaStream?.stream;
    if (remote != _remoteStream) {
      _remoteStream = remote;
      _remoteRenderer.srcObject = remote;
    }
    final local = call?.localUserMediaStream?.stream;
    if (local != _localStream) {
      _localStream = local;
      _localRenderer.srcObject = local;
    }
  }

  String _durationString() {
    final connectedAt = _connectedAt;
    if (connectedAt == null) return '00:00';
    final seconds = DateTime.now().difference(connectedAt).inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// 1 对 1 房间里就是对方。
  User? _peerOf(Room room) {
    final peerId = room.directChatMatrixID;
    if (peerId == null) return null;
    for (final user in room.getParticipants()) {
      if (user.id == peerId) return user;
    }
    return null;
  }

  String _peerName(CallSession? call) {
    final room = call?.room;
    if (room == null) return '';
    final peer = _peerOf(room);
    // 备注优先，跟聊天列表保持一致（否则给好友起了备注，通话页还是原名）。
    final peerId = peer?.id ?? room.directChatMatrixID;
    final remark = peerId == null
        ? null
        : RemarkService(room.client).remarkOf(peerId);
    return remark ?? peer?.calcDisplayname() ?? room.getLocalizedDisplayname();
  }

  bool _isIncoming(CallSession? call) =>
      call != null &&
      !call.isOutgoing &&
      !call.answeredByUs &&
      call.state != CallState.kEnded;

  bool _isWaiting(CallSession? call) =>
      call != null &&
      call.state != CallState.kEnded &&
      call.state != CallState.kConnected &&
      call.state != CallState.kRinging;

  String _statusText(L10n l10n, CallSession? call) {
    if (call == null) return l10n.callConnecting;
    switch (call.state) {
      case CallState.kEnded:
        switch (call.hangupReason) {
          case CallErrorCode.inviteTimeout:
            return call.isOutgoing ? l10n.callNoAnswer : l10n.callMissed;
          case CallErrorCode.userBusy:
            return l10n.callBusy;
          case CallErrorCode.userHangup:
            if (call.isOutgoing && !call.answeredByUs && !_endedLocally) {
              return l10n.callRejected;
            }
            return l10n.callEnded;
          default:
            return call.hangupReason == null ? l10n.callEnded : l10n.callFailed;
        }
      case CallState.kConnected:
        return _durationString();
      default:
        if (_isIncoming(call)) {
          final name = _peerName(call);
          return call.type == CallType.kVideo
              ? l10n.callInviteVideo(name)
              : l10n.callInviteVoice(name);
        }
        if (call.isOutgoing) return l10n.callWaiting;
        return l10n.callConnecting;
    }
  }

  // ---------------------------------------------------------------------------
  // 操作
  // ---------------------------------------------------------------------------

  Future<void> _hangup() async {
    if (_closing) return;
    _closing = true;
    _endedLocally = true;
    final voip = _voip ?? MatrixVoip.activeVoip;
    try {
      await voip?.hangup();
    } catch (e) {
      Logs().w('[VoIP] 挂断失败', e);
    }
    await _finish();
  }

  Future<void> _reject() async {
    if (_closing) return;
    _closing = true;
    _endedLocally = true;
    final voip = _voip ?? MatrixVoip.activeVoip;
    try {
      await voip?.reject();
    } catch (e) {
      Logs().w('[VoIP] 拒绝来电失败', e);
    }
    await _finish();
  }

  Future<void> _answer() async {
    final voip = _voip ?? MatrixVoip.activeVoip;
    try {
      await voip?.answer();
    } catch (e) {
      Logs().w('[VoIP] 接听失败', e);
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    _endTimer?.cancel();
    _endTimer = null;
    _ticker?.cancel();
    final voip = _voip ?? MatrixVoip.activeVoip;
    Logs().i('[VoIP] 通话结束，释放资源');
    try {
      await voip?.clear();
    } catch (e) {
      Logs().w('[VoIP] 释放资源失败', e);
    }
    MatrixVoip.pageOpen = false;
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _minimize() {
    MatrixVoip.pageOpen = false;
    Navigator.of(context).maybePop();
  }

  void _showVideoUnsupported() {
    AppToast.show(L10n.of(context).callVideoSwitchUnavailable);
  }

  // ---------------------------------------------------------------------------
  // 界面
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final voip = _voip ?? MatrixVoip.activeVoip;
    final call = voip?.activeCall.value;
    final isVideo = call?.type == CallType.kVideo;
    final connected = call?.state == CallState.kConnected;

    // 页面统一深色，但颜色仍从主题派生，不写死。
    final scheme = ColorScheme.fromSeed(
      seedColor: theme.colorScheme.primary,
      brightness: Brightness.dark,
    );

    return Theme(
      data: theme.copyWith(colorScheme: scheme),
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        body: Stack(
          children: [
            if (isVideo && connected && _remoteStream != null)
              Positioned.fill(
                child: rtc.RTCVideoView(
                  _remoteRenderer,
                  objectFit:
                      rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: false,
                ),
              )
            else
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.surfaceContainerHigh,
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  // 1. 顶部栏：永远渲染。
                  _buildTopBar(scheme, l10n),
                  // 2. 中间内容：可能为空，出问题也只影响这一块。
                  Expanded(child: _buildMiddle(scheme, l10n, call, isVideo)),
                  // 3. 底部按钮：永远渲染，且不依赖 call != null。
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 32),
                    child: _buildButtons(scheme, l10n, voip, call, isVideo),
                  ),
                ],
              ),
            ),
            if (isVideo && connected && _localStream != null)
              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
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

  Widget _buildTopBar(ColorScheme scheme, L10n l10n) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.callMinimize,
            onPressed: _minimize,
            icon: Icon(
              Icons.picture_in_picture_alt_outlined,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddle(
    ColorScheme scheme,
    L10n l10n,
    CallSession? call,
    bool isVideo,
  ) {
    if (call == null) {
      return Center(
        child: CircularProgressIndicator.adaptive(
          valueColor: AlwaysStoppedAnimation(scheme.onSurfaceVariant),
        ),
      );
    }

    final connected = call.state == CallState.kConnected;
    final name = _peerName(call);
    final ended = call.state == CallState.kEnded;
    final peer = _peerOf(call.room);
    final waiting = _isWaiting(call) || _isIncoming(call);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isVideo || !connected)
          Avatar(
            mxContent: peer?.avatarUrl,
            name: name,
            client: call.room.client,
            size: 120,
          ),
        if (!isVideo || !connected) const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _statusText(l10n, call),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
        if (waiting && !ended) ...[
          const SizedBox(height: 16),
          LoadingDots(color: scheme.onSurfaceVariant),
        ],
      ],
    );
  }

  Widget _buildButtons(
    ColorScheme scheme,
    L10n l10n,
    MatrixVoip? voip,
    CallSession? call,
    bool isVideo,
  ) {
    final incoming = _isIncoming(call);
    final connected = call?.state == CallState.kConnected;
    final ended = call?.state == CallState.kEnded;
    final muted = call?.isMicrophoneMuted ?? false;
    final speaker = voip?.speakerOn ?? false;
    final cameraMuted = call?.isLocalVideoMuted ?? false;

    if (incoming) {
      return _actionRow(scheme, [
        _CallAction(
          icon: Icons.call_end,
          label: l10n.callDecline,
          destructive: true,
          onTap: _reject,
        ),
        _CallAction(
          icon: Icons.call,
          label: l10n.callAnswer,
          affirmative: true,
          onTap: _answer,
        ),
      ], size: 72);
    }

    final actions = <_CallAction>[
      _CallAction(
        icon: muted ? Icons.mic_off : Icons.mic,
        label: muted ? l10n.callMicOff : l10n.callMicOn,
        onTap: () => voip?.toggleMute(),
      ),
      _CallAction(
        icon: Icons.call_end,
        label: connected ? l10n.callHangup : l10n.callCancel,
        destructive: true,
        onTap: _hangup,
      ),
      _CallAction(
        icon: speaker ? Icons.volume_up : Icons.volume_off,
        label: speaker ? l10n.callSpeakerOn : l10n.callSpeakerOff,
        onTap: () => voip?.toggleSpeaker(),
      ),
      if (connected && !isVideo)
        _CallAction(
          icon: Icons.videocam_outlined,
          label: l10n.callSwitchVideo,
          onTap: _showVideoUnsupported,
        ),
      if (connected && isVideo) ...[
        _CallAction(
          icon: cameraMuted ? Icons.videocam_off : Icons.videocam,
          label: cameraMuted ? l10n.callCameraOff : l10n.callCameraOn,
          onTap: () => voip?.toggleVideo(),
        ),
        _CallAction(
          icon: Icons.cameraswitch_outlined,
          label: l10n.callSwitchCamera,
          onTap: () => voip?.switchCamera(),
        ),
      ],
    ];

    if (ended && !_endedLocally) {
      // 对方挂断/无人接听：只留一个挂断按钮，避免用户卡住。
      return _actionRow(scheme, [
        _CallAction(
          icon: Icons.call_end,
          label: l10n.callHangup,
          destructive: true,
          onTap: _hangup,
        ),
      ], size: 64);
    }

    return _actionRow(scheme, actions, size: 64);
  }

  Widget _actionRow(
    ColorScheme scheme,
    List<_CallAction> actions, {
    required double size,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final action in actions)
          Expanded(
            child: _ActionButton(action: action, scheme: scheme, size: size),
          ),
      ],
    );
  }
}

class _CallAction {
  const _CallAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.affirmative = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final bool affirmative;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.scheme,
    required this.size,
  });

  final _CallAction action;
  final ColorScheme scheme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = action.destructive
        ? scheme.error
        : action.affirmative
        ? scheme.primary
        : scheme.surfaceContainerHigh;
    final foreground = action.destructive
        ? scheme.onError
        : action.affirmative
        ? scheme.onPrimary
        : scheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: action.onTap ?? () {},
              child: Icon(action.icon, size: size * 0.42, color: foreground),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}
