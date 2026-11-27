// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:fluffychat/config/m3_motion.dart';
import 'package:fluffychat/widgets/animations/shatter_layer.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 撤回一条消息时的「破碎」动画。
///
/// 做法：先把气泡用 [RenderRepaintBoundary.toImage] 拍成一张位图，
/// 交给 [ShatterLayer] 切成 48 片飞散 + 自转 + 淡出（450ms），
/// 与此同时把真实气泡透明掉，动画结束再真正发撤回事件 ——
/// 这样气泡不会先消失、碎片才出现。
///
/// 只有「自己点撤回」会走这条路（那一刻气泡还在屏幕上，能拍到图）；
/// 别人的撤回没有可拍的画面，直接消失。
class MessageShatter {
  MessageShatter._();

  /// 气泡的「可拍快照」句柄：按 eventId 存一个 [GlobalKey]。
  static final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  /// 正在播放破碎动画、需要暂时隐形的消息。
  static final Set<String> _hidden = <String>{};

  /// 隐形状态变化时 +1，气泡外层用 [ValueListenableBuilder] 监听。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 取（必要时创建）某条消息气泡的 key。
  ///
  /// 会话里渲染过的消息都会留下一份，超过 400 个就把已经不在屏幕上的清掉，
  /// 避免长会话列表把 Map 撑大。
  static GlobalKey keyFor(String eventId) {
    if (_keys.length > 400) {
      _keys.removeWhere(
        (id, key) => id != eventId && key.currentContext == null,
      );
    }
    return _keys.putIfAbsent(eventId, GlobalKey.new);
  }

  static bool isHidden(String eventId) => _hidden.contains(eventId);

  static void _setHidden(String eventId, bool hidden) {
    final changed = hidden ? _hidden.add(eventId) : _hidden.remove(eventId);
    if (changed) revision.value++;
  }

  /// 播放破碎动画，然后撤回。
  static Future<void> shatterAndRedact(
    BuildContext context,
    Event event, {
    String? reason,
  }) async {
    final eventId = event.eventId;
    final reduceMotion = M3Motion.reduceMotionOf(context);
    final boundary = _keys[eventId]?.currentContext?.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    // 系统要求减少动效、或者这一条没被画出来（例如在屏幕外）：直接撤回。
    if (reduceMotion || boundary is! RenderRepaintBoundary || overlay == null) {
      await event.redactEvent(reason: reason);
      return;
    }

    final rect = boundary.localToGlobal(Offset.zero) & boundary.size;
    ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: 2);
    } catch (error, stackTrace) {
      Logs().w('[shatter] 截图失败，直接撤回', error, stackTrace);
      await event.redactEvent(reason: reason);
      return;
    }

    // 先藏掉真实气泡（保留占位，避免下面的消息立刻上移），再让碎片飞。
    _setHidden(eventId, true);
    final entry = OverlayEntry(
      builder: (_) =>
          ShatterLayer(image: image, rect: rect, duration: M3Motion.long),
    );
    overlay.insert(entry);
    HapticFeedback.mediumImpact();

    await Future<void>.delayed(M3Motion.long);
    entry.remove();
    entry.dispose();
    try {
      await event.redactEvent(reason: reason);
    } finally {
      _setHidden(eventId, false);
    }
  }
}
