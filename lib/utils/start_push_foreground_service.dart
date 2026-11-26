// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:universal_html/html.dart' as html;

import '../l10n/l10n.dart';

abstract class ForegroundServices {
  static final List<String> runningServices = [];

  /// 常驻通知专用的通知渠道。
  ///
  /// Android 的渠道属性一旦创建就不能再修改，所以要把渠道从 LOW 改成 MIN
  /// 只能换一个新的渠道 ID：旧的 `fluffychat_sync` 留给已经安装过的设备自然
  /// 废弃，新装和升级后的服务一律走 `keep_alive`。
  ///
  /// MIN 渠道的效果：状态栏不出现图标、不响不震不弹横幅，只在通知中心的
  /// 「其他通知 / 静默通知」折叠区里能看到一行「正在接收消息」。这是系统对
  /// 前台服务的硬性要求（Android 8+），去掉它系统就会把服务杀掉。
  static const String keepAliveChannelId = 'keep_alive';

  /// Android 12+ 禁止应用在后台随意启动前台服务，短时间内反复启动会被系统
  /// 拒绝甚至抛异常。这里做 30 秒防抖，避免推送风暴时反复尝试。
  static const Duration _startDebounce = Duration(seconds: 30);
  static DateTime? _lastStartAttempt;

  static bool get platformSupported =>
      PlatformInfos.isMobile || PlatformInfos.isWeb;

  static bool _beforeUnload(html.Event e) {
    e.preventDefault();
    return true;
  }

  static Future<void> stopService(String name) async {
    runningServices.remove(name);
    if (runningServices.isNotEmpty) return;
    if (kIsWeb) {
      html.window.removeEventListener('beforeunload', _beforeUnload);
      return;
    }
    if (PlatformInfos.isMobile) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> startService(String name) async {
    try {
      runningServices.add(name);
      if (kIsWeb) {
        html.window.addEventListener('beforeunload', _beforeUnload);
        return;
      }
      if (!PlatformInfos.isMobile) return;

      final l10n = await L10n.delegate.load(PlatformDispatcher.instance.locale);
      final title = AppSettings.applicationName.value;
      final text = l10n.keepAliveNotification;

      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: keepAliveChannelId,
          channelName: l10n.keepAliveNotification,
          channelDescription: l10n.keepAliveNotificationDescription,
          channelImportance: NotificationChannelImportance.MIN,
          priority: NotificationPriority.MIN,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showBadge: false,
          showWhen: false,
          visibility: NotificationVisibility.VISIBILITY_SECRET,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
        ),
      );

      if (await FlutterForegroundTask.isRunningService) {
        Logs().d('[PushHelper] Foreground service already running');
        return;
      }

      final last = _lastStartAttempt;
      if (last != null && DateTime.now().difference(last) < _startDebounce) {
        Logs().d('[PushHelper] Skip starting foreground service (debounced)');
        return;
      }
      _lastStartAttempt = DateTime.now();

      final result = await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.shortService],
        notificationTitle: title,
        notificationText: text,
        notificationIcon: const NotificationIcon(metaDataName: 'ic_launcher'),
      );
      final started = result is ServiceRequestSuccess;
      Logs().d('[PushHelper] Foreground service start: $started ($result)');
      return;
    } catch (e, s) {
      Logs().w('[PushHelper] Unable to start foreground service', e, s);
      return;
    }
  }
}
