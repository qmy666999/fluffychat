// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../friends/friends_service.dart';

/// 朋友圈：所有动态都放在一个共用房间里，一条动态 = 一条
/// `com.dafeiyu.moment` 自定义事件（明文，机器人和其他客户端都能读）。
///
/// - 点赞：标准 `m.reaction`（rel_type m.annotation）
/// - 评论：`m.room.message` + relates_to m.thread 指向动态
/// - 房间 ID 存账号数据 `com.dafeiyu.moments_config`（多设备同步）
class MomentsService {
  static const momentEventType = 'com.dafeiyu.moment';
  static const configEventType = 'com.dafeiyu.moments_config';
  static const coverEventType = 'com.dafeiyu.moments_cover';
  static const roomName = '朋友圈';

  final Client client;

  const MomentsService(this.client);

  Map<String, Object?> get _config =>
      client.accountData[configEventType]?.content ?? const {};

  String? get roomId => _config['room_id'] as String?;

  int get lastSeenTs => (_config['last_seen_ts'] as num?)?.toInt() ?? 0;

  /// 封面存在房间状态事件里（state_key = 用户 id），这样别人也读得到。
  Uri? coverFor(String userId) {
    final event = room?.states[coverEventType]?[userId];
    final image = event?.content['image'];
    if (image is! String || image.isEmpty) return null;
    return Uri.tryParse(image);
  }

  /// 自己的封面。
  Uri? get coverImage {
    final userId = client.userID;
    return userId == null ? null : coverFor(userId);
  }

