// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 通讯录 → 群聊：我加入的所有群。
bool _isGroupRoom(Room room) =>
    room.membership == Membership.join && !room.isDirectChat && !room.isSpace;

class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupsEntry), centerTitle: true),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) {
          final rooms = client.rooms.where(_isGroupRoom).toList()
            ..sort(
              (a, b) => b.latestEventReceivedTime.compareTo(
                a.latestEventReceivedTime,
              ),
            );
          if (rooms.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.noGroupsYet,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final count = room.summary.mJoinedMemberCount ?? 0;
              return ListTile(
                leading: Avatar(
                  mxContent: room.avatar,
                  name: room.getLocalizedDisplayname(),
                  size: Avatar.defaultSize * 0.9,
                ),
                title: Text(room.getLocalizedDisplayname(), maxLines: 1),
                subtitle: count > 0
                    ? Text(
                        '$count',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => context.push('/rooms/${room.id}'),
                onLongPress: () => context.push(
                  '/rooms/info?roomId=${Uri.encodeComponent(room.id)}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
