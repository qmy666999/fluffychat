// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 新的朋友：收到的申请（接受/拒绝）+ 已发送的申请。
class NewFriendsPage extends StatefulWidget {
  const NewFriendsPage({super.key});

  @override
  State<NewFriendsPage> createState() => _NewFriendsPageState();
}

class _NewFriendsPageState extends State<NewFriendsPage> {
  Future<void> _accept(FriendRequestEntry request) async {
    final service = FriendsService(Matrix.of(context).client);
    try {
      await service.acceptRequest(request);
      if (!mounted) return;
      final roomId =
          request.roomId ?? await service.openDirectChat(request.peer);
      if (!mounted) return;
      context.go('/rooms/$roomId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).openChatFailed(e.toString()))),
      );
    }
  }

  Future<void> _reject(FriendRequestEntry request) async {
    await FriendsService(Matrix.of(context).client).rejectRequest(request);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final service = FriendsService(client);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.newFriends)),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) {
          final data = service.load();
          final incoming = data.incoming;
          final outgoing = data.outgoing;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.incomingRequests,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (incoming.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.noRequests,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final request in incoming)
                ListTile(
                  leading: Avatar(
                    mxContent: _uri(request.avatarUrl),
                    name: request.title,
                    size: Avatar.defaultSize * 0.9,
                  ),
                  title: Text(request.title, maxLines: 1),
                  subtitle: Text(
                    request.message.isEmpty
                        ? request.peer
                        : '${request.message}\n${request.peer}',
                    maxLines: 2,
                  ),
                  trailing: request.status == FriendRequestStatus.pending
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _accept(request),
                              child: Text(l10n.accept),
                            ),
                            TextButton(
                              onPressed: () => _reject(request),
                              child: Text(l10n.reject),
                            ),
                          ],
                        )
                      : Text(
                          request.status == FriendRequestStatus.accepted
                              ? l10n.statusAccepted
                              : l10n.statusRejected,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.outgoingRequests,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (outgoing.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.noRequests,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final request in outgoing)
                ListTile(
                  leading: Avatar(
                    mxContent: _uri(request.avatarUrl),
                    name: request.title,
                    size: Avatar.defaultSize * 0.9,
                  ),
                  title: Text(request.peer, maxLines: 1),
                  subtitle: Text(request.message, maxLines: 1),
                  trailing: Text(
                    switch (request.status) {
                      FriendRequestStatus.pending => l10n.waitingVerification,
                      FriendRequestStatus.accepted => l10n.statusAccepted,
                      FriendRequestStatus.rejected => l10n.statusRejected,
                    },
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Uri? _uri(String? value) =>
    value == null || value.isEmpty ? null : Uri.tryParse(value);
