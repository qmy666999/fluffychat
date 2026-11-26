// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// 一条「提醒我」记录：把某条消息在指定时间重新提醒一次。
class ReminderEntry {
  final String id;
  final String roomId;
  final String eventId;
  final String text;
  final int dueAt;

  ReminderEntry({
    required this.id,
    required this.roomId,
    required this.eventId,
    required this.text,
    required this.dueAt,
  });

  DateTime get due => DateTime.fromMillisecondsSinceEpoch(dueAt);

  Map<String, Object?> toJson() => {
    'id': id,
    'room_id': roomId,
    'event_id': eventId,
    'text': text,
    'due_at': dueAt,
  };

  factory ReminderEntry.fromJson(Map<String, Object?> json) => ReminderEntry(
    id: (json['id'] ?? '').toString(),
    roomId: (json['room_id'] ?? '').toString(),
    eventId: (json['event_id'] ?? '').toString(),
    text: (json['text'] ?? '').toString(),
    dueAt: (json['due_at'] as num?)?.toInt() ?? 0,
  );
}

/// 消息提醒：存在账号数据里，App 在前台时由 MatrixState 每分钟检查一次。
///
/// 说明：这一版没有后台调度（不引额外的通知插件），所以提醒只在 App
/// 运行/切回前台时触发；App 完全退出时不会响。做得到这一层已经够用，
/// 真需要后台提醒再接本地通知插件。
class ReminderService {
  static const String eventType = 'com.dafeiyu.reminders';
  static const int maxEntries = 200;

  final Client client;

  const ReminderService(this.client);

  List<ReminderEntry> load() {
    final items = client.accountData[eventType]?.content['items'];
    if (items is! List) return <ReminderEntry>[];
    return [
      for (final item in items)
        if (item is Map)
          ReminderEntry.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Future<void> add(Event event, DateTime due) async {
    final userId = client.userID;
    if (userId == null) return;
    final items = load();
    items.removeWhere((e) => e.eventId == event.eventId);
    items.insert(
      0,
      ReminderEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        roomId: event.room.id,
        eventId: event.eventId,
        text: event.body,
        dueAt: due.millisecondsSinceEpoch,
      ),
    );
    if (items.length > maxEntries) items.removeRange(maxEntries, items.length);
    await client.setAccountData(userId, eventType, {
      'items': [for (final item in items) item.toJson()],
    });
  }

  Future<void> remove(String id) async {
    final userId = client.userID;
    if (userId == null) return;
    final items = load()..removeWhere((e) => e.id == id);
    await client.setAccountData(userId, eventType, {
      'items': [for (final item in items) item.toJson()],
    });
  }

  Future<void> clear() async {
    final userId = client.userID;
    if (userId == null) return;
    await client.setAccountData(userId, eventType, {'items': <Object?>[]});
  }

  /// 取出一条已经到时间的提醒并从列表里删掉；没有到时间的返回 null。
  static Future<ReminderEntry?> popDue(Client client) async {
    final service = ReminderService(client);
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = service.load().where((e) => e.dueAt <= now).toList();
    if (due.isEmpty) return null;
    final first = due.first;
    await service.remove(first.id);
    return first;
  }
}
