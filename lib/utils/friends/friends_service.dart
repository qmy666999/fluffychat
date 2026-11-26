// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

// Matrix 没有原生好友关系。这里用 account data + 房间状态事件模拟一套：
//
// - `com.dafeiyu.friends`         好友名单（备注名/昵称/头像缓存）
// - `com.dafeiyu.friend_requests` 收/发的申请
// - `m.direct`                    标准私聊映射，判断私聊只认它
// - 房间里 `com.dafeiyu.friend_request` / `friend_accept` / `friend_removed`
//   状态事件负责把「申请/接受/删除」送达对方

class FriendEntry {
  final String userId;
  String remark;
  String displayName;
  String? avatarUrl;
  int addedAt;

  FriendEntry({
    required this.userId,
    this.remark = '',
    this.displayName = '',
    this.avatarUrl,
    int? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 显示名：备注优先，其次昵称，最后 mxid 的 localpart。
  String get title {
    final r = remark.trim();
    if (r.isNotEmpty) return r;
    if (displayName.trim().isNotEmpty) return displayName.trim();
    return userId.localpart ?? userId;
  }

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'remark': remark,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'added_at': addedAt,
  };

  factory FriendEntry.fromJson(Map<String, Object?> json) => FriendEntry(
    userId: (json['user_id'] ?? '') as String,
    remark: (json['remark'] ?? '') as String? ?? '',
    displayName: (json['display_name'] ?? '') as String? ?? '',
    avatarUrl: json['avatar_url'] as String?,
    addedAt: (json['added_at'] as num?)?.toInt(),
  );

  /// 用来从搜索结果/资料更新缓存。
  void updateFromProfile(Profile profile) {
    displayName = profile.displayName ?? displayName;
    avatarUrl = profile.avatarUrl?.toString() ?? avatarUrl;
  }
}

enum FriendRequestStatus { pending, accepted, rejected }

class FriendRequestEntry {
  final String peer;
  final String message;
  final String? peerName;
  final String? avatarUrl;
  final int ts;
  final String? roomId;
  FriendRequestStatus status;

  FriendRequestEntry({
    required this.peer,
    this.message = '',
    this.peerName,
    this.avatarUrl,
    required this.ts,
    this.roomId,
    this.status = FriendRequestStatus.pending,
  });

  String get title {
    final n = peerName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return peer.localpart ?? peer;
  }

  Map<String, Object?> toJson() => {
    'peer': peer,
    'message': message,
    'peer_name': peerName,
    'avatar_url': avatarUrl,
    'ts': ts,
    'room_id': roomId,
    'status': status.name,
  };

  factory FriendRequestEntry.fromJson(
    Map<String, Object?> json, {
    bool incoming = true,
  }) => FriendRequestEntry(
    // 数据格式按提示词：incoming 用 from，outgoing 用 to，这里统一成 peer。
    peer:
        ((incoming ? json['from'] : json['to']) ?? json['peer'] ?? '')
            as String,
    message: (json['message'] ?? '') as String? ?? '',
    peerName:
        ((incoming ? json['from_name'] : json['to_name']) ?? json['peer_name'])
            as String?,
    avatarUrl: json['avatar_url'] as String?,
    ts: (json['ts'] as num?)?.toInt() ?? 0,
    roomId: json['room_id'] as String?,
    status: FriendRequestStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => FriendRequestStatus.pending,
    ),
  );

  Map<String, Object?> toIncomingJson() => {
    'from': peer,
    'from_name': peerName,
    'avatar_url': avatarUrl,
    'message': message,
    'ts': ts,
    'status': status.name,
    'room_id': roomId,
  };

  Map<String, Object?> toOutgoingJson() => {
    'to': peer,
    'message': message,
    'ts': ts,
    'status': status.name,
  };
}

class FriendsData {
  List<FriendEntry> friends;
  List<FriendRequestEntry> incoming;
  List<FriendRequestEntry> outgoing;

  FriendsData({
    List<FriendEntry>? friends,
    List<FriendRequestEntry>? incoming,
    List<FriendRequestEntry>? outgoing,
  }) : friends = friends ?? [],
       incoming = incoming ?? [],
       outgoing = outgoing ?? [];

  int get pendingCount =>
      incoming.where((r) => r.status == FriendRequestStatus.pending).length;

  FriendEntry? friend(String userId) {
    for (final f in friends) {
      if (f.userId == userId) return f;
    }
    return null;
  }

  bool isFriend(String userId) => friend(userId) != null;
}

class FriendsService {
  static const friendsEventType = 'com.dafeiyu.friends';
  static const requestsEventType = 'com.dafeiyu.friend_requests';
  static const requestRoomEventType = 'com.dafeiyu.friend_request';
  static const acceptRoomEventType = 'com.dafeiyu.friend_accept';
  static const rejectRoomEventType = 'com.dafeiyu.friend_reject';
  static const removedRoomEventType = 'com.dafeiyu.friend_removed';

