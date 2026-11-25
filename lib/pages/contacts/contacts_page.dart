// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_bottom_bar.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 通讯录：新的朋友 + 好友名单。
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  bool _syncStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_syncStarted) return;
    _syncStarted = true;
    FriendsSync.start(Matrix.of(context).client);
  }

  Future<void> _openChat(String userId) async {
    final service = FriendsService(Matrix.of(context).client);
    try {
      final roomId = await service.openDirectChat(userId);
      if (!mounted) return;
      context.go('/rooms/$roomId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).openChatFailed(e.toString()))),
      );
    }
  }

  /// 下拉刷新：无视节流立刻扫一次房间，把对方「已接受」的申请捞回来。
  Future<void> _refresh() async {
    final client = Matrix.of(context).client;
    await FriendsSync.scanNow(client);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final service = FriendsService(client);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bottomTabContacts),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: l10n.addToContacts,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => context.push('/contacts/add'),
          ),
        ],
      ),
      bottomNavigationBar: const ChatListBottomBar(currentIndex: 1),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) {
          final data = service.load();
          // 好友列表里不能出现自己。
          final friends = data.friends
              .where((friend) => friend.userId != client.userID)
              .toList()
            ..sort(
              (a, b) =>
                  a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            );
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: Text(l10n.newFriends),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (data.pendingCount > 0)
                      Badge(
                        label: Text(data.pendingCount.toString()),
                      ),
                    const Icon(Icons.chevron_right_outlined),
                  ],
                ),
                onTap: () => context.push('/contacts/new'),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.friendsSection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.noFriendsYet,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final friend in friends)
                ListTile(
                  leading: Avatar(
                    mxContent: _parseUri(friend.avatarUrl),
                    name: friend.title,
                    size: Avatar.defaultSize * 0.9,
                  ),
                  title: Text(friend.title, maxLines: 1),
                  // 好友行只显示名字，不显示 Matrix ID（ID 在资料页里看）
                  trailing: const Icon(Icons.chat_bubble_outline),
                  onTap: () => _openChat(friend.userId),
                  onLongPress: () => context.push(
                    '/contacts/friend?userId=${Uri.encodeComponent(friend.userId)}',
                  ),
                ),
            ],
            ),
          );
        },
      ),
    );
  }
}

Uri? _parseUri(String? value) =>
    value == null || value.isEmpty ? null : Uri.tryParse(value);
