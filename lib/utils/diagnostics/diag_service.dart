// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:matrix/matrix.dart';

/// 把本地操作日志上报到一个**自己的私有房间**，方便出 bug 时直接拉取，
/// 不需要用户做任何操作（也不用 adb）。
///
/// 房间：名字 `__diag__`、私有（invite only）、**不加密**（加密了服务端 API
/// 读不到内容），房间 ID 存在账号数据 [roomMarkerKey] 里。
class DiagService {
  DiagService._();

  static final DiagService I = DiagService._();

  static const String roomName = '__diag__';

  static const String roomMarkerKey = 'com.dafeiyu.diag_room';

  static const Duration uploadInterval = Duration(minutes: 5);

  /// 一次最多发 300 行；同时限制字符数，避免单条事件超过服务器 64KB 上限。
  static const int maxLinesPerBatch = 300;

  static const int maxCharsPerBatch = 12000;

  Client? _client;
  Timer? _timer;
  bool _uploading = false;

  Client? get client => _client;

  void start(Client client) {
    _client = client;
    _timer?.cancel();
    _timer = Timer.periodic(uploadInterval, (_) => unawaited(uploadNow()));
    // 启动后先等一会儿再传，避免和登录/同步抢带宽。
    unawaited(Future<void>.delayed(const Duration(seconds: 20), uploadNow));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _client = null;
  }

  /// 找到或创建诊断房间。
  Future<Room?> ensureRoom(Client client) async {
    final userId = client.userID;
    if (userId == null) return null;

    final marker = client.accountData[roomMarkerKey]?.content['room_id'];
    if (marker is String && marker.isNotEmpty) {
      final existing = client.getRoomById(marker);
      if (existing != null && existing.membership == Membership.join) {
        return existing;
      }
      try {
        await client.joinRoomById(marker);
      } catch (e, s) {
        Logs().w('[diag] 加入已有诊断房间失败', e, s);
      }
      final joined = client.getRoomById(marker);
      if (joined != null && joined.membership == Membership.join) {
        return joined;
      }
    }

    // 账号数据丢了也可能房间还在：先按名字找一遍，避免建出一堆重复房间。
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      if (room.name != roomName) continue;
      await client.setAccountData(userId, roomMarkerKey, {'room_id': room.id});
      return room;
    }

    final roomId = await client.createRoom(
      name: roomName,
      topic: 'FluffyChatX 操作日志（不加密；只记操作事件，不含聊天内容）',
      preset: CreateRoomPreset.privateChat,
    );
    await client.setAccountData(userId, roomMarkerKey, {'room_id': roomId});
    final room = client.getRoomById(roomId);
    if (room != null) {
      Logs().i('[diag] 已创建诊断房间 $roomId');
      return room;
    }
    // 新房间可能还没进 sync，等一下再试。
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final retry = client.getRoomById(roomId);
      if (retry != null) return retry;
    }
    return null;
  }

  /// 立刻上传一批（默认每 5 分钟自动调用一次）。
  Future<void> uploadNow() async {
    final client = _client;
    if (client == null || _uploading) return;
    if (!client.isLogged()) return;
    if (!AppSettings.diagUploadEnabled.value) return;
    _uploading = true;
    try {
      // 网络上限：公网只有 19KB/s 的时候，不给超时等于永久挂住。
      final room = await ensureRoom(
        client,
      ).timeout(const Duration(seconds: 20));
      if (room == null) return;
      if (room.encrypted) {
        // 加密房间服务端读不到内容，干脆别发，省得白占空间。
        Logs().w('[diag] 诊断房间被加密，跳过上报');
        return;
      }
      final pending = await ActionLogger.I.readPending(limit: maxLinesPerBatch);
      if (pending.isEmpty) return;

      final batch = <Map<String, Object?>>[];
      var chars = 0;
      for (final entry in pending) {
        final length = jsonEncode(entry).length;
        if (batch.isNotEmpty && chars + length > maxCharsPerBatch) break;
        batch.add(entry);
        chars += length;
      }
      if (batch.isEmpty) return;

      final body = batch.map(jsonEncode).join('\n');
      await room.sendTextEvent(body).timeout(const Duration(seconds: 20));
      final lastSeq = (batch.last['seq'] as num?)?.toInt();
      if (lastSeq != null) await ActionLogger.I.advanceCursor(lastSeq);
      Logs().i('[diag] 已上报 ${batch.length} 条日志到 ${room.id}');
    } catch (e, s) {
      // 上报失败必须静默重试，不能弹窗打扰用户。
      Logs().w('[diag] 上报失败', e, s);
    } finally {
      _uploading = false;
    }
  }
}
