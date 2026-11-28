// 统一解析「某个用户应该显示哪个头像」。
//
// 之前各处各写一套：气泡旁用 member 状态、顶部栏用 peer.avatarUrl、已读回执用
// getSeenByUsers 里的 User、通知完全没有 largeIcon，于是同一个人的头像在四个地方
// 表现不一样（有的正常、有的永久灰人形）。这里按可靠性从高到低依次取。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

class AvatarResolver {
  const AvatarResolver(this.client);

  final Client client;

  /// 同步解析，返回 null 表示「同步路径上真的拿不到」。
  ///
  /// 顺序：给定房间的成员状态 → 其它房间里该用户的成员状态 → 好友账号数据。
  Uri? resolveSync(String userId, {Room? room}) {
    if (userId.isEmpty) return null;

    final rooms = <Room>[?room, ...client.rooms.where((r) => r.id != room?.id)];
    for (final r in rooms) {
      final member = r.getState(EventTypes.RoomMember, userId);
      final url = member?.content.tryGet<String>('avatar_url');
      if (url != null && url.isNotEmpty) return Uri.tryParse(url);
    }

    final friends =
        client.accountData[FriendsService.friendsEventType]?.content['friends'];
    if (friends is List) {
      for (final friend in friends) {
        if (friend is! Map) continue;
        if (friend['user_id'] != userId) continue;
        final url = friend['avatar_url'];
        if (url is String && url.isNotEmpty) return Uri.tryParse(url);
      }
    }

    return null;
  }

  /// 兜底：同步解析拿不到时直接问服务器要资料（5 秒超时）。
  Future<Uri?> refresh(String userId, {Room? room}) async {
    final cached = resolveSync(userId, room: room);
    if (cached != null) return cached;
    try {
      final profile = await client.getProfileFromUserId(
        userId,
        timeout: const Duration(seconds: 5),
      );
      return profile.avatarUrl;
    } catch (error, stackTrace) {
      Logs().w('[avatar] 拉取资料失败 $userId', error, stackTrace);
      return null;
    }
  }

  /// 给通知下载 96×96 缩略图并落到临时文件，返回路径给 largeIcon 用。
  ///
  /// 3 秒超时：通知不能为了头像晚好几秒才弹；失败返回 null，通知照发。
  Future<String?> notificationIconPath(String userId, {Room? room}) async {
    final cachedPath = _NotificationIconCache.instance.get(userId);
    if (cachedPath != null) return cachedPath;

    final mxc = await refresh(userId, room: room);
    if (mxc == null || mxc.scheme != 'mxc') return null;
    try {
      final bytes = await client
          .downloadMxcCached(
            mxc,
            width: 96,
            height: 96,
            isThumbnail: true,
            thumbnailMethod: ThumbnailMethod.crop,
          )
          .timeout(const Duration(seconds: 3));
      if (bytes.isEmpty) return null;
      return await _NotificationIconCache.instance.store(userId, bytes);
    } catch (error, stackTrace) {
      Logs().w('[avatar] 通知头像下载失败 $userId', error, stackTrace);
      return null;
    }
  }
}

/// 通知头像的落地缓存：同一个人一小时内只下一次，写进临时目录。
class _NotificationIconCache {
  _NotificationIconCache._();

  static final _NotificationIconCache instance = _NotificationIconCache._();

  static const Duration _ttl = Duration(hours: 1);
  static const String _dirName = 'notif_avatar';

  final Map<String, _CachedIcon> _memory = {};

  String? get(String userId) {
    final cached = _memory[userId];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.storedAt) > _ttl) {
      _memory.remove(userId);
      return null;
    }
    if (!File(cached.path).existsSync()) {
      _memory.remove(userId);
      return null;
    }
    return cached.path;
  }

  Future<String?> store(String userId, Uint8List bytes) async {
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/$_dirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final safeName = base64Url
          .encode(utf8.encode(userId))
          .replaceAll('=', '');
      final file = File('${dir.path}/$safeName.img');
      await file.writeAsBytes(bytes, flush: true);
      _memory[userId] = _CachedIcon(file.path, DateTime.now());
      return file.path;
    } catch (error, stackTrace) {
      Logs().w('[avatar] 写通知头像文件失败 $userId', error, stackTrace);
      return null;
    }
  }
}

class _CachedIcon {
  const _CachedIcon(this.path, this.storedAt);

  final String path;
  final DateTime storedAt;
}
