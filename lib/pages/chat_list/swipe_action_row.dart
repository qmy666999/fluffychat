// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// 左滑露出的一个操作按钮。
class SwipeAction {
  final String label;
  final Color color;
  final Color? foreground;
  final VoidCallback onPressed;

  const SwipeAction({
    required this.label,
    required this.color,
    this.foreground,
    required this.onPressed,
  });
}

/// 微信式左滑：把整行往左拖，右侧露出操作按钮。
///
/// 只实现「拖到一半会自动吸附」和「点按钮后自动收回」两个行为，
/// 不做整行滑走删除（微信也不是整行滑走）。
class SwipeActionRow extends StatefulWidget {
  final Widget child;
  final List<SwipeAction> actions;
  final double actionWidth;

  const SwipeActionRow({
    required this.child,
    required this.actions,
    this.actionWidth = 76,
    super.key,
  });

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow> {
  double _offset = 0;
  bool _dragging = false;

  double get _maxOffset => widget.actions.length * widget.actionWidth;

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.actions.isEmpty) return;
    setState(() {
      _dragging = true;
      _offset = (_offset - details.delta.dx).clamp(0.0, _maxOffset);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (widget.actions.isEmpty) return;
    // 甩得快就按方向直接开/关，否则看是否过半。
    final velocity = details.primaryVelocity ?? 0;
    final bool shouldOpen;
    if (velocity < -120) {
      shouldOpen = true;
    } else if (velocity > 120) {
      shouldOpen = false;
    } else {
      shouldOpen = _offset > _maxOffset / 3;
    }
    setState(() {
      _dragging = false;
      _offset = shouldOpen ? _maxOffset : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    final theme = Theme.of(context);
    final revealed = _offset > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in widget.actions)
                    SizedBox(
                      width: widget.actionWidth,
                      child: Material(
                        color: action.color,
                        child: InkWell(
                          onTap: () {
                            _close();
                            action.onPressed();
                          },
                          child: Center(
                            child: Text(
                              action.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onError,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            GestureDetector(
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: AnimatedSlide(
                offset: Offset(-_offset / (width == 0 ? 1 : width), 0),
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: Material(
                  color: theme.colorScheme.surface,
                  child: Stack(
                    children: [
                      AbsorbPointer(
                        absorbing: revealed || _dragging,
                        child: widget.child,
                      ),
                      // 露出按钮时，点行的内容只收起，不打开聊天。
                      if (revealed)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _close,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
