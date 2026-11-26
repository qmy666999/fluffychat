// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/favorites/favorites_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 微信式「收藏」：长按消息收藏进来的内容。
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesEntry)),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) {
          final items = FavoritesService(client).load();
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.favoritesEmpty, textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, i) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = items[i];
              final roomId = item['room_id']?.toString() ?? '';
              final eventId = item['event_id']?.toString() ?? '';
              final body = item['body']?.toString() ?? '';
              final type = item['msgtype']?.toString();
              final isMedia = type != null && type != 'm.text';
              return ListTile(
                leading: Icon(
                  isMedia ? Icons.image_outlined : Icons.chat_bubble_outline,
                ),
                title: Text(
                  body.isEmpty ? l10n.favoritesEntry : body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item['sender']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  tooltip: l10n.messageFavoriteRemoved,
                  onPressed: () async {
                    final event = await _loadEvent(client, roomId, eventId);
                    if (event == null) return;
                    await FavoritesService(client).toggle(event);
                  },
                ),
                onTap: () {
                  if (roomId.isEmpty) return;
                  context.go('/rooms/$roomId');
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<Event?> _loadEvent(
    Client client,
    String roomId,
    String eventId,
  ) async {
    final room = client.getRoomById(roomId);
    if (room == null) return null;
    return await room.getEventById(eventId);
  }
}
