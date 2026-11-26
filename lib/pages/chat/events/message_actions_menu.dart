// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/favorites/favorites_service.dart';
import 'package:fluffychat/utils/wechat/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 长按消息时在气泡上方弹出的微信式宫格菜单。
///
/// 微信规则：
/// * 自己的消息 2 分钟内可以撤回，超过 5 分钟只能删除；
/// * 文字消息才有「复制」；
/// * 提醒（三档）目前只在 App 前台弹出（见 ReminderService 注释）。
Future<void> showMessageActionsMenu(
  BuildContext context, {
  required Event event,
  required void Function(Event) onSelect,
  required void Function() onReply,
}) async {
  final theme = Theme.of(context);
  final l10n = L10n.of(context);
  final isOwn = event.senderId == event.room.client.userID;
  final isFavorited = FavoritesService(
    event.room.client,
  ).contains(event.eventId);
  final age = DateTime.now().difference(event.originServerTs);
  final canRedact = isOwn && age.inMinutes < 5;
  final canDelete = age.inMinutes >= 2;
  final isText =
      event.messageType == MessageTypes.Text ||
      event.messageType == MessageTypes.Notice ||
      event.messageType == MessageTypes.Emote;

  final actions = <_MessageAction>[
    if (canRedact)
      _MessageAction(
        icon: Icons.undo_outlined,
        label: l10n.redactMessage,
        onTap: () => _confirmRedact(context, event),
      ),
    if (isText)
      _MessageAction(
        icon: Icons.copy_outlined,
        label: l10n.copy,
        onTap: () => _copy(context, event),
      ),
    _MessageAction(
      icon: Icons.checklist_outlined,
      label: l10n.messageMultiSelect,
      onTap: () => onSelect(event),
    ),
    _MessageAction(
      icon: Icons.format_quote_outlined,
      label: l10n.messageQuote,
      onTap: onReply,
    ),
    _MessageAction(
      icon: Icons.alarm_add_outlined,
      label: l10n.messageRemind,
      onTap: () => _pickReminder(context, event),
    ),
    _MessageAction(
      icon: isFavorited ? Icons.bookmark : Icons.bookmark_add_outlined,
      label: isFavorited ? l10n.messageFavorited : l10n.messageFavorite,
      onTap: () => _toggleFavorite(context, event),
    ),
    if (canDelete)
      _MessageAction(
        icon: Icons.delete_outline,
        label: l10n.delete,
        onTap: () => _confirmRedact(context, event),
      ),
  ];

  const itemWidth = 72.0;
  const itemHeight = 88.0;
  const menuPadding = 8.0;
  const perRow = 4;
  final rows = math.min(actions.length, perRow);
  final columns = (actions.length / perRow).ceil();
  final menuWidth = itemWidth * rows + menuPadding * 2;
  final menuHeight = itemHeight * columns;

  final screen = MediaQuery.sizeOf(context);
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final messageBox = context.findRenderObject() as RenderBox?;
  Rect? anchor;
  if (overlayBox != null && messageBox != null && messageBox.hasSize) {
    anchor =
        overlayBox.globalToLocal(messageBox.localToGlobal(Offset.zero)) &
        messageBox.size;
  }

  final safeTop = MediaQuery.paddingOf(context).top;
  var left = anchor == null
      ? (screen.width - menuWidth) / 2
      : (isOwn ? anchor.right - menuWidth - 12 : anchor.left + 56);
  left = left.clamp(8.0, math.max(8.0, screen.width - menuWidth - 8));
  var top = anchor == null
      ? screen.height / 2 - menuHeight / 2
      : anchor.top - menuHeight - 8;
  if (top < safeTop + 8) {
    top = anchor == null ? safeTop + 8 : anchor.bottom + 8;
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.cancel,
    barrierColor: theme.colorScheme.scrim.withAlpha(40),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, _) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(menuPadding),
              child: SizedBox(
                width: menuWidth - menuPadding * 2,
                child: Wrap(
                  children: [
                    for (final action in actions)
                      _MessageActionButton(
                        action: action,
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          action.onTap();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _MessageAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _MessageActionButton extends StatelessWidget {
  final _MessageAction action;
  final VoidCallback onTap;

  const _MessageActionButton({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  action.icon,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmRedact(BuildContext context, Event event) async {
  final l10n = L10n.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.redactConfirm),
      content: Text(l10n.redactMessageDescription),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.redactMessage),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await event.redactEvent();
}

void _copy(BuildContext context, Event event) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  Clipboard.setData(ClipboardData(text: event.body));
  messenger.showSnackBar(SnackBar(content: Text(l10n.copiedToClipboard)));
}

Future<void> _pickReminder(BuildContext context, Event event) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final now = DateTime.now();
  final choice = await showDialog<Duration>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.remindTitle),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(const Duration(hours: 1)),
          child: Text(l10n.remindIn1Hour),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(const Duration(days: 1)),
          child: Text(l10n.remindTomorrow),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(const Duration(days: 7)),
          child: Text(l10n.remindIn1Week),
        ),
      ],
    ),
  );
  if (choice == null) return;
  await ReminderService(event.room.client).add(event, now.add(choice));
  messenger.showSnackBar(SnackBar(content: Text(l10n.remindSet)));
}

Future<void> _toggleFavorite(BuildContext context, Event event) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final added = await FavoritesService(event.room.client).toggle(event);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        added ? l10n.messageFavorited : l10n.messageFavoriteRemoved,
      ),
    ),
  );
}
