// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/m3_motion.dart';
import 'package:material_ui/material_ui.dart';

/// 会话列表「删除该聊天」的收起动画协调器。
///
/// 删除本身是 `room.forget()`（一步就把房间从列表里拿掉），这里把动作拆成两段：
/// 1. [collapse] 先把房间标记成「正在收起」，列表里那一行做 280ms 的高度收起 + 淡出，
///    其它行平滑上移；
/// 2. 动画播完由 [CollapsingRoomTile] 调 [finish]，此时才真正执行 `room.forget()`。
class RoomCollapse {
  RoomCollapse._();

  /// 正在收起/已收起的房间（收起后一直保持到 widget 卸载，避免回弹一帧）。
  static final Set<String> _collapsed = <String>{};

  /// 收起动画播完后要执行的动作（一般是 `room.forget()`）。
  static final Map<String, VoidCallback> _callbacks = <String, VoidCallback>{};

  /// 状态变化时 +1，列表项用 [ValueListenableBuilder] 监听。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool isCollapsing(String roomId) => _collapsed.contains(roomId);

  /// 开始收起 [roomId]，动画结束后执行 [onCollapsed]。
  static void collapse(String roomId, VoidCallback onCollapsed) {
    if (!_collapsed.add(roomId)) return;
    _callbacks[roomId] = onCollapsed;
    revision.value++;
  }

  /// 动画播完了：交出回调并执行。
  static void finish(String roomId) {
    final callback = _callbacks.remove(roomId);
    if (callback == null) return;
    callback();
  }

  /// 行被移除时清理状态。
  static void release(String roomId) {
    _callbacks.remove(roomId);
    if (_collapsed.remove(roomId)) revision.value++;
  }
}

/// 包住一个会话行：房间被标记为收起时做「高度收起 + 淡出」。
class CollapsingRoomTile extends StatefulWidget {
  const CollapsingRoomTile({
    super.key,
    required this.roomId,
    required this.child,
  });

  final String roomId;
  final Widget child;

  @override
  State<CollapsingRoomTile> createState() => _CollapsingRoomTileState();
}

class _CollapsingRoomTileState extends State<CollapsingRoomTile>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 280);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  late final Animation<double> _factor = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));

  @override
  void initState() {
    super.initState();
    RoomCollapse.revision.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    RoomCollapse.revision.removeListener(_sync);
    RoomCollapse.release(widget.roomId);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final collapsing = RoomCollapse.isCollapsing(widget.roomId);
    if (!collapsing) {
      if (_controller.value != 0) _controller.value = 0;
      return;
    }
    final duration = M3Motion.of(context, _duration);
    _controller.duration = duration;
    if (_controller.isAnimating) return;
    if (_controller.isCompleted) return;
    _controller.forward().whenComplete(() {
      if (!mounted) return;
      RoomCollapse.finish(widget.roomId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _factor,
      builder: (context, child) => Align(
        alignment: Alignment.topCenter,
        heightFactor: _factor.value.clamp(0.0, 1.0),
        child: Opacity(opacity: _factor.value.clamp(0.0, 1.0), child: child),
      ),
      child: widget.child,
    );
  }
}
