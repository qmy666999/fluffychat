// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 底部四项导航：聊天 / 通讯录 / 发现 / 我。
///
/// 只做入口和布局：颜色全部取自当前主题（surfaceContainer / primary / error），
/// 没有引入任何自定义色值；「我」就是原来顶栏那个头像，点击仍然弹出同一套
/// 账号与设置菜单，所以功能一个都没丢。
class ChatListBottomBar extends StatelessWidget {
  final ChatListController controller;

  const ChatListBottomBar(this.controller, {super.key});

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
                  selected: true,
                  onTap: controller.clearActiveSpace,
                  icon: StreamBuilder(
                    stream: client.onSync.stream,
                    builder: (context, _) {
                      final unread = client.rooms.fold<int>(
                        0,
                        (sum, room) => sum +
                            (room.membership == Membership.join
                                ? room.notificationCount
                                : 0),
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
                  selected: false,
                  onTap: () => context.push('/contacts'),
                  icon: const Icon(Icons.contacts_outlined),
                ),
              ),
              Expanded(
                child: _BottomBarItem(
                  label: L10n.of(context).bottomTabDiscover,
                  selected: false,
                  onTap: () => context.push('/discover'),
                  icon: const Icon(Icons.explore_outlined),
                ),
              ),
              Expanded(
                child: _MeBottomBarItem(controller: controller),
              ),
            ],
          ),
        ),
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

/// 「我」= 原来顶栏右上角的头像。点击复用 ClientChooserButton 那套菜单，
/// 账号切换 / 新建群组 / 归档 / 设置等入口都还在。
class _MeBottomBarItem extends StatelessWidget {
  final ChatListController controller;

  const _MeBottomBarItem({required this.controller});

  Future<void> _showAccountMenu(BuildContext context) async {
    final button = ClientChooserButton(controller);
    final items = button.bundleMenuItems(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final result = await showMenu<Object>(
      context: context,
      position: position,
      items: items,
    );
    if (result == null) return;
    if (!context.mounted) return;
    await button.clientSelected(result, context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    return InkWell(
      onTap: () => _showAccountMenu(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FutureBuilder<Profile>(
            future: client.isLogged() ? client.fetchOwnProfile() : null,
            builder: (context, snapshot) => Avatar(
              mxContent: snapshot.data?.avatarUrl,
              name: snapshot.data?.displayName ?? client.userID?.localpart,
              size: 24,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            L10n.of(context).bottomTabMe,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
