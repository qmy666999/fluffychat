// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

/// 顶栏：标题居中 + 右上角搜索图标。
///
/// 搜索框本身没有删掉，只是收进了搜索模式：点放大镜才出现输入框，
/// 按返回/关闭再收起。原来的搜索逻辑（controller.startSearch / cancelSearch）不变。
class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return SliverAppBar(
      floating: true,
      toolbarHeight: 64,
      pinned: isColumnMode,
      scrolledUnderElevation: 0,
      centerTitle: true,
      shape: isColumnMode
          ? Border(bottom: BorderSide(color: theme.dividerColor, width: 1))
          : null,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;

          if (!controller.isSearchMode) {
            // 微信式：标题「微信」，有未读时显示「微信(N)」（不含隐藏的朋友圈房间）
            final moments = MomentsService(client);
            final unread = client.rooms
                .where(
                  (room) =>
                      room.membership == Membership.join &&
                      !moments.hidesRoom(room),
                )
                .fold<int>(0, (sum, room) => sum + room.notificationCount);
            final title = unread > 0
                ? '${L10n.of(context).bottomTabChats}($unread)'
                : L10n.of(context).bottomTabChats;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                // 同步状态/断线提示原来在搜索框的 hintText 里，位置挪到标题下面，
                // 不然把输入框收成图标之后这条信息就没地方显示了。
                if (!hide)
                  Text(
                    status.calcLocalizedString(context),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            );
          }

          return TextField(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (text) =>
                controller.onSearchEnter(text, globalSearch: globalSearch),
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.secondaryContainer,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(99),
              ),
              hintText: L10n.of(context).searchChatsRooms,
              hintStyle: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.normal,
              ),
              prefixIcon: Icon(
                Icons.search_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              suffixIcon: globalSearch
                  ? controller.isSearching
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 12,
                            ),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: controller.setServer,
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(99),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              controller.searchServer ??
                                  Matrix.of(context).client.homeserver!.host,
                              maxLines: 2,
                            ),
                          )
                  : null,
            ),
          );
        },
      ),
      actions: [
        if (controller.isSearchMode)
          IconButton(
            tooltip: L10n.of(context).cancel,
            icon: const Icon(Icons.close_outlined),
            onPressed: controller.cancelSearch,
          )
        else ...[
          // 微信右上角「+」：发起群聊 / 添加朋友
          PopupMenuButton<String>(
            tooltip: L10n.of(context).createGroup,
            icon: const Icon(Icons.add),
            onSelected: (value) {
              if (value == 'group') {
                context.go('/rooms/newgroup');
              } else if (value == 'friend') {
                context.push('/contacts/add');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'group',
                child: Text(L10n.of(context).createGroup),
              ),
              PopupMenuItem(
                value: 'friend',
                child: Text(L10n.of(context).addToContacts),
              ),
            ],
          ),
          IconButton(
            tooltip: L10n.of(context).search,
            icon: const Icon(Icons.search_outlined),
            onPressed: controller.startSearch,
          ),
        ],
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
