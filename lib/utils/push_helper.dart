// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/call_kit_params.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/notifications/notification_log.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:fluffychat/utils/wechat/remark_service.dart';
import 'package:fluffychat/utils/wechat/room_kind.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:flutter_shortcuts_new/flutter_shortcuts_new.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

final Map<String, DateTime> lastReceivedPushNotification = {};

final _pushLock = Lock();

Future<void> pushHelper(
  PushNotification notification, {
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  // 后台推送模式下，处理完一条推送就把前台服务收掉（省电）。但 App 自己在前台
  // 服务里跑 sync 并弹本地通知时不能收，否则常驻通知会跟着消失。
  bool stopForegroundService = true,
}) async {
  l10n ??= await lookupL10n(PlatformDispatcher.instance.locale);

  try {
    await _pushLock.synchronized(
      () => _tryPushHelper(
        notification,
        clients: clients,
        l10n: l10n,
        activeRoomId: activeRoomId,
        flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
      ).timeout(const Duration(seconds: 30)),
    );
  } catch (e, s) {
    if (e.toString() == 'Exception: Client is not logged in.') {
      Logs().w('Ignore push notification, when not logged in', e);
      return;
    }
    if (PlatformInfos.isAndroid &&
        e is! TimeoutException &&
        e is! IOException &&
        e is! http.ClientException) {
      Logs().e('Push Helper has crashed! Writing into temporary file...', e, s);
      final store = await SharedPreferences.getInstance();
      await store.setStringList(AppConfig.pushHelperCrashReportKey, [
        e.toString(),
        s.toString(),
      ]);
    }

    NotificationLog.add('pushHelper 异常，走兜底通知: $e');
    if (notification.roomId != null) {
      await flutterLocalNotificationsPlugin.show(
        id: notification.notificationId,
        title: l10n.newMessageInFluffyChat,
        body: l10n.openAppToReadMessages,
        notificationDetails: NotificationDetails(
          iOS: DarwinNotificationDetails(
            threadIdentifier:
                '${notification.clientName}_${notification.roomId}',
          ),
          android: AndroidNotificationDetails(
            AppConfig.pushNotificationsChannelId,
            l10n.incomingMessages,
            number: notification.counts?.unread,
            ticker: l10n.unreadChatsInApp(
              AppSettings.applicationName.value,
              (notification.counts?.unread ?? 0).toString(),
            ),
            importance: Importance.high,
            priority: Priority.max,
            shortcutId: notification.roomId,
            category: AndroidNotificationCategory.message,
            groupKey: notification.clientName,
          ),
        ),
      );
    }
    rethrow;
  } finally {
    if (stopForegroundService && !_pushLock.locked) {
      ForegroundServices.stopService('background_push');
    }
  }
}

/// 本地要不要为这条事件弹通知。
///
/// 以前这里直接写 `client.pushruleEvaluator.match(event).notify`，有两个坑：
/// 1. SDK 在没有拿到 `m.push_rules` 账号数据时 `pushruleEvaluator` 是一个
///    空规则集，任何事件都匹配不到规则，默认返回 `notify = false`
///    —— 结果全世界所有消息都被当成「免打扰」丢掉；
/// 2. 普通消息的规则 actions 里是 `set_tweak: highlight, value: false`，
///    highlight 只影响要不要横幅，不参与「要不要通知」。
///
/// 现在的规则：只有「用户明确静音」才拦，其余一律放行。
/// - `.m.rule.master` 打开（全局静音）→ 不弹；
/// - 房间级免打扰（`room.pushRuleState == dontNotify`）→ 不弹；
/// - 只收 @ 提及（`mentionsOnly`）时，没被提及 → 不弹；
/// - 其余情况（包括没拿到规则集）→ 弹。
bool _shouldNotifyLocally(Client client, Event event) {
  final room = event.room;
  final state = room.pushRuleState;
  final matched = client.pushruleEvaluator.match(event);
  final master = client.allPushNotificationsMuted;
  NotificationLog.add(
    'pushHelper 规则检查 room=${room.id} rules=${client.globalPushRules != null} '
    'master=$master roomState=${state.name} '
    'notify=${matched.notify} highlight=${matched.highlight}',
  );

  if (master) {
    NotificationLog.add('跳过：全局静音（.m.rule.master 开启）');
    return false;
  }
  if (state == PushRuleState.dontNotify) {
    NotificationLog.add('跳过：这个聊天被设为「消息免打扰」');
    return false;
  }
  if (state == PushRuleState.mentionsOnly && !matched.highlight) {
    NotificationLog.add('跳过：这个聊天只提醒 @ 我，本条没提及');
    return false;
  }
  // 普通消息、规则集缺失、规则匹配不到 —— 全部放行。
  return true;
}

