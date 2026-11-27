// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/wechat/remark_service.dart';
import 'package:fluffychat/utils/wechat/room_kind.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 微信式「聊天信息」页：私聊是好友信息 + 聊天设置，群聊是群资料 + 群设置。
class ChatInfoPage extends StatefulWidget {
  final String roomId;

  const ChatInfoPage({required this.roomId, super.key});

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  bool _busy = false;

  Client get _client => Matrix.of(context).client;

  Room? get _room => _client.getRoomById(widget.roomId);

  Future<void> _setBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    AppToast.show(text);
  }

  Future<void> _setMuted(Room room, bool muted) => _setBusy(() async {
    await room.setPushRuleState(
      muted ? PushRuleState.dontNotify : PushRuleState.notify,
    );
  });

  Future<void> _setPinned(Room room, bool pinned) =>
      _setBusy(() async => room.setFavourite(pinned));

  Future<void> _setReminder(Room room, bool value) async {
    await WechatPrefs.setRoomReminder(room.id, value);
    if (mounted) setState(() {});
  }

  Future<void> _openSearch() => context.push('/rooms/${widget.roomId}/search');

  Future<void> _setRemark(Room room) async {
    final peer = room.directChatMatrixID;
    if (peer == null) return;
    await showRemarkDialog(
      context,
      peer,
      originalName: room.getLocalizedDisplayname(
        MatrixLocals(L10n.of(context)),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setBackground() => context.push('/rooms/settings/style');

  Future<void> _clearHistory(Room room) async {
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.clearChatHistory,
      message: l10n.clearChatBody,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok) return;
    await _setBusy(() async => room.forget());
    if (!mounted) return;
    context.go('/rooms');
  }

  Future<void> _complain() async {
    final l10n = L10n.of(context);
    _snack(l10n.complainThanks);
  }

  Future<void> _deleteFriend(Room room) async {
    final l10n = L10n.of(context);
    final peer = room.directChatMatrixID;
    if (peer == null) return;
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.deleteFriend,
      message: null,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok) return;
    await _setBusy(() async {
      await FriendsService(_client).removeFriendBothWays(peer);
    });
    if (!mounted) return;
    context.go('/contacts');
  }

  Future<void> _renameGroup(Room room) async {
    final l10n = L10n.of(context);
    final name = await showTextInputDialog(
      context: context,
      title: l10n.groupName,
      initialText: room.getLocalizedDisplayname(),
      hintText: l10n.groupName,
    );
    if (name == null || name.trim().isEmpty) return;
    await _setBusy(() async => room.setName(name.trim()));
  }

  Future<void> _setGroupNotice(Room room) async {
    final l10n = L10n.of(context);
    final notice = await showTextInputDialog(
      context: context,
      title: l10n.groupNotice,
      initialText: room.topic,
      hintText: l10n.groupNotice,
      maxLines: 4,
      minLines: 2,
    );
    if (notice == null) return;
    await _setBusy(() async => room.setDescription(notice.trim()));
  }

  Future<void> _setMyNickname(Room room) async {
    final l10n = L10n.of(context);
    final userId = _client.userID;
    if (userId == null) return;
    final current = room
        .getState(EventTypes.RoomMember, userId)
        ?.content
        .tryGet<String>('displayname');
    final name = await showTextInputDialog(
      context: context,
      title: l10n.myGroupNickname,
      initialText: current,
      hintText: l10n.myGroupNickname,
    );
    if (name == null) return;
    await _setBusy(() async {
      await _client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomMember,
        userId,
        {'membership': 'join', 'displayname': name.trim()},
      );
    });
  }

  Future<void> _showGroupQr(Room room) async {
    final l10n = L10n.of(context);
    final link = 'https://matrix.to/#/${room.id}';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.groupQrCode),
        content: SizedBox(
          width: 220,
          height: 220,
          child: PrettyQrView.data(data: link),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveGroup(Room room) async {
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.leaveGroup,
      message: l10n.leaveGroupBody,
      okLabel: l10n.leaveGroup,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok) return;
    await _setBusy(() async => room.leave());
    if (!mounted) return;
    context.go('/rooms');
  }

  Future<void> _toggleSavedToContacts(Room room, bool value) async {
    await WechatPrefs.setRoomSavedToContacts(room.id, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final room = _room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.chatInfo)),
        body: Center(child: Text(l10n.chatInfo)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatInfo), centerTitle: true),
      body: StreamBuilder(
        stream: _client.onSync.stream,
        builder: (context, _) {
          final isDirect = isSinglePeerChat(room);
          final muted = room.pushRuleState != PushRuleState.notify;
          return ListView(
            children: [
              if (isDirect)
                _DirectHeader(room: room)
              else
                _GroupHeader(
                  room: room,
                  onInvite: () => context.push('/rooms/${room.id}/invite'),
                ),
              const Divider(height: 1),
              if (!isDirect) ...[
                ListTile(
                  title: Text(l10n.groupName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          room.getLocalizedDisplayname(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_outlined),
                    ],
                  ),
                  onTap: () => _renameGroup(room),
                ),
                ListTile(
                  title: Text(l10n.groupQrCode),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: () => _showGroupQr(room),
                ),
                ListTile(
                  title: Text(l10n.groupNotice),
                  subtitle: room.topic.isEmpty ? null : Text(room.topic),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: () => _setGroupNotice(room),
                ),
                ListTile(
                  title: Text(l10n.myGroupNickname),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: () => _setMyNickname(room),
                ),
                const Divider(height: 1),
              ],
              if (isDirect)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.setRemark),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: () => _setRemark(room),
                ),
              ListTile(
                leading: const Icon(Icons.search_outlined),
                title: Text(l10n.searchChatHistory),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: _openSearch,
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.notifications_off_outlined),
                title: Text(l10n.chatMute),
                value: muted,
                onChanged: (value) => _setMuted(room, value),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.push_pin_outlined),
                title: Text(l10n.chatPin),
                value: room.isFavourite,
                onChanged: (value) => _setPinned(room, value),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.alarm_outlined),
                title: Text(l10n.chatRemind),
                subtitle: Text(
                  l10n.chatRemindHint,
                  style: theme.textTheme.bodySmall,
                ),
                value: WechatPrefs.roomReminder(room.id),
                onChanged: (value) => _setReminder(room, value),
              ),
              if (!isDirect)
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.contacts_outlined),
                  title: Text(l10n.saveToContacts),
                  value: WechatPrefs.roomSavedToContacts(room.id),
                  onChanged: (value) => _toggleSavedToContacts(room, value),
                ),
              ListTile(
                leading: const Icon(Icons.wallpaper_outlined),
                title: Text(l10n.chatBackground),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: _setBackground,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l10n.clearChatHistory,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => _clearHistory(room),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(l10n.complain),
                onTap: _complain,
              ),
              if (isDirect)
                ListTile(
                  leading: Icon(
                    Icons.person_remove_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    l10n.deleteFriend,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () => _deleteFriend(room),
                )
              else
                ListTile(
                  leading: Icon(
                    Icons.logout_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    l10n.leaveGroup,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () => _leaveGroup(room),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _DirectHeader extends StatelessWidget {
  final Room room;

  const _DirectHeader({required this.room});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final peer = room.directChatMatrixID ?? '';
    final remark = peer.isEmpty
        ? null
        : RemarkService(room.client).remarkOf(peer);
    final displayname =
        remark ?? room.getLocalizedDisplayname(MatrixLocals(l10n));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        spacing: 16,
        children: [
          Avatar(mxContent: room.avatar, name: displayname, size: 64),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  displayname,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${l10n.wechatId}: $peer',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final Room room;
  final VoidCallback onInvite;

  const _GroupHeader({required this.room, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final members = room.getParticipants();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final user in members.take(15))
                SizedBox(
                  width: 52,
                  child: Column(
                    spacing: 4,
                    children: [
                      Avatar(
                        mxContent: user.avatarUrl,
                        name: user.calcDisplayname(),
                        size: 44,
                      ),
                      Text(
                        user.calcDisplayname(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (room.canInvite)
                SizedBox(
                  width: 52,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onInvite,
                    child: Column(
                      spacing: 4,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.add, size: 22),
                        ),
                        Text(
                          l10n.groupInvite,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Text(
            room.getLocalizedDisplayname(),
            style: theme.textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}
