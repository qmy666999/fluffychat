import 'dart:convert';

import 'package:matrix/matrix.dart';

/// 撤回之后会话列表的预览要回退到上一条可见消息。
///
/// 服务端的房间预览事件（`client.roomPreviewLastEvents`）包含 `m.room.message`，
/// 而撤回只是把原消息的 content 清空（`redacted = true`），事件本身还在，
/// 所以 `room.lastEvent` 仍然指向它。这里再往前翻几条，跳过撤回事件与被撤回
/// 的原消息，找到真正该显示的那一条。
class RedactionPreviewCache {
  RedactionPreviewCache._();

  /// 每个房间只查一次，列表滚动/重建时不会反复请求服务器
  static final Map<String, Future<Event?>> _cache = {};

  /// 这条事件在界面上是不是「已经没有内容了」
  static bool isHiddenPreview(Event? event) =>
      event != null && (event.type == EventTypes.Redaction || event.redacted);

  static Future<Event?> previous(Room room) {
    return _cache.putIfAbsent(room.id, () async {
      try {
        final response = await room.client.getRoomEvents(
          room.id,
          Direction.b,
          limit: 12,
          filter: jsonEncode(
            StateFilter(
              types: room.client.roomPreviewLastEvents.toList(),
            ).toJson(),
          ),
        );
        for (final matrixEvent in response.chunk) {
          final event = Event.fromMatrixEvent(
            matrixEvent,
            room,
            status: EventStatus.synced,
          );
          if (isHiddenPreview(event)) continue;
          return event;
        }
      } catch (e) {
        Logs().w('[redaction] 取上一条预览失败 room=${room.id}', e);
      }
      return null;
    });
  }

  static void invalidate(String roomId) => _cache.remove(roomId);
}
