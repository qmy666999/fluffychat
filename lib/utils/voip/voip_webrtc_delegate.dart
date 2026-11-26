// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as wrtc;

import 'matrix_voip.dart';

/// 把 matrix-dart-sdk 的 VoIP 层接到 flutter_webrtc 上。
///
/// SDK 只负责信令（m.call.*）和 SDP/ICE 的状态机，真正的摄像头、麦克风、
/// 对等连接都由这里创建。FluffyChatX 的 1 对 1 通话走的就是这条路。
class VoipWebRtcDelegate implements WebRTCDelegate {
  late final MatrixVoip voip;

  @override
  wrtc.MediaDevices get mediaDevices => rtc.mediaDevices;

  @override
  Future<wrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => rtc.createPeerConnection(configuration, constraints);

  @override
  Future<void> playRingtone() => voip.startRingtone();

  @override
  Future<void> stopRingtone() => voip.stopRingtone();

  @override
  Future<void> registerListeners(CallSession session) async =>
      voip.attachSession(session);

  @override
  Future<void> handleNewCall(CallSession session) async =>
      voip.handleNewCall(session);

  @override
  Future<void> handleCallEnded(CallSession session) async =>
      voip.handleCallEnded(session);

  @override
  Future<void> handleMissedCall(CallSession session) async =>
      voip.handleMissedCall(session);

  // 群组通话（LiveKit / Element Call）不在这一版的范围里。
  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {}

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {}

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => voip.activeCall.value == null;

  // 未加密房间不需要 SFrame key provider。
  @override
  EncryptionKeyProvider? get keyProvider => null;
}