Future<void> _tryPushHelper(
  PushNotification notification, {
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  final isBackgroundMessage = clients == null;
  Logs().v(
    'Push helper has been started (background=$isBackgroundMessage).',
    notification.toJson(),
  );

  final clientName = notification.clientName;
  final store = await AppSettings.init();

  final client = clientName == null
      ? (clients?.first ??
            (await ClientManager.getClients(
              initialize: false,
              store: store,
            )).first)
      : (clients?.firstWhereOrNull(
              (client) => client.clientName == clientName,
            ) ??
            await ClientManager.createClient(clientName, store));

  lastReceivedPushNotification[client.clientName] = DateTime.now();

  l10n ??= await L10n.delegate.load(PlatformDispatcher.instance.locale);

  Logs().v('Load event...');
  final event = await client.getEventByPushNotification(
    notification,
    storeInDatabase: false,
  );

  updateAppBadge(notification.counts?.unread ?? 0);

  if (event == null) {
    NotificationLog.add(
      'pushHelper: 找不到事件（可能是已读/查不到）'
      ' room=${notification.roomId} event=${notification.eventId}',
    );
    if (client.syncPending) return;
    if (clients?.length == 1 && (notification.counts?.unread == 0)) {
      await flutterLocalNotificationsPlugin.cancelAll();
    } else {
      // Make sure client is fully loaded and synced before dismiss notifications:
      await client.roomsLoading;
      await client
          .oneShotSync()
          .timeout(const Duration(seconds: 8))
          .catchError((_) => null);
      await cancelNotificationsOnSync(
        client.onSync.value!,
        clientName!,
        client.userID!,
        l10n,
        flutterLocalNotificationsPlugin,
      );
    }
    return;
  }

  Logs().v('Push helper got notification event of type ${event.type}.');

  if (!_shouldNotifyLocally(client, event)) return;

  if (event.type == RtcNotificationContent.eventType &&
      event.tryParseRtcNotificationContent()?.notificationType == .ring &&
      PlatformInfos.isMobile) {
    _showIncomingCall(event, l10n);
    return;
  }

  if (notification.roomId != null &&
      activeRoomId == notification.roomId &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    NotificationLog.add('pushHelper: 正在看这个房间，跳过');
    return;
  }

  final matrixLocals = MatrixLocals(l10n);

  // Calculate the body
  final body = event.type == EventTypes.Encrypted
      ? l10n.newMessageInFluffyChat
      : event.calcLocalizedBody(
          matrixLocals,
          plaintextBody: true,
          hideReply: true,
          hideEdit: true,
          removeMarkdown: true,
        );

  // The person object for the android message style notification
  final avatar = event.room.avatar;
  final senderAvatar = isSinglePeerChat(event.room)
      ? avatar
      : event.senderFromMemoryOrFallback.avatarUrl;

  final ownUser = event.room.unsafeGetUserFromMemoryOrFallback(client.userID!);

  final userAvatarFile = await client.tryDownloadNotificationAvatar(
    ownUser.avatarUrl,
  );
  final roomAvatarFile = await client.tryDownloadNotificationAvatar(avatar);
  final senderAvatarFile = await client.tryDownloadNotificationAvatar(
    senderAvatar,
  );

  final id = '${client.clientName}_${notification.roomId}'.hashCode;

  // 标题/发送者名字要跟聊天列表一致：备注优先（否则给好友起了备注，
  // 通知里还是显示对方的原始昵称）。
  final senderName =
      RemarkService(client).remarkOf(event.senderId) ??
      event.senderFromMemoryOrFallback.calcDisplayname();
  // Show notification

  final newMessage = Message(
    body,
    event.originServerTs,
    Person(
      bot: event.messageType == MessageTypes.Notice,
      key: event.senderId,
      name: senderName,
      icon: senderAvatarFile == null
          ? null
          : ByteArrayAndroidIcon(senderAvatarFile),
    ),
  );

  final messagingStyleInformation = PlatformInfos.isAndroid
      ? await AndroidFlutterLocalNotificationsPlugin()
            .getActiveNotificationMessagingStyle(id: id)
      : null;
  messagingStyleInformation?.messages?.add(newMessage);

  final roomName = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

  // 渠道统一用 AppConfig.pushNotificationsChannelId（messages_v2，high）。
  // 以前这里按房间建渠道（渠道 ID = 房间 ID），那些渠道都是默认/静默重要度，
  // 消息发进去会被系统直接丢掉，而且会在系统设置里堆一堆以房间名命名的类别。

  final androidPlatformChannelSpecifics = AndroidNotificationDetails(
    AppConfig.pushNotificationsChannelId,
    l10n.incomingMessages,
    number: notification.counts?.unread,
    category: AndroidNotificationCategory.message,
    shortcutId: event.room.id,
    styleInformation:
        messagingStyleInformation ??
        MessagingStyleInformation(
          Person(
            name: ownUser.calcDisplayname(),
            icon: userAvatarFile == null
                ? null
                : ByteArrayAndroidIcon(userAvatarFile),
            key: event.room.client.userID,
          ),
          conversationTitle: isSinglePeerChat(event.room) ? null : roomName,
          groupConversation: !isSinglePeerChat(event.room),
          messages: [newMessage],
        ),
    ticker: isSinglePeerChat(event.room)
        ? body
        : l10n.senderMessage(senderName, body),
    importance: Importance.high,
    priority: Priority.max,
    groupKey: client.clientName,
    actions: switch (event.type) {
      EventTypes.Message ||
      EventTypes.Encrypted ||
      EventTypes.Sticker => <AndroidNotificationAction>[
        AndroidNotificationAction(
          FluffyChatNotificationActions.reply.name,
          l10n.reply,
          inputs: [AndroidNotificationActionInput(label: l10n.writeAMessage)],
          allowGeneratedReplies: true,
          semanticAction: SemanticAction.reply,
        ),
        AndroidNotificationAction(
          FluffyChatNotificationActions.markAsRead.name,
          l10n.markAsRead,
          semanticAction: SemanticAction.markAsRead,
        ),
        AndroidNotificationAction(
          FluffyChatNotificationActions.mute.name,
          l10n.mute,
          semanticAction: SemanticAction.mute,
        ),
      ],
      RtcNotificationContent.eventType => [
        AndroidNotificationAction(
          FluffyChatNotificationActions.enterCall.name,
          l10n.enterCall,
          semanticAction: SemanticAction.call,
        ),
      ],
      _ => null,
    },
  );
  final iOSAttachmentPath = PlatformInfos.isIOS
      ? await client.getIosNotificationAvatar(event.room.avatar)
      : null;
  final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
    threadIdentifier: '${notification.clientName}_${notification.roomId}',
    attachments: iOSAttachmentPath == null
        ? null
        : [
            DarwinNotificationAttachment(
              iOSAttachmentPath,
              identifier: 'image',
            ),
          ],
  );
  final platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iOSPlatformChannelSpecifics,
  );

  final title = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

  if (PlatformInfos.isAndroid && messagingStyleInformation == null) {
    await _setShortcut(event, l10n, title, roomAvatarFile);
  }

  final needsTitleAndBody = !PlatformInfos.isAndroid;

  await flutterLocalNotificationsPlugin.show(
    id: notification.notificationId,
    title: needsTitleAndBody ? title : null,
    body: needsTitleAndBody ? body : null,
    notificationDetails: platformChannelSpecifics,
    payload: FluffyChatPushPayload(
      client.clientName,
      event.room.id,
      event.eventId,
    ).toString(),
  );

  // Send summary notification on Android
  if (PlatformInfos.isAndroid) {
    await updateSummaryNotification(
      clientName: client.clientName,
      l10n: l10n,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
    );
  }
  NotificationLog.add('pushHelper 完成 room=${event.roomId}');
  Logs().v('Push helper has been completed!');
}

