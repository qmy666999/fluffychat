// SPDX-FileCopyrightText: 2026 FluffyChatX contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_tts/flutter_tts.dart';

/// 把消息念出来（长按菜单里的「朗读」）。
///
/// 用系统的 TTS 引擎，不联网、不产生费用。全局只保留一个实例：点第二条消息
/// 时先把上一条停掉，否则两段话会叠在一起。
class SpeechService {
  SpeechService._();

  static final FlutterTts _tts = FlutterTts();

  static bool _configured = false;

  static Future<void> speak(String text) async {
    final message = text.trim();
    if (message.isEmpty) return;

    // 中文优先；引擎不支持时 flutter_tts 会保持默认语音，不抛异常。
    if (!_configured) {
      _configured = true;
      try {
        await _tts.setLanguage('zh-CN');
      } catch (_) {
        // 设备没装中文语音包就按系统默认朗读，不打断用户操作。
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1);
    }

    // 上一段还在念就先停掉，避免叠音。
    await _tts.stop();
    await _tts.speak(message);
  }

  static Future<void> stop() async {
    await _tts.stop();
  }
}
