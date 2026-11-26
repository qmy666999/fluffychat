// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:matrix/matrix.dart';

/// 通讯录「标签」：把好友按自定的组归类（微信的标签就是这么用的）。
///
/// 存在自己的账号数据 [eventType] 里，多设备自动同步：
/// `{ "order": ["大学同学", "同事"], "tags": { "大学同学": ["@a:host"] } }`
class FriendTagsData {
  final List<String> order;
  final Map<String, List<String>> tags;

  const FriendTagsData({required this.order, required this.tags});

  int countOf(String tag) => tags[tag]?.length ?? 0;

  /// 某个好友身上有哪些标签。
  List<String> tagsOf(String userId) => [
    for (final entry in tags.entries)
      if (entry.value.contains(userId)) entry.key,
  ];
}

class FriendTagsService {
  static const String eventType = 'com.dafeiyu.friend_tags';

  final Client client;

  const FriendTagsService(this.client);

  FriendTagsData load() {
    final content = client.accountData[eventType]?.content;
    final rawTags = content?['tags'];
    final order = <String>[];
    final tags = <String, List<String>>{};
    if (rawTags is Map) {
      for (final entry in rawTags.entries) {
        final name = entry.key.toString();
        final value = entry.value;
        if (value is! List) continue;
        tags[name] = value.map((e) => e.toString()).toList();
        order.add(name);
      }
    }
    final rawOrder = content?['order'];
    if (rawOrder is List) {
      final ordered = rawOrder.map((e) => e.toString()).where(tags.containsKey);
      order
        ..clear()
        ..addAll(ordered);
      for (final name in tags.keys) {
        if (!order.contains(name)) order.add(name);
      }
    }
    return FriendTagsData(order: order, tags: tags);
  }

  Future<void> create(String name) async {
    final data = load();
    if (data.tags.containsKey(name)) return;
    data.tags[name] = <String>[];
    data.order.add(name);
    await _save(data);
  }

  Future<void> rename(String from, String to) async {
    final data = load();
    if (!data.tags.containsKey(from) || from == to) return;
    final index = data.order.indexOf(from);
    data.tags[to] = data.tags.remove(from) ?? <String>[];
    if (index != -1) {
      data.order[index] = to;
    } else {
      data.order.add(to);
    }
    await _save(data);
  }

  Future<void> delete(String name) async {
    final data = load();
    data.tags.remove(name);
    data.order.remove(name);
    await _save(data);
  }

  /// 用整份名单覆盖某个标签的成员（添加/移除好友都走这里）。
  Future<void> setFriends(String tag, List<String> userIds) async {
    final data = load();
    if (!data.tags.containsKey(tag)) {
      data.order.add(tag);
    }
    data.tags[tag] = List<String>.from(userIds);
    await _save(data);
  }

  Future<void> toggleFriend(String tag, String userId) async {
    final data = load();
    final members = data.tags.putIfAbsent(tag, () => <String>[]);
    if (members.contains(userId)) {
      members.remove(userId);
    } else {
      members.add(userId);
    }
    await _save(data);
  }

  Future<void> _save(FriendTagsData data) async {
    final userId = client.userID;
    if (userId == null) return;
    await client.setAccountData(userId, eventType, {
      'order': data.order,
      'tags': data.tags,
    });
  }

  /// 标签里还能显示出来的好友（自动过滤已经删掉的人）。
  List<FriendEntry> friendsOf(String tag, FriendsData friends) {
    final ids = load().tags[tag] ?? const <String>[];
    return [
      for (final friend in friends.friends)
        if (ids.contains(friend.userId)) friend,
    ];
  }
}
