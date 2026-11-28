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

/// 当前是否允许「安装未知应用」。
///
/// Android 8+ 每个 App 需要单独授权，没开的时候调起安装器**可能什么都不发生**
/// （不抛异常），所以安装前必须先问一下 PackageManager。
/// 非 Android 平台直接返回 true（不需要这个权限）。
Future<bool> canInstallPackages() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final result = await _channel.invokeMethod<bool>('canInstallPackages');
    return result ?? false;
  } catch (e) {
    debugPrint('[AppSettings] canInstallPackages failed: $e');
    return false;
  }
}

/// 跳到「安装未知应用」授权页（`ACTION_MANAGE_UNKNOWN_APP_SOURCES`）。
Future<bool> openInstallPermissionSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final result = await _channel.invokeMethod<bool>(
      'openInstallPermissionSettings',
    );
    return result ?? false;
  } catch (e) {
    debugPrint('[AppSettings] openInstallPermissionSettings failed: $e');
    return false;
  }
}
