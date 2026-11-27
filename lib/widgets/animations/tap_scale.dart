// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/m3_motion.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 给任何可点击的东西加上「按下缩小 0.96、松手弹回」的反馈。
///
/// 两种用法：
/// * 只做视觉反馈（子节点自己处理点击，例如 [InkWell]、[IconButton]）：
///   不传 [onTap]，内部用 [Listener] 监听指针，**不参与手势竞技场**，
///   所以不会抢走子节点的点击；
/// * 自己处理点击：传 [onTap] / [onLongPress]，内部用 [GestureDetector]。
///
/// [haptic] 默认关闭 —— 只给「发送 / 点赞 / 撤回」这类主操作打开，
/// 列表滚动时每次都震会很难受。
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptic = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior behavior;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _press() {
    if (_pressed || !mounted) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    setState(() => _pressed = true);
  }

  void _release() {
    if (!_pressed || !mounted) return;
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = M3Motion.reduceMotionOf(context);
    final target = _pressed && !reduceMotion ? widget.scale : 1.0;
    final scale = AnimatedScale(
      scale: target,
      duration: M3Motion.of(
        context,
        _pressed ? M3Motion.short : M3Motion.medium,
      ),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    );

    // 没有自己的点击处理时只做视觉反馈：用 Listener 而不是 GestureDetector，
    // 这样子节点的 InkWell / IconButton 仍然能拿到这次点击。
    if (widget.onTap == null && widget.onLongPress == null) {
      return Listener(
        behavior: widget.behavior,
        onPointerDown: (_) => _press(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: scale,
      );
    }

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: widget.onTap == null
          ? null
          : () {
              _release();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: scale,
    );
  }
}
