// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// 长按语音「收藏」用的本地收藏夹。
///
/// 存在账号数据里（跟设备无关，换手机也还在），不碰服务器配置。
class FavoritesService {
  static const eventType = 'com.dafeiyu.favorites';
  static const maxEntries = 200;

  final Client client;

  const FavoritesService(this.client);

  List<Map<String, Object?>> load() {
    final raw = client.accountData[eventType]?.content['items'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map(Map<String, Object?>.from).toList();
  }

  bool contains(String eventId) => load().any((e) => e['event_id'] == eventId);

  /// 收藏 / 取消收藏，返回操作后是否在收藏夹里。
  Future<bool> toggle(Event event) async {
    final userId = client.userID;
    if (userId == null) return false;
    final items = load();
    final exists = items.any((e) => e['event_id'] == event.eventId);
    if (exists) {
      items.removeWhere((e) => e['event_id'] == event.eventId);
    } else {
      items.insert(0, {
        'event_id': event.eventId,
        'room_id': event.room.id,
        'sender': event.senderId,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'body': event.body,
        'msgtype': event.messageType,
        'event_type': event.type,
      });
      if (items.length > maxEntries) {
        items.removeRange(maxEntries, items.length);
      }
    }
    await client.setAccountData(userId, eventType, {'items': items});
    return !exists;
  }
}