void updateAppBadge(int unreadCount) {
  if (PlatformInfos.isAndroid || PlatformInfos.isMacOS || PlatformInfos.isIOS) {
    if (unreadCount == 0) {
      FlutterNewBadger.removeBadge();
    } else {
      FlutterNewBadger.setBadge(unreadCount);
    }
    return;
  }
}

Future<void> updateSummaryNotification({
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  required String clientName,
  required L10n l10n,
}) async {
  final activeNotifications =
      (await flutterLocalNotificationsPlugin.getActiveNotifications())
          .where((n) => n.groupKey == clientName && n.id != clientName.hashCode)
          .toList();

  if (activeNotifications.isEmpty) {
    await flutterLocalNotificationsPlugin.cancel(id: clientName.hashCode);
    return;
  }

  if (activeNotifications.any(
    (notification) => notification.id == clientName.hashCode,
  )) {
    // Already have a visible summary notification!
    return;
  }

  await flutterLocalNotificationsPlugin.show(
    id: clientName.hashCode,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        AppConfig.pushNotificationsChannelId,
        l10n.incomingMessages,
        groupKey: clientName,
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          activeNotifications.map((n) => n.body ?? '').toList(),
        ),
        autoCancel: false,
        silent: true,
      ),
    ),
  );
}

class FluffyChatPushPayload {
  final String? clientName, roomId, eventId;

