// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_bottom_bar.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/utils/wechat/friend_tags_service.dart';
import 'package:fluffychat/utils/wechat/remark_service.dart';
import 'package:fluffychat/utils/wechat/room_kind.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 通讯录：新的朋友 / 群聊 / 标签 + 按拼音首字母分组的好友名单。
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  bool _syncStarted = false;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _draggingIndex = false;

  static const List<String> _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_syncStarted) return;
    _syncStarted = true;
    final client = Matrix.of(context).client;
    FriendsSync.start(client);
    // 进页面就重扫一次：对方刚同意、或者换设备登录时，名单要能立刻出来。
    unawaited(FriendsSync.scanNow(client));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openChat(String userId) async {
    final service = FriendsService(Matrix.of(context).client);
    try {
      final roomId = await service.openDirectChat(userId);
      if (!mounted) return;
      context.go('/rooms/$roomId');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(L10n.of(context).openChatFailed(e.toString()));
    }
  }

  /// 长按好友：发消息 / 设置备注（微信长按好友的交互）。
  Future<void> _showFriendActions(FriendEntry friend) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final remark = RemarkService(client).remarkOf(friend.userId);
    final action = await showModalBottomSheet<_FriendAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                remark ?? friend.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              subtitle: Text(friend.userId),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(l10n.sendMessage),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_FriendAction.message),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.setRemark),
              onTap: () => Navigator.of(sheetContext).pop(_FriendAction.remark),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _FriendAction.message:
        await _openChat(friend.userId);
      case _FriendAction.remark:
        await showRemarkDialog(
          context,
          friend.userId,
          originalName: friend.displayName,
        );
        if (mounted) setState(() {});
    }
  }

  /// 下拉刷新：无视节流立刻扫一次房间，把对方「已接受」的申请捞回来。
  Future<void> _refresh() async {
    final client = Matrix.of(context).client;
    await FriendsSync.scanNow(client);
    if (mounted) setState(() {});
  }

  GlobalKey _keyFor(String letter) =>
      _sectionKeys.putIfAbsent(letter, GlobalKey.new);

  Future<void> _scrollToLetter(String letter) async {
    final context = _sectionKeys[letter]?.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0,
    );
  }

  void _onIndexDrag(Offset localPosition, double height) {
    if (height <= 0) return;
    final index = (localPosition.dy / height * _letters.length).floor().clamp(
      0,
      _letters.length - 1,
    );
    final letter = _letters[index];
    // 只滚到真的有人存在的分组，避免拖过 # 之后一片空白。
    if (_sectionKeys[letter]?.currentContext == null) return;
    _scrollToLetter(letter);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final service = FriendsService(client);
    final tags = FriendTagsService(client).load();
    final groupCount = client.rooms.where(_isGroupRoom).length;

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
          final friends =
              data.friends
                  .where((friend) => friend.userId != client.userID)
                  .toList()
                ..sort(
                  (a, b) => _sortKey(a.title).compareTo(_sortKey(b.title)),
                );

          final grouped = <String, List<FriendEntry>>{};
          for (final friend in friends) {
            grouped.putIfAbsent(_initial(friend.title), () => []).add(friend);
          }
          final existingLetters = [
            for (final letter in _letters)
              if (grouped[letter] != null) letter,
          ];

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _entryTile(
                        icon: Icons.person_add_alt_1_outlined,
                        title: l10n.newFriends,
                        badge: data.pendingCount > 0
                            ? Badge(label: Text(data.pendingCount.toString()))
                            : null,
                        onTap: () => context.push('/contacts/new'),
                      ),
                      _entryTile(
                        icon: Icons.groups_outlined,
                        title: l10n.groupsEntry,
                        trailingText: groupCount > 0 ? '$groupCount' : null,
                        onTap: () => context.push('/contacts/groups'),
                      ),
                      _entryTile(
                        icon: Icons.sell_outlined,
                        title: l10n.tagsEntry,
                        trailingText: tags.order.isEmpty
                            ? null
                            : '${tags.order.length}',
                        onTap: () => context.push('/contacts/tags'),
                      ),
                      const Divider(height: 1),
                      if (friends.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l10n.noFriendsYet,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      for (final letter in existingLetters) ...[
                        Container(
                          key: _keyFor(letter),
                          color: theme.colorScheme.surfaceContainerHigh,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: Text(
                            letter,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final friend in grouped[letter]!)
                          ListTile(
                            key: ValueKey(friend.userId),
                            leading: Avatar(
                              mxContent: _parseUri(friend.avatarUrl),
                              name:
                                  RemarkService(
                                    client,
                                  ).remarkOf(friend.userId) ??
                                  friend.title,
                              size: Avatar.defaultSize * 0.9,
                            ),
                            title: Text(
                              RemarkService(client).remarkOf(friend.userId) ??
                                  friend.title,
                              maxLines: 1,
                            ),
                            // 好友行只显示名字，不显示 Matrix ID（ID 在资料页里看）
                            trailing: const Icon(Icons.chat_bubble_outline),
                            onTap: () => context.push(
                              '/contacts/friend?userId=${Uri.encodeComponent(friend.userId)}',
                            ),
                            // 长按弹菜单：发消息 / 设置备注（微信长按好友的交互）。
                            onLongPress: () => _showFriendActions(friend),
                          ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              if (existingLetters.isNotEmpty)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: _IndexBar(
                    letters: existingLetters,
                    active: _draggingIndex,
                    onChanged: _onIndexDrag,
                    onDragState: (dragging) =>
                        setState(() => _draggingIndex = dragging),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget? _trailingText(BuildContext context, String? text) {
    if (text == null) return null;
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  bool _isGroupRoom(Room room) =>
      room.membership == Membership.join && isGroupChat(room);

  Widget _entryTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? badge,
    String? trailingText,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.primary),
      ),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ?badge,
          ?_trailingText(context, trailingText),
          const Icon(Icons.chevron_right_outlined),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 右侧竖排 A-Z 索引条：点或滑都能跳转。
class _IndexBar extends StatelessWidget {
  final List<String> letters;
  final bool active;
  final void Function(Offset localPosition, double height) onChanged;
  final void Function(bool dragging) onDragState;

  const _IndexBar({
    required this.letters,
    required this.active,
    required this.onChanged,
    required this.onDragState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        void handle(Offset position) => onChanged(position, height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) {
            onDragState(true);
            handle(details.localPosition);
          },
          onVerticalDragUpdate: (details) => handle(details.localPosition),
          onVerticalDragEnd: (_) => onDragState(false),
          onVerticalDragCancel: () => onDragState(false),
          onTapDown: (details) => handle(details.localPosition),
          child: Container(
            width: 24,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final letter in letters)
                  SizedBox(
                    height: 18,
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active ? FontWeight.bold : null,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 拼音排序键：中文按拼音、英文按字母，数字和符号排最后。
String _sortKey(String name) {
  try {
    return PinyinHelper.getPinyinE(
      name,
      separator: '',
      defPinyin: '~',
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase();
  } catch (_) {
    return name.toLowerCase();
  }
}

/// 分组首字母：A-Z，其它都进 #。
String _initial(String name) {
  final key = _sortKey(name);
  if (key.isEmpty) return '#';
  final first = key[0].toUpperCase();
  if (first.codeUnitAt(0) >= 65 && first.codeUnitAt(0) <= 90) return first;
  return '#';
}

Uri? _parseUri(String? value) =>
    value == null || value.isEmpty ? null : Uri.tryParse(value);

/// 长按好友时弹出的菜单项。
enum _FriendAction { message, remark }
