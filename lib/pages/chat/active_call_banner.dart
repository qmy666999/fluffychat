// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// 全局「正在通话中」横条。
///
/// 挂在 `MaterialApp.builder` 的根部（见 `fluffy_chat_app.dart`），所以在
/// 会话列表、通讯录、发现、我这些页面上都一直在。这样即使把通话页最小化、
/// 又一路返回退出聊天，也随时有一个入口能回到通话页或者直接挂断。
///
/// 显示时会把下面的 App 内容整体往下推（而不是盖在 AppBar 上），并且自己
/// 吃掉状态栏高度，避免文字被时间和信号图标压住。
class GlobalCallBannerHost extends StatefulWidget {
  const GlobalCallBannerHost({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalCallBannerHost> createState() => _GlobalCallBannerHostState();
}

class _GlobalCallBannerHostState extends State<GlobalCallBannerHost> {
  Timer? _ticker;
  CallSession? _call;

  @override
  void initState() {
    super.initState();
    _call = MatrixVoip.activeSession.value;
    MatrixVoip.activeSession.addListener(_onSessionChanged);
    MatrixVoip.pageVisible.addListener(_onSessionChanged);
    // 计时文字每秒变一次，只用监听器不会刷新，所以再加一个轻量计时器。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _call != null) setState(() {});
    });
  }

  @override
  void dispose() {
    MatrixVoip.activeSession.removeListener(_onSessionChanged);
    MatrixVoip.pageVisible.removeListener(_onSessionChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() => _call = MatrixVoip.activeSession.value);
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final visible = call != null && !MatrixVoip.pageOpen;
    return Column(
      children: [
        // 用一个占位代替条件插入，保证 Column 的第二个孩子（App 本体）位置
        // 不变，这样横幅出现/消失在 Navigator 上只是一次 resize，不会重建
        // 整个 App 的页面栈。
        if (visible) _CallBanner(call: call) else const SizedBox.shrink(),
        Expanded(
          // 横幅已经占掉状态栏那块高度，下面的页面就不用再留一次顶部安全区，
          // 否则会出现一条和状态栏一样高的空白。
          child: MediaQuery.removePadding(
            context: context,
            removeTop: visible,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _CallBanner extends StatelessWidget {
  const _CallBanner({required this.call});

  final CallSession call;

  String _durationText() {
    final startedAt = MatrixVoip.of(call.room.client)?.connectedAt;
    if (call.state != CallState.kConnected || startedAt == null) return '';
    final seconds = DateTime.now().difference(startedAt).inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _hangup() async {
    final voip = MatrixVoip.of(call.room.client);
    await voip?.hangup();
    await voip?.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final isVideo = call.type == CallType.kVideo;
    final duration = _durationText();
    final label = duration.isEmpty
        ? l10n.callWaiting
        : l10n.callInProgress(duration);

    return Material(
      color: scheme.secondaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 让出状态栏：背景色一直铺到屏幕最顶上，内容从状态栏下面开始。
          SizedBox(height: MediaQuery.paddingOf(context).top),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                  size: 18,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: MatrixVoip.openCallPage,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: MatrixVoip.openCallPage,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSecondaryContainer,
                  ),
                  child: Text(l10n.callBackToCall),
                ),
                IconButton(
                  tooltip: l10n.callHangup,
                  onPressed: _hangup,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  icon: const Icon(Icons.call_end, size: 20),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