  FluffyChatPushPayload(this.clientName, this.roomId, this.eventId);

  factory FluffyChatPushPayload.fromString(String payload) {
    final parts = payload.split('|');
    if (parts.length != 3) {
      return FluffyChatPushPayload(null, null, null);
    }
    return FluffyChatPushPayload(parts.first, parts[1], parts[2]);
  }

  @override
  String toString() => '$clientName|$roomId|$eventId';
}

/// Creates a shortcut for Android platform but does not block displaying the
/// notification. This is optional but provides a nicer view of the
/// notification popup.
Future<void> _setShortcut(
  Event event,
  L10n l10n,
  String title,
  Uint8List? avatarFile,
) async {
  final flutterShortcuts = FlutterShortcuts();
  await flutterShortcuts.initialize(debug: !kReleaseMode);
  await flutterShortcuts.pushShortcutItem(
    shortcut: ShortcutItem(
      id: event.room.id,
      action: AppConfig.inviteLinkPrefix + event.room.id,
      shortLabel: title,
      conversationShortcut: true,
      icon: avatarFile == null ? null : base64Encode(avatarFile),
      shortcutIconAsset: avatarFile == null
          ? ShortcutIconAsset.androidAsset
          : ShortcutIconAsset.memoryAsset,
      isImportant: event.room.isFavourite,
    ),
  );
}

extension on PushNotification {
  String? get clientName =>
      devices?.firstOrNull?.data?.tryGet<String>('client_name');
  int get notificationId {
    final roomId = this.roomId;
    if (roomId == null) return 0;
    final clientName = this.clientName;
    if (PlatformInfos.isCupertinoStyle) {
      return '${clientName}_${roomId}_$eventId'.hashCode;
    }
    if (clientName == null) return roomId.hashCode;
    return '${clientName}_$roomId'.hashCode;
  }
}

