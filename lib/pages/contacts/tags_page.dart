// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/utils/wechat/friend_tags_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// 通讯录 → 标签：给好友分组，方便按标签找人。
class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  FriendTagsService get _service =>
      FriendTagsService(Matrix.of(context).client);

  Future<void> _create() async {
    final l10n = L10n.of(context);
    final name = await showTextInputDialog(
      context: context,
      title: l10n.newTag,
      hintText: l10n.tagNameHint,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _service.create(trimmed);
    if (mounted) setState(() {});
  }

  Future<void> _delete(String tag) async {
    final l10n = L10n.of(context);
    final ok = await showOkCancelAlertDialog(
      context: context,
      title: l10n.tagDelete,
      message: tag,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (ok != OkCancelResult.ok) return;
    await _service.delete(tag);
    if (mounted) setState(() {});
  }

  Future<void> _editMembers(String tag) async {
    final client = Matrix.of(context).client;
    final friends = FriendsService(
      client,
    ).load().friends.where((friend) => friend.userId != client.userID).toList();
    final selected = (_service.load().tags[tag] ?? const <String>[]).toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _TagMembersSheet(title: tag, friends: friends, selected: selected),
    );
    if (result == null) return;
    await _service.setFriends(tag, result.toList());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tagsEntry),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.newTag),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) {
          final data = _service.load();
          if (data.order.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Icon(
                      Icons.sell_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Text(
                      l10n.noTagsYet,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      l10n.wechatGroupTagHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: data.order.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final tag = data.order[index];
              final count = data.countOf(tag);
              return ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text(tag),
                subtitle: Text(
                  '$count',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                trailing: IconButton(
                  tooltip: l10n.tagDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(tag),
                ),
                onTap: () => _editMembers(tag),
              );
            },
          );
        },
      ),
    );
  }
}

/// 标签成员勾选面板。
class _TagMembersSheet extends StatefulWidget {
  final String title;
  final List<FriendEntry> friends;
  final Set<String> selected;

  const _TagMembersSheet({
    required this.title,
    required this.friends,
    required this.selected,
  });

  @override
  State<_TagMembersSheet> createState() => _TagMembersSheetState();
}

class _TagMembersSheetState extends State<_TagMembersSheet> {
  late final Set<String> _selected = Set<String>.from(widget.selected);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(l10n.ok),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.friends.isEmpty
                  ? Center(child: Text(l10n.noFriendsYet))
                  : ListView.builder(
                      itemCount: widget.friends.length,
                      itemBuilder: (context, index) {
                        final friend = widget.friends[index];
                        final checked = _selected.contains(friend.userId);
                        return CheckboxListTile.adaptive(
                          value: checked,
                          secondary: Avatar(
                            mxContent: friend.avatarUrl == null
                                ? null
                                : Uri.tryParse(friend.avatarUrl!),
                            name: friend.title,
                            size: Avatar.defaultSize * 0.8,
                          ),
                          title: Text(friend.title),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected.add(friend.userId);
                            } else {
                              _selected.remove(friend.userId);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
