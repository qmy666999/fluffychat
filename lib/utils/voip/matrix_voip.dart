// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';

import 'voip_webrtc_delegate.dart';

/// FluffyChatX 的 1 对 1 通话管理器。
///
/// matrix-dart-sdk 自带传统 mesh 通话（房间里的 `m.call.*` 事件），但不负责
/// 摄像头/麦克风和播放器，`Client` 也不会自己创建它。这里用一个客户端一个实例
/// 的方式包一层，顺便把 UI 需要的状态（当前通话、是否有来电）暴露成
/// `ValueNotifier`。
class MatrixVoip extends VoIP {
  MatrixVoip._(Client client, VoipWebRtcDelegate delegate)
    : super(
        client,
        delegate,
        // 提示词要求：对方 30 秒不接就自动挂断。
        timeouts: CallTimeouts(callInviteLifetime: const Duration(seconds: 30)),
      ) {
    delegate.voip = this;
  }

  static final Map<String, MatrixVoip> _instances = {};

  /// 用 `client.clientName` 缓存，退出登录时 [dispose] 清掉。
  static MatrixVoip ensure(Client client) {
    final key = client.clientName;
    final existing = _instances[key];
    if (existing != null) {
      if (identical(existing.client, client)) return existing;
      unawaited(existing.dispose());
    }
    final delegate = VoipWebRtcDelegate();
    final created = MatrixVoip._(client, delegate);
    _instances[key] = created;
    return created;
  }

  static MatrixVoip? of(Client client) => _instances[client.clientName];

  /// 只给 STUN，够局域网 / Tailscale 直连用；公网互打要先有 TURN。
  static const _stunServers = [
    'stun:stun.miwifi.com:3478',
    'stun:stun.l.google.com:19302',
  ];

  /// 当前正在进行的通话（主叫、被叫、已接听都算）。
  final ValueNotifier<CallSession?> activeCall = ValueNotifier(null);

  /// 每次状态变化 +1，页面监听它重建，避免直接 listen 一堆 Stream。
  final ValueNotifier<int> revision = ValueNotifier(0);

  final Set<CallSession> _attached = {};
  AudioPlayer? _ringtonePlayer;
  bool speakerOn = false;

  Room? get room => activeCall.value?.room;
  CallSession? get session => activeCall.value;
  bool get hasCall => activeCall.value != null;

  void _bump() => revision.value = revision.value + 1;

  @override
  Future<List<Map<String, dynamic>>> getIceServers() async {
    final servers = await super.getIceServers();
    return [
      ...servers,
      {'urls': _stunServers},
    ];
  }

  /// 主动呼叫。返回 null 表示已经有别的通话在跑了。
  Future<CallSession?> startCall(Room room, CallType type) async {
    if (hasCall) return null;
    final peer = room.directChatMatrixID;
    await _setSpeakerphone(false);
    final call = await inviteToCall(room, type, userId: peer);
    activeCall.value = call;
    _bump();
    return call;
  }

  Future<void> handleNewCall(CallSession session) async {
    if (session.isGroupCall) return;
    if (session.isOutgoing) {
      activeCall.value ??= session;
      _bump();
      return;
    }
    activeCall.value = session;
    await startRingtone();
    _bump();
  }

  Future<void> handleCallEnded(CallSession session) async {
    await stopRingtone();
    _bump();
  }

  Future<void> handleMissedCall(CallSession session) async {
    await stopRingtone();
    _bump();
  }

  /// SDK 每建立一个 CallSession 都会调用一次这里，用来把状态变化暴露给 UI。
  void attachSession(CallSession session) {
    if (!_attached.add(session)) return;
    session.onCallStateChanged.stream.listen((state) {
      if (state == CallState.kEnded) unawaited(stopRingtone());
      _bump();
    });
    session.onCallEventChanged.stream.listen((_) => _bump());
    session.onStreamAdd.stream.listen((_) => _bump());
    session.onStreamRemoved.stream.listen((_) => _bump());
  }

  // ---------------------------------------------------------------------------
  // 铃声
  // ---------------------------------------------------------------------------

  Future<void> startRingtone() async {
    if (_ringtonePlayer != null) return;
    try {
      final player = AudioPlayer();
      _ringtonePlayer = player;
      await player.setAsset('assets/sounds/call_ring.mp3');
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1);
      unawaited(player.play());
    } catch (e) {
      Logs().w('[VoIP] 铃声播放失败', e);
      _ringtonePlayer = null;
    }
  }

  Future<void> stopRingtone() async {
    final player = _ringtonePlayer;
    _ringtonePlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // ignore
    }
    await player.dispose();
  }

  // ---------------------------------------------------------------------------
  // 通话操作
  // ---------------------------------------------------------------------------

  Future<void> answer() async {
    final call = activeCall.value;
    if (call == null) return;
    await stopRingtone();
    await _setSpeakerphone(false);
    await call.answer();
    _bump();
  }

  Future<void> reject() async {
    final call = activeCall.value;
    if (call == null) return;
    await stopRingtone();
    await call.reject(reason: CallErrorCode.userHangup);
    _bump();
  }

  Future<void> hangup() async {
    final call = activeCall.value;
    if (call == null) return;
    await stopRingtone();
    await call.hangup(reason: CallErrorCode.userHangup);
    _bump();
  }

  Future<void> toggleMute() async {
    final call = activeCall.value;
    if (call == null) return;
    await call.setMicrophoneMuted(!call.isMicrophoneMuted);
    _bump();
  }

  Future<void> toggleVideo() async {
    final call = activeCall.value;
    if (call == null) return;
    await call.setLocalVideoMuted(!call.isLocalVideoMuted);
    _bump();
  }

  Future<void> toggleSpeaker() async {
    await _setSpeakerphone(!speakerOn);
    _bump();
  }

  Future<void> switchCamera() async {
    final tracks = activeCall.value?.localUserMediaStream?.stream
        ?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    await rtc.Helper.switchCamera(tracks.first);
    _bump();
  }

  Future<void> _setSpeakerphone(bool on) async {
    speakerOn = on;
    try {
      await rtc.Helper.setSpeakerphoneOn(on);
    } catch (e) {
      Logs().w('[VoIP] 切换扬声器失败', e);
    }
  }

  /// 通话彻底结束：释放麦克风 / 相机 / 对等连接，并清掉 SDK 内部的记录，
  /// 否则同一个通话 ID 会挡住下一次呼叫。
  Future<void> clear() async {
    final call = activeCall.value;
    activeCall.value = null;
    await stopRingtone();
    if (call != null) {
      _attached.remove(call);
      try {
        await call.cleanUp();
      } catch (e) {
        Logs().w('[VoIP] 释放通话资源失败', e);
      }
      // SDK 不会自己清理 calls / currentCID / incomingCallRoomId，
      // 不清掉的话下一次呼叫会被当成同一通电话。
      final stale = calls.entries
          .where((entry) => entry.value.callId == call.callId)
          .toList();
      for (final entry in stale) {
        calls.remove(entry.key);
      }
      if (currentCID?.callId == call.callId) currentCID = null;
      incomingCallRoomId.remove(call.room.id);
    }
    await _setSpeakerphone(false);
    _bump();
  }

  /// 退出登录 / 切换账号时一定要调用，不然麦克风会一直开着。
  Future<void> dispose() async {
    await clear();
    unawaited(onIncomingGroupCall.close());
    _instances.remove(client.clientName);
  }
}