Future<void> _showIncomingCall(Event event, L10n l10n) async {
  final callId = '${event.room.id}|${event.room.client.clientName}';
  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls.any((call) => call.id == callId)) {
    Logs().d(
      'Call with this ID is already active. Ignoring this Push Notification...',
      callId,
    );
    return;
  }
  final intentStr = event.content.tryGet<String>('m.call.intent');
  final intent =
      MatrixRtcCallIntent.values.singleWhereOrNull(
        (i) => i.name == intentStr,
      ) ??
      .video;
  final timeout =
      event.tryParseRtcNotificationContent()?.lifetime ??
      RtcNotificationContent.defaultLifetime;
  final params = await buildFluffyChatCallKitParams(
    event.room,
    l10n: l10n,
    intent: intent,
    timeout: timeout,
  );
  final timeoutDateTime = DateTime.now().add(timeout);
  await FlutterCallkitIncoming.showCallkitIncoming(params);

  while (DateTime.now().isBefore(timeoutDateTime)) {
    await event.room.client.oneShotSync();
    if (!event.room.hasActiveMatrixRtcCall) {
      Logs().i('The other party has ended the call');
      await FlutterCallkitIncoming.endCall(params.id);
      break;
    }
    if (event.room.ownMatrixRtcMembership != null) {
      Logs().d('User has joined the call.');
      break;
    }
    if (event.room.getActiveMatrixRtcMembers().any(
      (member) =>
          member.senderId == event.room.client.userID! &&
          member.deviceId != event.room.client.deviceID!,
    )) {
      Logs().i('User has accepted the call on a different device');
      await FlutterCallkitIncoming.endCall(params.id);
      break;
    }
  }
}

Future<void> cancelNotificationsOnSync(
  SyncUpdate syncUpdate,
  String clientName,
  String userId,
  L10n l10n,
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
) async {
  final newReadRoomIds =
      syncUpdate.rooms?.join?.entries
          .where(
            (entry) =>
                (entry.value.ephemeral?.any(
                      (event) =>
                          event.type == 'm.receipt' &&
                          event.content.values.any(
                            (value) =>
                                value is Map<String, Object?> &&
                                (value
                                            .tryGetMap<String, Object?>(
                                              'm.read',
                                            )
                                            ?.keys
                                            .contains(userId) ==
                                        true ||
                                    value
                                            .tryGetMap<String, Object?>(
                                              'm.read.private',
                                            )
                                            ?.keys
                                            .contains(userId) ==
                                        true),
                          ),
                    ) ??
                    false) &&
                entry.value.unreadNotifications?.notificationCount == 0,
          )
          .map((entry) => entry.key)
          .toSet() ??
      {};
  if (newReadRoomIds.isEmpty) return;

  List<ActiveNotification>? activeNotifications;

  for (final roomId in newReadRoomIds) {
    if (PlatformInfos.isMacOS || PlatformInfos.isIOS || PlatformInfos.isWeb) {
      activeNotifications ??= await flutterLocalNotificationsPlugin
          .getActiveNotifications();
      for (final notification in activeNotifications) {
        final payload = FluffyChatPushPayload.fromString(
          notification.payload ?? '',
        );
        if (payload.clientName != clientName || payload.roomId != roomId) {
          continue;
        }
        final id = notification.id;
        // TODO: notifications from NSE have no id. How to clean them up?
        if (id == null) continue;
        await flutterLocalNotificationsPlugin.cancel(id: id);
      }
      continue;
    }
    final id = '${clientName}_$roomId'.hashCode;
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  if (PlatformInfos.isAndroid) {
    await updateSummaryNotification(
      clientName: clientName,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
      l10n: l10n,
    );
  }
}
