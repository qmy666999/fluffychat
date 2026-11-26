import 'package:matrix/matrix.dart';

/// 被「删除好友」隐藏掉的私聊房间。
///
/// 删除好友时**不能**退群（`leaveRoom`）：服务器会把「你退出了群聊」发给对方，
/// 而且以后再想加回来得从头进房间。微信的做法是只把会话从列表里拿掉，房间和
/// 历史消息都还在。所以这里把房间 id 记到账号数据里，会话列表按它过滤；
/// 对方再发消息（或有新未读）时自动解除隐藏，会话重新出现。
class HiddenRoomsService {
  static const String eventType = 'com.dafeiyu.hidden_rooms';
  static const String _roomsKey = 'rooms';

  final Client client;

  const HiddenRoomsService(this.client);

  Set<String> load() {
    final ids = <String>{};
    final raw = client.accountData[eventType]?.content[_roomsKey];
    if (raw is List) {
      for (final item in raw) {
        if (item is String && item.isNotEmpty) ids.add(item);
      }
    }
    return ids;
  }

  bool isHidden(String roomId) => load().contains(roomId);

  Future<void> hide(String roomId) async {
    final ids = load();
    if (!ids.add(roomId)) return;
    await _save(ids);
  }

  Future<void> hideAll(Iterable<String> roomIds) async {
    final ids = load();
    var changed = false;
    for (final roomId in roomIds) {
      if (ids.add(roomId)) changed = true;
    }
    if (changed) await _save(ids);
  }

  Future<void> unhide(String roomId) async {
    final ids = load();
    if (!ids.remove(roomId)) return;
    await _save(ids);
  }

  Future<void> _save(Set<String> ids) async {
    final me = client.userID;
    if (me == null) return;
    await client.setAccountData(me, eventType, {_roomsKey: ids.toList()});
  }

  /// 收到新消息（或自己又在这个会话里发了消息）时，把它从隐藏列表里放出来。
  ///
  /// 返回是否有变化，用来决定要不要刷新会话列表。
  static Future<bool> autoUnhide(Client client) async {
    if (!client.isLogged()) return false;
    final service = HiddenRoomsService(client);
    final hidden = service.load();
    if (hidden.isEmpty) return false;
    final me = client.userID;
    final visible = <String>[];
    for (final room in client.rooms) {
      if (!hidden.contains(room.id)) continue;
      if (room.membership != Membership.join) continue;
      // 自己发过言，或者有别人发来的未读 → 说明用户在跟这个人继续聊，
      // 会话该回到列表里；只是历史未读（旧消息）不算。
      final lastEvent = room.lastEvent;
      if (lastEvent == null) continue;
      if (lastEvent.senderId == me || room.notificationCount > 0) {
        visible.add(room.id);
      }
    }
    if (visible.isEmpty) return false;
    final ids = service.load()..removeAll(visible);
    await service._save(ids);
    return true;
  }
}
