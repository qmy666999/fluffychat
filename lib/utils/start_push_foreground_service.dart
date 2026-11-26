// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/notifications/app_notifications.dart';
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
  /// 只能换一个新的渠道 ID：`fluffychat_sync`（旧版本，名字还是占位符）和
  /// `keep_alive`（1.14.1 用过的）都会在启动时被删掉，现在统一走
  /// `keep_alive_v2`（见 `AppNotifications.keepAliveChannelId`）。
  ///
  /// MIN 渠道的效果：状态栏不出现图标、不响不震不弹横幅，只在通知中心的
  /// 「其他通知 / 静默通知」折叠区里能看到一行「正在接收消息」。这是系统对
  /// 前台服务的硬性要求（Android 8+），去掉它系统就会把服务杀掉。
  static const String keepAliveChannelId = AppNotifications.keepAliveChannelId;

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
        // dataSync：因为这里是在后台保持同步连接收消息（不是三分钟就结束的
        // 短任务）。用 shortService 会被 Android 14+ 在 3 分钟后掐掉，还可能
        // 抛超时异常。Android 15 对 dataSync 有每日 6 小时上限，超了系统会
        // 自己停服务，对我们来说就是退化成原来的「没有常驻通知」。
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        notificationIcon: const NotificationIcon(metaDataName: 'ic_launcher'),
      );
      final started = result is ServiceRequestSuccess;
      Logs().i('[fgs] foreground service start: $started ($result)');
      return;
    } catch (e, s) {
      Logs().w('[PushHelper] Unable to start foreground service', e, s);
      return;
    }
  }
}
