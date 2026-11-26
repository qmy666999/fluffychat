// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('chat.fluffychatx/app_settings');

/// 打开系统的「应用通知设置」页面。
///
/// 常驻通知只能做到 MIN 渠道（状态栏无图标），如果用户想彻底关掉它，只能在
/// 系统设置里动手，所以设置页要给一个能直接跳过去的按钮。Android 侧由
/// `MainActivity` 里的 MethodChannel 实现；其它平台返回 false，调用方负责
/// 给出「请手动前往系统设置」的提示。
Future<bool> openAppNotificationSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final result = await _channel.invokeMethod<bool>(
      'openNotificationSettings',
    );
    return result ?? false;
  } catch (e) {
    debugPrint('[AppSettings] openNotificationSettings failed: $e');
    return false;
  }
}
