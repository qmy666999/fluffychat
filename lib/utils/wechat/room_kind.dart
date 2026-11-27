// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// 微信式判断：这个会话是不是「跟某一个人」的单聊。
///
/// Matrix 自带的 `room.isDirectChat` 只看 `m.direct`，但很多两人房间
/// （对方直接拉人建的、或者以前用别的客户端建的）没有这条映射，
/// 于是会被当成群聊：标题显示房间名、右上角冒出群公告/二维码、
/// 气泡上还会出现昵称。这里改成只看实际成员数：
/// **除自己以外只剩 1 个人就是单聊，3 人及以上才是群聊。**
bool isSinglePeerChat(Room room) {
  if (room.isSpace) return false;
  final joined = room.summary.mJoinedMemberCount;
  if (joined != null) return joined <= 2;
  return _joinedOthers(room).length <= 1;
}

bool isGroupChat(Room room) => !isSinglePeerChat(room);

/// 单聊里对面那个人的 Matrix ID；群聊返回 null。
String? singlePeerUserId(Room room) {
  if (!isSinglePeerChat(room)) return null;
  final direct = room.directChatMatrixID;
  if (direct != null && direct != room.client.userID) return direct;
  final others = _joinedOthers(room);
  return others.isEmpty ? null : others.first.id;
}

List<User> _joinedOthers(Room room) {
  final me = room.client.userID;
  return room
      .getParticipants()
      .where((user) => user.id != me && user.membership == Membership.join)
      .toList();
}

/// 单聊里对面那个人的显示名；群聊或拿不到资料返回 null。
String? singlePeerDisplayname(Room room) {
  final peerId = singlePeerUserId(room);
  if (peerId == null) return null;
  for (final user in room.getParticipants()) {
    if (user.id != peerId) continue;
    final name = user.calcDisplayname().trim();
    if (name.isNotEmpty && name != peerId) return name;
  }
  return null;
}