  final Client client;

  const FriendsService(this.client);

  // ---------------------------------------------------------------- 读写留底

  FriendsData load() {
    final data = FriendsData();
    final friendsContent = client.accountData[friendsEventType]?.content;
    final rawFriends = friendsContent?['friends'];
    if (rawFriends is List) {
      for (final item in rawFriends) {
        if (item is Map) {
          data.friends.add(
            FriendEntry.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    final requestsContent = client.accountData[requestsEventType]?.content;
    final rawIncoming = requestsContent?['incoming'];
    if (rawIncoming is List) {
      for (final item in rawIncoming) {
        if (item is Map) {
          data.incoming.add(
            FriendRequestEntry.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    final rawOutgoing = requestsContent?['outgoing'];
    if (rawOutgoing is List) {
      for (final item in rawOutgoing) {
        if (item is Map) {
          data.outgoing.add(
            FriendRequestEntry.fromJson(
              Map<String, Object?>.from(item),
              incoming: false,
            ),
          );
        }
      }
    }
    return data;
  }

  Future<void> _save(FriendsData data) async {
    final userId = client.userID;
    if (userId == null) return;
    await client.setAccountData(userId, friendsEventType, {
      'friends': data.friends.map((f) => f.toJson()).toList(),
    });
    await client.setAccountData(userId, requestsEventType, {
      'incoming': data.incoming.map((r) => r.toIncomingJson()).toList(),
      'outgoing': data.outgoing.map((r) => r.toOutgoingJson()).toList(),
    });
  }

  Future<void> save(FriendsData data) => _save(data);

  // ---------------------------------------------------------------- 好友维护

  Future<void> addFriend(FriendEntry friend) async {
    final data = load();
    final existing = data.friend(friend.userId);
    if (existing != null) {
      existing
        ..displayName = friend.displayName
        ..avatarUrl = friend.avatarUrl;
    } else {
      data.friends.add(friend);
    }
    await _save(data);
  }

  Future<void> removeFriend(String userId) async {
    final data = load();
    data.friends.removeWhere((f) => f.userId == userId);
    await _save(data);
  }

  Future<void> setRemark(String userId, String remark) async {
    final data = load();
    final friend = data.friend(userId);
    if (friend == null) return;
    friend.remark = remark.trim();
    await _save(data);
  }

  // ---------------------------------------------------------------- m.direct

  bool isDirectRoom(String roomId) {
    final direct = client.accountData['m.direct']?.content;
    if (direct == null) return false;
    for (final value in direct.values) {
      if (value is List && value.contains(roomId)) return true;
    }
    return false;
  }

  Future<void> markRoomAsDirect(String userId, String roomId) async {
    final me = client.userID;
    if (me == null) return;
    final direct = Map<String, Object?>.from(
      client.accountData['m.direct']?.content ?? const {},
    );
    final list = List<String>.from((direct[userId] as List?) ?? const []);
    if (list.contains(roomId)) return;
    list.add(roomId);
    direct[userId] = list;
    await client.setAccountData(me, 'm.direct', direct);
  }

  /// 第 1 期：把已有的两人房间补进 m.direct。
  ///
  /// FluffyChat 判断私聊只认 m.direct，历史房间里没写过映射的就会一直显示
  /// 「N 名参与者」。这里补齐，顺手也保证不会把群（>2 人）误标。
  Future<int> ensureDirectRooms() async {
    if (!client.isLogged()) return 0;
    var marked = 0;
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.isSpace) continue;
      if (isDirectRoom(room.id)) continue;
      final count = room.summary.mJoinedMemberCount;
      if (count != 2) continue;
      final peer = room.directChatMatrixID ?? _onlyOtherMember(room);
      if (peer == null) continue;
      await markRoomAsDirect(peer, room.id);
      marked++;
    }
    if (marked > 0) {
      debugPrint('[friends] marked $marked existing rooms as direct');
    }
    return marked;
  }

  String? _onlyOtherMember(Room room) {
    final me = client.userID;
    final others = room
        .getParticipants()
        .map((e) => e.id)
        .where((id) => id != me)
        .toList();
    return others.length == 1 ? others.single : null;
  }

  // ---------------------------------------------------------------- 私聊入口

  /// 找到或新建跟某人的私聊房间，并写进 m.direct。
  Future<String> openDirectChat(String userId) async {
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.directChatMatrixID == userId) return room.id;
    }
    // 这里不带 m.room.encryption 初始状态，所以房间是明文的：
    // 好友会话要让机器人也能读，加密房间换设备还会丢历史。
    final roomId = await client.createRoom(
      invite: [userId],
      isDirect: true,
      preset: CreateRoomPreset.privateChat,
    );
    await markRoomAsDirect(userId, roomId);
    return roomId;
  }

  // ---------------------------------------------------------------- 搜索用户

  Future<List<Profile>> searchUsers(String term) async {
    final res = await client.searchUserDirectory(term.trim(), limit: 20);
    final me = client.userID;
    return res.results.where((p) => p.userId != me).toList();
  }

  // ---------------------------------------------------------------- 发申请

  /// 加好友：建（或复用）两人房间 → 发申请状态事件 → 记 outgoing。
  Future<String> sendFriendRequest(String userId, String message) async {
    final roomId = await openDirectChat(userId);
    final me = client.userID!;
    final profile = await client.fetchOwnProfile();

    await client.setRoomStateWithKey(roomId, requestRoomEventType, me, {
      'from': me,
      'from_name': profile.displayName ?? me.localpart,
      'avatar_url': profile.avatarUrl?.toString(),
      'message': message,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    final data = load();
    data.outgoing.removeWhere((r) => r.peer == userId);
    data.outgoing.add(
      FriendRequestEntry(
        peer: userId,
        message: message,
        peerName: profile.displayName,
        avatarUrl: profile.avatarUrl?.toString(),
        ts: DateTime.now().millisecondsSinceEpoch,
        roomId: roomId,
      ),
    );
    await _save(data);
    return roomId;
  }

  // ---------------------------------------------------------------- 收/处理申请

  /// 接受：自己名单加人 → 标 accepted → 房间标私聊 → 回一条 accept 事件。
  Future<void> acceptRequest(FriendRequestEntry request) async {
    final me = client.userID!;
    final roomId = request.roomId ?? await openDirectChat(request.peer);

    await addFriend(
      FriendEntry(
        userId: request.peer,
        displayName: request.peerName ?? '',
        avatarUrl: request.avatarUrl,
      ),
    );

    final data = load();
    for (final r in data.incoming) {
      if (r.peer == request.peer) {
        r.status = FriendRequestStatus.accepted;
      }
    }
    for (final r in data.outgoing) {
      if (r.peer == request.peer) {
        r.status = FriendRequestStatus.accepted;
      }
    }
    await _save(data);

    await markRoomAsDirect(request.peer, roomId);
    // 只是「被邀请」的话发不了状态事件，而且双方不在同一个会话里。
    await _ensureJoined(roomId);
    final profile = await client.fetchOwnProfile();
    try {
      await client.setRoomStateWithKey(roomId, acceptRoomEventType, me, {
        'by': me,
        'name': profile.displayName ?? me.localpart,
        'avatar_url': profile.avatarUrl?.toString(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e, s) {
      // 对方可能还没进房间，事件发不出去不影响本地名单。
      debugPrint('[friends] accept event failed: $e $s');
    }
  }

  Future<void> rejectRequest(FriendRequestEntry request) async {
    final me = client.userID;
    final data = load();
    for (final r in data.incoming) {
      if (r.peer == request.peer) r.status = FriendRequestStatus.rejected;
    }
    for (final r in data.outgoing) {
      if (r.peer == request.peer) r.status = FriendRequestStatus.rejected;
    }
    await _save(data);

    // 让发起方也知道被拒了（否则他那边一直显示「等待验证」）。
    final roomId = request.roomId;
    if (me == null || roomId == null) return;
    await _ensureJoined(roomId);
    try {
      await client.setRoomStateWithKey(roomId, rejectRoomEventType, me, {
        'by': me,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[friends] reject event failed: $e');
    }
  }

  /// 被邀请状态下进房间，之后才能发状态事件，也让双方落在同一个 room_id 上。
  Future<void> _ensureJoined(String roomId) async {
    final room = client.getRoomById(roomId);
    if (room == null) return;
    if (room.membership == Membership.join) return;
    if (room.membership != Membership.invite) return;
    try {
      await client.joinRoomById(roomId);
    } catch (e) {
      debugPrint('[friends] join $roomId failed: $e');
    }
  }

  /// 删好友：本地名单删掉，并在私聊房间里留一条 removed 事件，
  /// 对方的客户端收到后会把自己名单里的你也删掉（双向处理）。
  Future<void> removeFriendBothWays(String userId) async {
    final me = client.userID!;
    await removeFriend(userId);
    for (final room in client.rooms) {
      if (room.directChatMatrixID != userId) continue;
      try {
        await client.setRoomStateWithKey(room.id, removedRoomEventType, me, {
          'by': me,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (e) {
        debugPrint('[friends] removed event failed: $e');
      }
      break;
    }
  }

  // ---------------------------------------------------------------- 从房间回收

  /// 扫描所有房间的状态事件，把对方发来的申请/接受/删除同步进本地 account data。
  /// 返回是否有变化（有变化时界面该刷新）。
  Future<bool> syncFromRooms() async {
    if (!client.isLogged()) return false;
    final me = client.userID!;
    final data = load();
    var changed = false;

    for (final room in client.rooms) {
      if (room.membership == Membership.leave) continue;
      // 收到的申请
      final requestStates = room.states[requestRoomEventType];
      if (requestStates != null) {
        for (final event in requestStates.values) {
          final content = event.content;
          final from = content['from'] as String?;
          if (from == null || from == me) continue;
          final ts = (content['ts'] as num?)?.toInt() ?? 0;
          final existing = data.incoming.firstWhere(
            (r) => r.peer == from,
            orElse: () => FriendRequestEntry(peer: from, ts: 0),
          );
          // 同一来源只保留一条；更新的申请覆盖旧内容，但已处理的状态不倒退。
          if (data.incoming.any((r) => r.peer == from) && existing.ts >= ts) {
            continue;
          }
          final entry = FriendRequestEntry(
            peer: from,
            message: (content['message'] ?? '') as String? ?? '',
            peerName: content['from_name'] as String?,
            avatarUrl: content['avatar_url'] as String?,
            ts: ts,
            roomId: room.id,
            status: existing.status == FriendRequestStatus.accepted
                ? FriendRequestStatus.accepted
                : FriendRequestStatus.pending,
          );
          data.incoming.removeWhere((r) => r.peer == from);
          data.incoming.add(entry);
          changed = true;
        }
      }

      // 对方接受了我的申请 → 双方互为好友
      final acceptStates = room.states[acceptRoomEventType];
      if (acceptStates != null) {
        for (final event in acceptStates.values) {
          final by = (event.content['by'] as String?) ?? event.stateKey;
          if (by == null || by == me) continue;
          if (data.isFriend(by)) continue;
          // 名字/头像：新版客户端会把资料写进事件；老事件只能回落到房间成员信息。
          final member = room.getState(EventTypes.RoomMember, by);
          final eventName = (event.content['name'] as String?)?.trim();
          final memberName =
              (member?.content['displayname'] as String?)?.trim() ?? '';
          final avatar =
              (event.content['avatar_url'] as String?) ??
              (member?.content['avatar_url'] as String?);
          data.friends.add(
            FriendEntry(
              userId: by,
              displayName: (eventName != null && eventName.isNotEmpty)
                  ? eventName
                  : memberName,
              avatarUrl: avatar,
            ),
          );
          for (final r in data.incoming) {
            if (r.peer == by) r.status = FriendRequestStatus.accepted;
          }
          for (final r in data.outgoing) {
            if (r.peer == by) r.status = FriendRequestStatus.accepted;
          }
          changed = true;
        }
      }

      // 对方删了我 → 我也删掉他
      final removedStates = room.states[removedRoomEventType];
      if (removedStates != null) {
        for (final event in removedStates.values) {
          final by = event.content['by'] as String?;
          if (by == null || by == me) continue;
          if (!data.isFriend(by)) continue;
          data.friends.removeWhere((f) => f.userId == by);
          changed = true;
        }
      }

      // 对方拒绝了申请 → 只把 outgoing 标成已拒绝，绝不写进好友名单。
      final rejectStates = room.states[rejectRoomEventType];
      if (rejectStates != null) {
        for (final event in rejectStates.values) {
          final by = (event.content['by'] as String?) ?? event.stateKey;
          if (by == null || by == me) continue;
          for (final r in data.outgoing) {
            if (r.peer == by && r.status == FriendRequestStatus.pending) {
              r.status = FriendRequestStatus.rejected;
              changed = true;
            }
          }
        }
      }
    }

    if (changed) await _save(data);
    return changed;
  }
}

/// 全局只保留一份同步监听，避免多个页面重复订阅。
class FriendsSync {
  static final Set<String> _started = {};
  static final Map<String, StreamSubscription<SyncUpdate>> _subs = {};
  static DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _scanning = false;

  static void start(Client client) {
    final me = client.userID;
    if (me == null) return;
    if (_subs.containsKey(me)) return;
    final service = FriendsService(client);
    unawaited(service.ensureDirectRooms());
    unawaited(service.syncFromRooms());
    _subs[me] = client.onSync.stream.listen((_) => _throttledScan(service));
  }

  /// 每个 sync 都全量扫房间太浪费，5 秒内只扫一次。
  static void _throttledScan(FriendsService service) {
    if (_scanning) return;
    final now = DateTime.now();
    if (now.difference(_lastScan) < const Duration(seconds: 5)) return;
    _lastScan = now;
    _scanning = true;
    unawaited(service.syncFromRooms().whenComplete(() => _scanning = false));
  }

  /// 通讯录下拉刷新用：无视节流，立刻扫一次。
  static Future<void> scanNow(Client client) =>
      FriendsService(client).syncFromRooms();

  static void stop() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
    _started.clear();
  }
}
