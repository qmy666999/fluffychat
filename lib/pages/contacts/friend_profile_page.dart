// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 好友资料页：备注、发消息、删除好友。
class FriendProfilePage extends StatefulWidget {
  final String userId;

  const FriendProfilePage({required this.userId, super.key});

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  FriendsService get _service => FriendsService(Matrix.of(context).client);

  Future<void> _sendMessage() async {
    try {
      final roomId = await _service.openDirectChat(widget.userId);
      if (!mounted) return;
      context.go('/rooms/$roomId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).openChatFailed(e.toString()))),
      );
    }
  }

  Future<void> _setRemark() async {
    final l10n = L10n.of(context);
    final friend = _service.load().friend(widget.userId);
    final remark = await showTextInputDialog(
      context: context,
      title: l10n.setRemark,
      initialText: friend?.remark ?? '',
      hintText: l10n.remarkHint,
    );
    if (remark == null) return;
    await _service.setRemark(widget.userId, remark);
    if (mounted) setState(() {});
  }

  Future<void> _remove() async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.removeFriend,
      message: l10n.removeFriendConfirm,
      okLabel: l10n.remove,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    await _service.removeFriendBothWays(widget.userId);
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final friend = _service.load().friend(widget.userId);
    final title = friend?.title ?? widget.userId;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.friendProfile)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Avatar(
              mxContent: _uri(friend?.avatarUrl),
              name: title,
              size: Avatar.defaultSize * 2,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              widget.userId,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if ((friend?.remark ?? '').trim().isNotEmpty)
            Center(
              child: Text(
                friend!.remark,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(l10n.sendMessage),
            onTap: _sendMessage,
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.setRemark),
            subtitle: Text(
              (friend?.remark ?? '').isEmpty
                  ? l10n.remarkHint
                  : friend!.remark,
            ),
            onTap: _setRemark,
          ),
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
            title: Text(
              l10n.removeFriend,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: _remove,
          ),
        ],
      ),
    );
  }
}

Uri? _uri(String? value) =>
    value == null || value.isEmpty ? null : Uri.tryParse(value);
