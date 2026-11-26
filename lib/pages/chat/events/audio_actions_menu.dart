// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/favorites/favorites_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 长按语音消息弹出的微信式宫格菜单。
///
/// 只放真的能用的项：撤回（仅自己发的）、多选、引用、收藏。
/// 听筒播放 / 背景播放 / 转文字 / 提醒 / 连续朗读这些做不了的，一律不出现。
Future<void> showAudioActionsMenu(
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

  final actions = <_AudioAction>[
    if (isOwn)
      _AudioAction(
        icon: Icons.undo_outlined,
        label: l10n.redactMessage,
        onTap: () => _confirmRedact(context, event),
      ),
    _AudioAction(
      icon: Icons.checklist_outlined,
      label: l10n.audioMultiSelect,
      onTap: () => onSelect(event),
    ),
    _AudioAction(
      icon: Icons.format_quote_outlined,
      label: l10n.audioQuote,
      onTap: onReply,
    ),
    _AudioAction(
      icon: isFavorited ? Icons.bookmark : Icons.bookmark_add_outlined,
      label: isFavorited ? l10n.audioFavorited : l10n.audioFavorite,
      onTap: () => _toggleFavorite(context, event),
    ),
  ];

  const itemWidth = 72.0;
  const menuPadding = 8.0;
  const menuHeight = 88.0;
  final menuWidth = itemWidth * actions.length + menuPadding * 2;

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
  left = left.clamp(8.0, screen.width - menuWidth - 8);
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions)
                    _AudioActionButton(
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
      ],
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _AudioAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AudioAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _AudioActionButton extends StatelessWidget {
  final _AudioAction action;
  final VoidCallback onTap;

  const _AudioActionButton({required this.action, required this.onTap});

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

Future<void> _toggleFavorite(BuildContext context, Event event) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final added = await FavoritesService(event.room.client).toggle(event);
  messenger.showSnackBar(
    SnackBar(
      content: Text(added ? l10n.audioFavorited : l10n.audioFavoriteRemoved),
    ),
  );
}
