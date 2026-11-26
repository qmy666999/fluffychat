// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 底部四项导航：微信 / 通讯录 / 发现 / 我。
///
/// 四个页面都是平级 tab：点击用 `go` 切换（不压栈），所以二级页面不会出现
/// 返回箭头，底部导航也一直都在。
class ChatListBottomBar extends StatelessWidget {
  final ChatListController? controller;
  final int currentIndex;

  const ChatListBottomBar({this.controller, this.currentIndex = 0, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                child: _BottomBarItem(
                  label: L10n.of(context).bottomTabChats,
                  selected: currentIndex == 0,
                  onTap: () => context.go('/rooms'),
                  icon: StreamBuilder(
                    stream: client.onSync.stream,
                    builder: (context, _) {
                      // 只统计可见会话：朋友圈房间被隐藏了，它的未读不能算进这个角标，
                      // 否则会出现「有数字但列表里没有对应会话」。
                      final moments = MomentsService(client);
                      final unread = client.rooms
                          .where(
                            (room) =>
                                room.membership == Membership.join &&
                                !moments.hidesRoom(room) &&
                                // 免打扰的会话只在该会话上显示红点，不进这个总数。
                                room.pushRuleState == PushRuleState.notify,
                          )
                          .fold<int>(
                            0,
                            (sum, room) => sum + room.notificationCount,
                          );
                      return Badge(
                        isLabelVisible: unread > 0,
                        label: Text(unread > 99 ? '99+' : unread.toString()),
                        child: const Icon(Icons.forum_outlined),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: _BottomBarItem(
                  label: L10n.of(context).bottomTabContacts,
                  selected: currentIndex == 1,
                  onTap: () => context.go('/contacts'),
                  icon: StreamBuilder(
                    stream: client.onSync.stream,
                    builder: (context, _) {
                      final pending = FriendsService(
                        client,
                      ).load().pendingCount;
                      return Badge(
                        isLabelVisible: pending > 0,
                        label: Text(pending > 99 ? '99+' : pending.toString()),
                        child: const Icon(Icons.contacts_outlined),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: _BottomBarItem(
                  label: L10n.of(context).bottomTabDiscover,
                  selected: currentIndex == 2,
                  onTap: () => context.go('/discover'),
                  icon: const Icon(Icons.explore_outlined),
                ),
              ),
              Expanded(
                child: _BottomBarItem(
                  label: L10n.of(context).bottomTabMe,
                  selected: currentIndex == 3,
                  onTap: () => context.go('/me'),
                  icon: _MeAvatar(client: client),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeAvatar extends StatelessWidget {
  final Client client;

  const _MeAvatar({required this.client});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile>(
      future: client.isLogged() ? client.fetchOwnProfile() : null,
      builder: (context, snapshot) => Avatar(
        mxContent: snapshot.data?.avatarUrl,
        name: snapshot.data?.displayName ?? client.userID?.localpart,
        size: 24,
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool selected;
  final void Function() onTap;

  const _BottomBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconTheme.merge(
            data: IconThemeData(
              size: 24,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            child: icon,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
