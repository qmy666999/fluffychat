// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:fluffychat/utils/diagnostics/diag_route_observer.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:matrix/matrix.dart' show Logs;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 诊断功能的启动入口：初始化日志文件（写盘线程、seq、上报游标都在这里恢复）。
///
/// 只记「骨架事件」，**绝不记消息正文 / 图片 / 密码 / token**。
Future<void> initDiagnostics(SharedPreferences store) async {
  await ActionLogger.I.init(store);
}

/// 记录一次启动（版本、构建号、机型、系统版本）。
Future<void> logAppStart() async {
  final extra = <String, Object?>{};
  try {
    final info = await PackageInfo.fromPlatform();
    extra['version'] = info.version;
    extra['build'] = info.buildNumber;
    extra['package'] = info.packageName;
  } catch (e, s) {
    Logs().w('[diag] 读取版本信息失败', e, s);
  }
  extra['os'] = Platform.operatingSystem;
  extra['os_version'] = Platform.operatingSystemVersion;
  try {
    final plugin = DeviceInfoPlugin();
    if (PlatformInfos.isAndroid) {
      final device = await plugin.androidInfo;
      extra['model'] = '${device.manufacturer} ${device.model}';
      extra['android'] = device.version.release;
      extra['sdk'] = device.version.sdkInt;
    } else if (PlatformInfos.isIOS) {
      final device = await plugin.iosInfo;
      extra['model'] = device.utsname.machine;
      extra['ios'] = device.systemVersion;
    }
  } catch (e, s) {
    Logs().w('[diag] 读取机型失败', e, s);
  }
  ActionLogger.I.log('app_start', extra: extra, stack: DiagRouteObserver.stack);
}
