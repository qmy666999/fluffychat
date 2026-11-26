// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:material_ui/material_ui.dart';

class SwipeAction {
  SwipeAction({
    required this.label,
    required this.color,
    required this.onPressed,
    this.foreground,
  });

  final String label;
  final Color color;
  final Color? foreground;
  final VoidCallback onPressed;
}

/// 会话列表从左往右滑出来的两个按钮。
class SwipeActionRow extends StatelessWidget {
  const SwipeActionRow({
    super.key,
    required this.itemKey,
    required this.child,
    required this.actions,
    this.actionWidth = 76,
  });

  final Object itemKey;
  final Widget child;
  final List<SwipeAction> actions;

  final double actionWidth;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return child;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ratio = width <= 0
            ? 0.4
            : ((actions.length * actionWidth) / width).clamp(0.18, 0.8);
        return Slidable(
          key: ValueKey(itemKey),
          groupTag: 'chat_list',
          closeOnScroll: true,
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: ratio,
            children: [
              for (final action in actions)
                SlidableAction(
                  onPressed: (_) => action.onPressed(),
                  backgroundColor: action.color,
                  foregroundColor: action.foreground ?? scheme.onError,
                  label: action.label,
                  flex: 2,
                ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}
