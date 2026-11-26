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

  /// 封面是**普通消息事件**（不是状态事件）。
  ///
  /// 状态事件的 state_key 可以伪造——只要权限放开，谁都能写 `state_key = 别人`
  /// 改别人的封面。普通事件的 sender 由服务器签名，无法伪造，天然「只能改自己的」。
  /// 取某个人最新的一条封面事件。
  Future<Uri?> coverForAsync(String userId) async {
    final latest = await _latestCoverEvent(userId);
    if (latest != null) return latest;
    // 兼容旧版：早先封面存在状态事件里，读到就先用着。
    return _legacyStateCover(userId);
  }

  Future<Uri?> _latestCoverEvent(String userId) async {
    final momentsRoom = room;
    if (momentsRoom == null) return null;
    try {
      final tl = await momentsRoom.getTimeline(limit: 30);
      for (var page = 0; page < 3; page++) {
        final hits = tl.events
            .where(
              (e) =>
                  e.type == coverEventType &&
                  e.senderId == userId &&
                  !e.redacted,
            )
            .toList();
        if (hits.isNotEmpty) {
          hits.sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
          final image = hits.first.content['image'];
          if (image is String && image.isNotEmpty) return Uri.tryParse(image);
        }
        if (!tl.canRequestHistory) break;
        await tl.requestHistory(historyCount: 50);
      }
    } catch (e) {
      debugPrint('[moments] read cover failed: $e');
    }
    return null;
  }

  Uri? _legacyStateCover(String userId) {
    final event = room?.states[coverEventType]?[userId];
    final image = event?.content['image'];
    if (image is! String || image.isEmpty) return null;
    return Uri.tryParse(image);
  }

  Future<void> setCover(Uint8List bytes) async {
    final momentsRoom = await ensureRoom();
    final mxc = await client.uploadContent(
      bytes,
      filename: 'cover.jpg',
      contentType: 'image/jpeg',
    );
    // 用普通消息事件：sender 由服务器鉴权，别人改不了我的，我也改不了别人的。
    await momentsRoom.sendEvent({
      'image': mxc.toString(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, type: coverEventType);
  }

  /// 把旧封面（账号数据里的 / 房间状态事件里的）迁成自己的普通消息事件。
  Future<void> migrateLegacyCover() async {
    final userId = client.userID;
    if (userId == null) return;
    if (await _latestCoverEvent(userId) != null) return;

    final fromState = _legacyStateCover(userId)?.toString();
    final fromAccountData =
        client.accountData[coverEventType]?.content['image'];
    final image =
        fromState ??
        (fromAccountData is String && fromAccountData.isNotEmpty
            ? fromAccountData
            : null);
    if (image == null) return;

    try {
      final momentsRoom = await ensureRoom();
      await momentsRoom.sendEvent({
        'image': image,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, type: coverEventType);
      debugPrint('[moments] migrated legacy cover to timeline event');
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
    List<Event> mine() =>
        momentEvents(tl.events).where((e) => e.senderId == userId).toList();

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
    final id = canonicalRoomId;
    return id == null ? null : client.getRoomById(id);
  }

  /// 朋友圈用的是固定别名的公开房间，任何账号都能自己 join，
  /// 不需要谁去「邀请」，用户也感知不到房间的存在。
  String? get alias {
    final host = client.homeserver?.host;
    if (host == null || host.isEmpty) return null;
    return '$canonicalAliasLocalPart:$host';
  }

  static const canonicalAliasLocalPart = '#moments';

  /// 按账号缓存别名解析结果（多账号登录时不能互相串）。
  static final Map<String, String> _resolved = {};

  String get _cacheKey => client.userID ?? '';

  /// 解析别名的结果（缓存），没有就回落账号数据里记的 room_id。
  String? get canonicalRoomId => _resolved[_cacheKey] ?? roomId;

  Future<String?> resolveRoomId() async {
    final cached = _resolved[_cacheKey];
    if (cached != null) return cached;
    final alias = this.alias;
    if (alias != null) {
      try {
        final resolved = await client.getRoomIdByAlias(alias);
        final id = resolved.roomId;
        if (id != null && id.isNotEmpty) {
          _resolved[_cacheKey] = id;
          return id;
        }
      } catch (e) {
        debugPrint('[moments] alias $alias not resolved: $e');
      }
    }
    final fallback = roomId;
    if (fallback != null) _resolved[_cacheKey] = fallback;
    return fallback;
  }

  /// 启动时静默加入：失败不提示，只记日志。
  Future<void> ensureJoined() async {
    if (!client.isLogged()) return;
    final id = await resolveRoomId();
    if (id == null) return;
    final existing = client.getRoomById(id);
    if (existing != null && existing.membership == Membership.join) return;
    try {
      await client.joinRoomById(id);
      debugPrint('[moments] silently joined $id');
    } catch (e) {
      debugPrint('[moments] silent join failed: $e');
    }
  }

  /// 这个房间该不该从会话列表里藏掉。
  ///
  /// 别名解析到的房间、账号数据里记的房间，以及**所有叫「朋友圈」的历史重复房间**
  /// 都藏起来（老版本每个账号各建了一个，之前会显示成一堆群）。
  bool hidesRoom(Room room) {
    if (room.id == canonicalRoomId) return true;
    final name = room.name.trim();
    if (name == roomName) return true;
    // 老版本/测试留下的「朋友圈 · xxx」这类变体也一起藏掉
    if (name.startsWith('$roomName · ') || name.startsWith('$roomName·')) {
      return true;
    }
    return false;
  }

  /// 找到或创建朋友圈房间（公开 + 固定别名，不加密）。
  Future<Room> ensureRoom() async {
    // 1) 别名能解析到 → 直接 join（已经在房间里就什么都不做）
    final resolvedId = await resolveRoomId();
    if (resolvedId != null) {
      final joined = client.getRoomById(resolvedId);
      if (joined != null && joined.membership == Membership.join) return joined;
      try {
        await client.joinRoomById(resolvedId);
      } catch (e) {
        debugPrint('[moments] join $resolvedId failed: $e');
      }
      final afterJoin = client.getRoomById(resolvedId);
      if (afterJoin != null) return afterJoin;
    }

    // 2) 没有这个房间 → 建一个公开房间并占住别名
    final String id;
    try {
      id = await client.createRoom(
        name: roomName,
        topic: 'FluffyChatX 朋友圈',
        preset: CreateRoomPreset.publicChat,
        roomAliasName: 'moments',
        // 绝对不能加密：机器人和其他客户端要读得到。
      );
    } catch (e) {
      // 别名可能刚被别人抢建，再解析一次
      debugPrint('[moments] create room failed, retry alias: $e');
      final retryId = await resolveRoomId();
      if (retryId == null) rethrow;
      await client.joinRoomById(retryId);
      final retried = client.getRoomById(retryId);
      if (retried == null) rethrow;
      return retried;
    }

    _resolved[_cacheKey] = id;
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
    final joined = room.getParticipants().map((p) => p.id).toSet();
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

  Future<void> unLike(
    Event moment,
    List<Event> events, {
    String key = '👍',
  }) async {
    for (final reaction in _reactions(events, moment)) {
      if (reaction.senderId == client.userID && reaction.key == key) {
        await reaction.event.redactEvent();
        return;
      }
    }
  }

  Future<void> comment(Event moment, String text) async {
    final room = await ensureRoom();
    // 用普通回复（m.in_reply_to）而不是 thread：
    // thread 回复不会出现在主线时间线里，朋友圈也读不回来。
    await room.sendEvent({
      'msgtype': 'm.text',
      'body': text,
      'm.relates_to': {
        'm.in_reply_to': {'event_id': moment.eventId},
      },
    }, type: 'm.room.message');
  }

  // ------------------------------------------------------------ 事件聚合

  static List<Event> momentEvents(List<Event> events) =>
      events.where((e) => e.type == momentEventType && !e.redacted).toList()
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

  static List<String> reactions(List<Event> events, Event moment) =>
      _reactions(events, moment).map((r) => r.senderId).toSet().toList();

  static bool hasLiked(List<Event> events, Event moment, String? userId) =>
      _reactions(events, moment).any((r) => r.senderId == userId);

  static List<MomentComment> comments(List<Event> events, Event moment) =>
      events
          .where((e) {
            if (e.redacted) return false;
            if (e.type != 'm.room.message') return false;
            final relates = e.content['m.relates_to'];
            if (relates is! Map) return false;
            // 兼容两种写法：新代码用 m.in_reply_to，老数据可能是 rel_type=m.thread
            final inReplyTo = relates['m.in_reply_to'];
            final target =
                relates['event_id'] ??
                (inReplyTo is Map ? inReplyTo['event_id'] : null);
            return target == moment.eventId;
          })
          .map((e) {
            return MomentComment(
              senderId: e.senderId,
              body: e.body,
              ts: e.originServerTs.millisecondsSinceEpoch,
            );
          })
          .toList()
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