  Future<void> setCover(Uint8List bytes) async {
    final userId = client.userID;
    if (userId == null) return;
    final momentsRoom = await ensureRoom();
    final mxc = await client.uploadContent(
      bytes,
      filename: 'cover.jpg',
      contentType: 'image/jpeg',
    );
    // 写房间状态事件：账号数据是私有的，别人读不到。
    await client.setRoomStateWithKey(momentsRoom.id, coverEventType, userId, {
      'image': mxc.toString(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 旧版封面存在私有账号数据里，首次进朋友圈时迁到房间状态事件。
  Future<void> migrateLegacyCover() async {
    final userId = client.userID;
    if (userId == null) return;
    final legacy = client.accountData[coverEventType]?.content['image'];
    if (legacy is! String || legacy.isEmpty) return;
    if (coverFor(userId) != null) return;
    try {
      final momentsRoom = await ensureRoom();
      await client.setRoomStateWithKey(momentsRoom.id, coverEventType, userId, {
        'image': legacy,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      debugPrint('[moments] migrated legacy cover to room state');
    } catch (e) {
      debugPrint('[moments] migrate cover failed: $e');
    }
  }

  /// 某个人的动态（共用房间里按 sender 过滤），必要时多翻几页历史。
  Future<List<Event>> momentsBySender(
    String userId, {
    int minCount = 10,
    int maxPages = 3,
  }) async {
    final momentsRoom = room;
    if (momentsRoom == null) return const [];
    final tl = await momentsRoom.getTimeline(limit: 40);
    List<Event> mine() => momentEvents(
      tl.events,
    ).where((e) => e.senderId == userId).toList();

    var result = mine();
    var pages = 0;
    while (result.length < minCount && pages < maxPages) {
      if (!tl.canRequestHistory) break;
      try {
        await tl.requestHistory(historyCount: 40);
      } catch (e) {
        debugPrint('[moments] history failed: $e');
        break;
      }
      pages++;
      result = mine();
    }
    return result;
  }

  Room? get room {
    final id = roomId;
    return id == null ? null : client.getRoomById(id);
  }

  /// 找到或创建朋友圈房间（不加密，好友先邀请进来）。
  Future<Room> ensureRoom() async {
    final existing = room;
    if (existing != null && existing.membership == Membership.join) {
      return existing;
    }

    final friends = FriendsService(client).load().friends;
    final id = await client.createRoom(
      name: roomName,
      topic: 'FluffyChatX 朋友圈',
      invite: friends.map((f) => f.userId).toList(),
      preset: CreateRoomPreset.privateChat,
      // 绝对不能加密：机器人和其他客户端要读得到。
    );
    final userId = client.userID!;
    await client.setAccountData(userId, configEventType, {
      ..._config,
      'room_id': id,
    });
    final created = client.getRoomById(id);
    if (created == null) {
      throw Exception('moments room not found in sync yet: $id');
    }
    return created;
  }

  Future<void> markSeen() async {
    final userId = client.userID;
    if (userId == null) return;
    await client.setAccountData(userId, configEventType, {
      ..._config,
      'last_seen_ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 好友名单里还没进房间的人，邀请一遍（只邀请，不强制）。
  Future<int> inviteMissingFriends(Room room) async {
    final friends = FriendsService(client).load().friends;
    final joined = room
        .getParticipants()
        .map((p) => p.id)
        .toSet();
    final missing = friends
        .map((f) => f.userId)
        .where((id) => !joined.contains(id))
        .where((id) => id != client.userID)
        .toList();
    var invited = 0;
    for (final userId in missing) {
      try {
        await room.invite(userId);
        invited++;
      } catch (e) {
        debugPrint('[moments] invite $userId failed: $e');
      }
    }
    return invited;
  }

  Future<Timeline> timeline({int limit = 20}) async {
    final room = await ensureRoom();
    return room.getTimeline(limit: limit);
  }

  /// 发现页红点：最新一条动态比上次看过的时间新。
  Future<bool> hasNewMoments() async {
    final room = this.room;
    if (room == null) return false;
    try {
      final tl = await room.getTimeline(limit: 10);
      final moments = momentEvents(tl.events);
      if (moments.isEmpty) return false;
      return momentTs(moments.first) > lastSeenTs;
    } catch (e) {
      debugPrint('[moments] red dot check failed: $e');
      return false;
    }
  }

  Future<void> post({
    required String text,
    required List<Uint8List> images,
  }) async {
    final room = await ensureRoom();
    final uploaded = <String>[];
    for (final bytes in images) {
      final mxc = await client.uploadContent(bytes, filename: 'moment.jpg');
      uploaded.add(mxc.toString());
    }
    await room.sendEvent({
      'text': text,
      'images': uploaded,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }, type: momentEventType);
  }

  Future<void> delete(Event moment) => moment.redactEvent();

  Future<void> like(Event moment, {String key = '👍'}) async {
    final room = await ensureRoom();
    await room.sendEvent({
      'm.relates_to': {
        'rel_type': 'm.annotation',
        'event_id': moment.eventId,
        'key': key,
      },
    }, type: 'm.reaction');
  }

  Future<void> unLike(Event moment, List<Event> events, {String key = '👍'}) async {
    for (final reaction in _reactions(events, moment)) {
      if (reaction.senderId == client.userID && reaction.key == key) {
        await reaction.event.redactEvent();
        return;
      }
    }
  }

  Future<void> comment(Event moment, String text) async {
    final room = await ensureRoom();
    await room.sendEvent({
      'msgtype': 'm.text',
      'body': text,
      'm.relates_to': {
        'rel_type': 'm.thread',
        'event_id': moment.eventId,
      },
    }, type: 'm.room.message');
  }

  // ------------------------------------------------------------ 事件聚合

  static List<Event> momentEvents(List<Event> events) => events
      .where((e) => e.type == momentEventType && !e.redacted)
      .toList()
    ..sort((a, b) => _ts(b).compareTo(_ts(a)));

  static int _ts(Event e) =>
      (e.content['ts'] as num?)?.toInt() ??
      e.originServerTs.millisecondsSinceEpoch;

  static int momentTs(Event moment) => _ts(moment);

  static List<String> images(Event moment) =>
      (moment.content['images'] as List?)?.whereType<String>().toList() ??
      const [];

  static List<Event> _reactionEvents(List<Event> events, Event moment) =>
      events.where((e) {
        if (e.type != 'm.reaction' || e.redacted) return false;
        final relates = e.content['m.relates_to'];
        return relates is Map &&
            relates['rel_type'] == 'm.annotation' &&
            relates['event_id'] == moment.eventId;
      }).toList();

  static List<MomentReaction> _reactions(List<Event> events, Event moment) =>
      _reactionEvents(events, moment)
          .map(
            (e) => MomentReaction(
              senderId: e.senderId,
              key: (e.content['m.relates_to'] as Map)['key'] as String? ?? '',
              event: e,
            ),
          )
          .toList();

  static List<String> reactions(List<Event> events, Event moment) => _reactions(
    events,
    moment,
  ).map((r) => r.senderId).toSet().toList();

  static bool hasLiked(
    List<Event> events,
    Event moment,
    String? userId,
  ) => _reactions(events, moment).any((r) => r.senderId == userId);

  static List<MomentComment> comments(List<Event> events, Event moment) =>
      events.where((e) {
        if (e.redacted) return false;
        if (e.type != 'm.room.message') return false;
        final relates = e.content['m.relates_to'];
        return relates is Map &&
            relates['rel_type'] == 'm.thread' &&
            relates['event_id'] == moment.eventId;
      }).map((e) {
        return MomentComment(
          senderId: e.senderId,
          body: e.body,
          ts: e.originServerTs.millisecondsSinceEpoch,
        );
      }).toList()
        ..sort((a, b) => a.ts.compareTo(b.ts));
}

class MomentReaction {
  final String senderId;
  final String key;
  final Event event;

  const MomentReaction({
    required this.senderId,
    required this.key,
    required this.event,
  });
}

class MomentComment {
  final String senderId;
  final String body;
  final int ts;

  const MomentComment({
    required this.senderId,
    required this.body,
    required this.ts,
  });
}
