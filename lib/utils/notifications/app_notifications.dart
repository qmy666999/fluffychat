// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知渠道的统一入口。
///
/// 为什么 ID 都带 `_v2`：Android 的 `NotificationChannel` 属性一旦创建就
/// **不能再改**（`createNotificationChannel` 对已存在的 ID 只是空操作），
/// 而旧版本里有个渠道是用占位符字符串 `loadingMessages` 当名字、且重要度
/// 被建成了最低，结果发进去的通知全被系统吞掉。换 ID 才能让系统重新按新
/// 属性建一份。
class AppNotifications {
  const AppNotifications._();

  /// 新消息：高重要度，有声音、有横幅、有角标。
  static const String messagesChannelId = 'messages_v2';

  /// 来电：最高重要度。
  static const String callsChannelId = 'calls_v2';

  /// 后台收消息的常驻通知：最低重要度，不响不震，状态栏无图标。
  static const String keepAliveChannelId = 'keep_alive_v2';

  /// 历史渠道，启动时清掉，免得设置页里留着名字是占位符的死渠道。
  static const List<String> legacyChannelIds = <String>[
    'fluffychat_sync',
    'keep_alive',
    'fluffychat_push',
  ];

  /// 建好三个渠道并删除历史渠道。幂等，可以每次启动都调。
  static Future<void> ensureChannels(
    FlutterLocalNotificationsPlugin plugin,
    L10n l10n,
  ) async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        messagesChannelId,
        l10n.messagesChannelName,
        description: l10n.messagesChannelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
        enableLights: true,
      ),
    );
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        callsChannelId,
        l10n.callsChannelName,
        description: l10n.callsChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        keepAliveChannelId,
        l10n.keepAliveNotification,
        description: l10n.keepAliveNotificationDescription,
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    for (final id in legacyChannelIds) {
      // 渠道可能本来就不存在，删不掉也不影响。
      try {
        await android.deleteNotificationChannel(channelId: id);
      } catch (_) {}
    }

    // 老版本还给每个房间单独建过渠道（渠道 ID 就是房间 ID，以 `!` 开头），
    // 这些渠道同样都是静默级别，消息发进去照样被系统丢掉。新版本统一只用
    // `messages_v2`，这里把房间渠道一并清掉。
    try {
      final channels = await android.getNotificationChannels();
      for (final channel in channels ?? const <AndroidNotificationChannel>[]) {
        if (!channel.id.startsWith('!')) continue;
        try {
          await android.deleteNotificationChannel(channelId: channel.id);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 发一条测试通知，手动验证「权限 + 渠道 + show」三件事是否真的通了。
  ///
  /// 返回 `false` 表示系统通知权限没开（或不是 Android），这时点再多次也
  /// 不会有通知 —— 只能去系统设置里打开。
  static Future<bool> showTestNotification(
    FlutterLocalNotificationsPlugin plugin,
    L10n l10n,
  ) async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    final enabled = await android.areNotificationsEnabled() ?? true;
    if (!enabled) return false;
    await ensureChannels(plugin, l10n);
    await plugin.show(
      id: 'fluffychatx_notification_test'.hashCode,
      title: l10n.notificationTestTitle,
      body: l10n.notificationTestBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          messagesChannelId,
          l10n.messagesChannelName,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
      ),
    );
    return true;
  }
}
