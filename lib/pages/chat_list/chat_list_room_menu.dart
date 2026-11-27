// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/room_collapse.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 会话列表长按弹出的微信式气泡菜单：标为未读 / 置顶该聊天 / 删除该聊天。
///
/// 故意只放这三项（微信就这三项）。更多操作（免打扰、归档等）走聊天信息页。
Future<void> showChatListRoomMenu(BuildContext context, Room room) async {
  final l10n = L10n.of(context);
  final theme = Theme.of(context);

  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  RelativeRect position;
  if (box != null && overlay != null && box.hasSize) {
    final topLeft = overlay.globalToLocal(box.localToGlobal(Offset.zero));
    position = RelativeRect.fromLTRB(
      topLeft.dx + 24,
      topLeft.dy,
      overlay.size.width - topLeft.dx - 24,
      overlay.size.height - topLeft.dy,
    );
  } else {
    position = const RelativeRect.fromLTRB(24, 120, 24, 120);
  }

  final action = await showMenu<_RoomMenuAction>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(
        value: _RoomMenuAction.markUnread,
        child: Row(
          spacing: 8,
          children: [
            Icon(
              room.markedUnread || room.notificationCount > 0
                  ? Icons.mark_chat_read_outlined
                  : Icons.mark_chat_unread_outlined,
              size: 18,
            ),
            Text(
              room.markedUnread || room.notificationCount > 0
                  ? l10n.markAsRead
                  : l10n.chatMenuMarkUnread,
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: _RoomMenuAction.pin,
        child: Row(
          spacing: 8,
          children: [
            Icon(
              room.isFavourite ? Icons.push_pin : Icons.push_pin_outlined,
              size: 18,
            ),
            Text(room.isFavourite ? l10n.unpin : l10n.chatMenuPin),
          ],
        ),
      ),
      PopupMenuItem(
        value: _RoomMenuAction.delete,
        child: Row(
          spacing: 8,
          children: [
            Icon(
              Icons.delete_outline,
              size: 18,
              color: theme.colorScheme.error,
            ),
            Text(
              l10n.chatMenuDelete,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ),
      ),
    ],
  );

  if (!context.mounted) return;
  switch (action) {
    case _RoomMenuAction.markUnread:
      final markUnread = !(room.markedUnread || room.notificationCount > 0);
      await room.markUnread(markUnread);
      AppToast.show(
        markUnread ? l10n.toastMarkedAsUnread : l10n.toastMarkedAsRead,
      );
    case _RoomMenuAction.pin:
      final pin = !room.isFavourite;
      await room.setFavourite(pin);
      AppToast.show(pin ? l10n.toastChatPinned : l10n.toastChatUnpinned);
    case _RoomMenuAction.delete:
      final result = await showOkCancelAlertDialog(
        context: context,
        title: l10n.chatDeleteConfirmTitle,
        message: l10n.chatDeleteConfirmBody,
        okLabel: l10n.delete,
        cancelLabel: l10n.cancel,
        isDestructive: true,
      );
      if (result != OkCancelResult.ok) return;
      // 先播 280ms 的收起动画，动画结束才真正 forget。
      RoomCollapse.collapse(room.id, room.forget);
    case null:
      return;
  }
}

enum _RoomMenuAction { markUnread, pin, delete }
