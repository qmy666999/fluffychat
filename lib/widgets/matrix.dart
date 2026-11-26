// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:fluffychat/utils/uia_request_manager.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:fluffychat/utils/wechat/reminder_service.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/app_update_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../config/setting_keys.dart';
import '../pages/key_verification/key_verification_dialog.dart';
import '../utils/account_bundles.dart';
import '../utils/background_push.dart';
import '../utils/notifications/app_notifications.dart';
import 'local_notifications_extension.dart';

class Matrix extends StatefulWidget {
  final Widget? child;

  final List<Client> clients;

  final Map<String, String>? queryParameters;

  final SharedPreferences store;

  const Matrix({
    this.child,
    required this.clients,
    required this.store,
    this.queryParameters,
    super.key,
  });

  @override
  MatrixState createState() => MatrixState();

  /// Returns the (nearest) Client instance of your application.
  static MatrixState of(BuildContext context) =>
      Provider.of<MatrixState>(context, listen: false);
}

class MatrixState extends State<Matrix> {
  int _activeClient = -1;
  String? activeBundle;

  SharedPreferences get store => widget.store;

  BackgroundPush? backgroundPush;

  final ValueNotifier<String?> activeCallRoomId = ValueNotifier(null);
  final ValueNotifier<CallPosition> callPosition = ValueNotifier(
    CallPosition.fullScreen,
  );

  Client get client {
    if (_activeClient < 0 || _activeClient >= widget.clients.length) {
      return currentBundle!.first!;
    }
    return widget.clients[_activeClient];
  }

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  void setActiveClient(Client? cl) {
    final i = widget.clients.indexWhere((c) => c == cl);
    if (i != -1) {
      _activeClient = i;
    } else {
      Logs().w('Tried to set an unknown client ${cl!.userID} as active');
    }
  }

  List<Client?>? get currentBundle {
    if (!hasComplexBundles) {
      return List.from(widget.clients);
    }
    final bundles = accountBundles;
    if (bundles.containsKey(activeBundle)) {
      return bundles[activeBundle];
    }
    return bundles.values.first;
  }

  Map<String?, List<Client?>> get accountBundles {
    final resBundles =
        <String?, List<({Client? client, AccountBundle? bundle})>>{};
    for (var i = 0; i < widget.clients.length; i++) {
      final bundles = widget.clients[i].accountBundles;
      for (final bundle in bundles) {
        if (bundle.name == null) {
          continue;
        }
        resBundles[bundle.name] ??= [];
        resBundles[bundle.name]!.add((
          client: widget.clients[i],
          bundle: bundle,
        ));
      }
    }
    for (final b in resBundles.values) {
      b.sort(
        (a, b) => a.bundle!.priority == null
            ? 1
            : b.bundle!.priority == null
            ? -1
            : a.bundle!.priority!.compareTo(b.bundle!.priority!),
      );
    }
    return resBundles.map(
      (k, v) => MapEntry(k, v.map((vv) => vv.client).toList()),
    );
  }

  bool get hasComplexBundles => accountBundles.values.any((v) => v.length > 1);

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  Future<Client> getLoginClient() async {
    if (widget.clients.isNotEmpty && !client.isLogged()) {
      return client;
    }
    final candidate = _loginClientCandidate ??=
        await ClientManager.createClient(
            '${AppSettings.applicationName.value}-${DateTime.now().millisecondsSinceEpoch}',
            store,
          )
          ..onLoginStateChanged.stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) {
                if (!widget.clients.contains(_loginClientCandidate)) {
                  widget.clients.add(_loginClientCandidate!);
                }
                ClientManager.addClientNameToStore(
                  _loginClientCandidate!.clientName,
                  store,
                );
                _registerSubs(_loginClientCandidate!.clientName);
                setActiveClient(_loginClientCandidate);
                _loginClientCandidate = null;
                FluffyChatApp.router.go('/backup');
              });
    if (widget.clients.isEmpty) widget.clients.add(candidate);
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onReceipts = <String, StreamSubscription>{};
  final onLogoutSub = <String, StreamSubscription<LoginState>>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};

  /// 全 App 共用一个通知插件实例：建渠道、弹本地通知、处理点击都走它。
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// 每个会话「上一次弹过通知的事件」，避免同一条消息重复弹。
  final Map<String, String> _notifiedEventIds = {};

  String? _cachedPassword;
  Timer? _cachedPasswordClearTimer;

  String? get cachedPassword => _cachedPassword;

  set cachedPassword(String? p) {
    Logs().d('Password cached');
    _cachedPasswordClearTimer?.cancel();
    _cachedPassword = p;
    _cachedPasswordClearTimer = Timer(const Duration(minutes: 10), () {
      _cachedPassword = null;
      Logs().d('Cached Password cleared');
    });
  }

  String? get activeRoomId {
    final route = FluffyChatApp.router.routeInformationProvider.value.uri.path;
    if (!route.startsWith('/rooms/')) return null;
    return route.split('/')[2];
  }

  @override
  void initState() {
    super.initState();
    // 初始状态要拿系统的：否则第一次 sync 时 _lifecycleState 还是 null，
    // 会被当成「不在前台」，一启动就在通知栏刷一堆通知。
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _listener = AppLifecycleListener(onStateChange: didChangeAppLifecycleState);
    initMatrix();
    _scheduleUpdateCheck();
    _startReminderTicker();
  }

  Timer? _reminderTimer;

  /// 每分钟看一次有没有到点的消息提醒（前台才有，见 ReminderService 的说明）。
  void _startReminderTicker() {
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      final entry = await ReminderService.popDue(client);
      if (entry == null || !mounted) return;
      final l10n = L10n.of(context);
      final preview = entry.text.trim();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            preview.isEmpty ? l10n.remindTitle : '${l10n.remindTitle}：$preview',
          ),
          action: SnackBarAction(
            label: l10n.open,
            onPressed: () => FluffyChatApp.router.go('/rooms/${entry.roomId}'),
          ),
        ),
      );
    });
  }

  Timer? _updateCheckTimer;

  /// 启动 5 秒后悄悄检查一次更新，一天最多提示一次。
  void _scheduleUpdateCheck() {
    _updateCheckTimer?.cancel();
    _updateCheckTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      checkAndPromptUpdate(context, automatic: true);
    });
  }

  AppLifecycleListener? _listener;
  AppLifecycleState? _lifecycleState;

  void _registerSubs(String name) {
    final c = getClientByName(name);
    if (c == null) {
      Logs().w(
        'Attempted to register subscriptions for non-existing client $name',
      );
      return;
    }
    onRoomKeyRequestSub[name] ??= c.onRoomKeyRequest.stream.listen((
      RoomKeyRequest request,
    ) async {
      if (widget.clients.any(
        ((cl) =>
            cl.userID == request.requestingDevice.userId &&
            cl.identityKey == request.requestingDevice.curve25519Key),
      )) {
        Logs().i(
          '[Key Request] Request is from one of our own clients, forwarding the key...',
        );
        await request.forwardKey();
      }
    });
    onKeyVerificationRequestSub[name] ??= c.onKeyVerificationRequest.stream
        .listen((KeyVerification request) async {
          var hidPopup = false;
          request.onUpdate = () {
            if (!hidPopup &&
                {
                  KeyVerificationState.done,
                  KeyVerificationState.error,
                }.contains(request.state)) {
              FluffyChatApp.router.pop('dialog');
            }
            hidPopup = true;
          };
          request.onUpdate = null;
          hidPopup = true;
          await KeyVerificationDialog(request: request).show(
            FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
                context,
          );
        });
    onLogoutSub[name] ??= c.onLoginStateChanged.stream
        .where((state) => state == LoginState.loggedOut)
        .listen((_) {
          final loggedInWithMultipleClients = widget.clients.length > 1;

          _cancelSubs(c.clientName);
          unawaited(MatrixVoip.of(c)?.dispose());
          // 退登的可能是「当前账号以外的」账号：把 clients 里的一项删掉会让
          // 后面的下标整体前移，先修正 _activeClient，否则会悄悄切到别的账号。
          final removedIndex = widget.clients.indexOf(c);
          widget.clients.remove(c);
          if (removedIndex != -1) {
            if (removedIndex == _activeClient) {
              _activeClient = -1;
            } else if (removedIndex < _activeClient) {
              _activeClient--;
            }
          }
          ClientManager.removeClientNameFromStore(c.clientName, store);
          InitWithRestoreExtension.deleteSessionBackup(name);

          if (loggedInWithMultipleClients) {
            final snackbarContext =
                FluffyChatApp
                    .router
                    .routerDelegate
                    .navigatorKey
                    .currentContext ??
                context;

            if (!snackbarContext.mounted) return;
            final l10n = L10n.of(snackbarContext);
            ScaffoldMessenger.of(
              snackbarContext,
            ).showSnackBar(SnackBar(content: Text(l10n.oneClientLoggedOut)));
            return;
          }
          FluffyChatApp.router.go('/');
        });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);
    if (PlatformInfos.isWeb || PlatformInfos.isDesktop) {
      c.onSync.stream.first.then((s) {
        if (kIsWeb) {
          WebFlutterLocalNotificationsPlugin().requestNotificationsPermission();
        }
        onNotification[name] ??= c.onNotification.stream.listen(
          showLocalNotification,
        );
      });
    } else if (PlatformInfos.isMobile) {
      // 我们的服务器没有配推送网关（手机上也未必装了 UnifiedPush 分发器），
      // 所以后台收不到推送就永远不会有通知。这里改成：App 不在前台时，每次
      // sync 完自己给自己发一条本地通知，效果和推送通知一样（同一条渠道、
      // 同样的「消息样式」，点击也能回到对应会话）。
      onNotification[name] ??= c.onSync.stream.listen((_) {
        unawaited(_showBackgroundNotifications(c));
      });
    }
    onReceipts[name] ??= c.onSync.stream.listen(
      (syncUpdate) => cancelNotificationsOnSync(
        syncUpdate,
        c.clientName,
        c.userID!,
        // ignore: use_build_context_synchronously
        L10n.of(context),
        _localNotifications,
      ),
    );
    // 1 对 1 通话：每个客户端一个实例，负责信令、铃声和通话状态。
    MatrixVoip.ensure(c);
  }

  void _cancelSubs(String name) {
    onRoomKeyRequestSub[name]?.cancel();
    onRoomKeyRequestSub.remove(name);
    onKeyVerificationRequestSub[name]?.cancel();
    onKeyVerificationRequestSub.remove(name);
    onLogoutSub[name]?.cancel();
    onLogoutSub.remove(name);
    onNotification[name]?.cancel();
    onNotification.remove(name);
    onReceipts[name]?.cancel();
    onReceipts.remove(name);
  }

  Future<void> initMatrix() async {
    if (PlatformInfos.isMobile) {
      backgroundPush = BackgroundPush(
        this,
        onFcmError: (errorMsg, {Uri? link}) async {
          final context =
              FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
              this.context;
          if (!context.mounted) return;
          final result = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).pushNotificationsNotAvailable,
            message: errorMsg,
            okLabel: link == null
                ? L10n.of(context).ok
                : L10n.of(context).learnMore,
            cancelLabel: L10n.of(context).doNotShowAgain,
          );
          if (result == OkCancelResult.ok && link != null) {
            launchUrlString(
              link.toString(),
              mode: LaunchMode.externalApplication,
            );
          }
          if (result == OkCancelResult.cancel) {
            await AppSettings.showNoGoogle.setItem(true);
          }
        },
      );
    }
    if (backgroundPush == null) {
      await _localNotifications.initialize(
        settings: InitializationSettings(
          linux: LinuxInitializationSettings(
            defaultActionName: FluffyChatNotificationActions.open.name,
          ),
          windows: ClientManager.windowsNotificationSettings,
          macOS: const DarwinInitializationSettings(),
          iOS: const DarwinInitializationSettings(),
          android: const AndroidInitializationSettings('notifications_icon'),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: widget.clients,
          router: FluffyChatApp.router,
          l10n: null,
        ),
      );
      if (PlatformInfos.isAndroid) {
        // Android 13 起没有 POST_NOTIFICATIONS 权限的话，通知会被系统直接丢弃，
        // 而且不会报错。之前只有 UnifiedPush 注册成功时才会申请权限，等于永远
        // 申请不到，所以这里启动就先要一次。
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        // 渠道要在第一次 show 之前建好：高/最高/最低三个分开，名字不能再用
        // 占位符，历史坏渠道顺便删掉。
        final l10n = await L10n.delegate.load(
          PlatformDispatcher.instance.locale,
        );
        await AppNotifications.ensureChannels(_localNotifications, l10n);
      }
    }

    for (final c in widget.clients) {
      _registerSubs(c.clientName);
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasDetached = _lifecycleState == AppLifecycleState.detached;
    _lifecycleState = state;
    if (wasDetached) {
      backgroundPush?.openRoomFromNotification(newActivity: true);
    }
    final foreground = state == AppLifecycleState.resumed;
    for (final client in widget.clients) {
      client.syncPresence = state == AppLifecycleState.resumed
          ? null
          : PresenceType.unavailable;
      if (PlatformInfos.isMobile) {
        // 没有推送网关，后台要收消息只能靠 sync 一直跑着：所以进后台也不关
        // backgroundSync，否则一按 Home 就再也收不到通知了。
        client.backgroundSync = true;
        client.requestHistoryOnLimitedTimeline = !foreground;
        Logs().v('Set background sync to', true);
      }
    }
    if (PlatformInfos.isMobile) {
      unawaited(_syncForegroundService(foreground));
    }
  }

  /// 前后台切换时开/关常驻前台服务。
  ///
  /// 后台跑着 sync 却没有前台服务时，系统随时可能把进程掐掉；有了前台服务
  /// 才能稳定收消息。前台服务自带一条最低优先级的通知（渠道
  /// `keep_alive_v2`，静音、不进状态栏图标），回前台就把它收掉。
  Future<void> _syncForegroundService(bool foreground) async {
    try {
      if (foreground) {
        Logs().i('[fgs] app resumed, stop keep-alive service');
        await ForegroundServices.stopService('background_push');
      } else {
        Logs().i('[fgs] app in background, start keep-alive service');
        await ForegroundServices.startService('background_push');
      }
    } catch (e, s) {
      // Android 12+ 从后台启动前台服务可能被系统拒绝，这里只是尽量争取，
      // 失败也不影响消息通知本身。
      Logs().w('[fgs] 前台服务切换失败', e, s);
    }
  }

  /// App 不在前台时，把「有新未读消息的会话」变成系统通知。
  ///
  /// 走的是 `pushHelper` 这条现成的路：它负责判断推送规则（免打扰的会话不
  /// 弹）、拼消息样式、下载头像、挂上回复/标记已读按钮，点击也能直接回到
  /// 对应会话。我们只是把「服务器推过来的通知」换成「本地 sync 拼出来的
  /// 通知」，因为这台服务器没有配推送网关。
  Future<void> _showBackgroundNotifications(Client client) async {
    if (!PlatformInfos.isMobile) return;
    if (_lifecycleState == AppLifecycleState.resumed) return;
    if (!client.isLogged()) return;
    // 设置 → 新消息通知里关掉了「接收新消息通知」就什么都不弹。
    if (!WechatPrefs.notifyReceive) return;
    final l10n = await L10n.delegate.load(PlatformDispatcher.instance.locale);
    if (!mounted) return;

    for (final room in client.rooms) {
      final lastEvent = room.lastEvent;
      if (lastEvent == null) continue;
      if (lastEvent.senderId == client.userID) continue;
      if (room.notificationCount <= 0) continue;
      if (room.membership != Membership.join) continue;
      final key = '${client.clientName}|${room.id}';
      if (_notifiedEventIds[key] == lastEvent.eventId) continue;
      _notifiedEventIds[key] = lastEvent.eventId;
      Logs().i('[notif] room=${room.id} event=${lastEvent.eventId}');
      try {
        await pushHelper(
          PushNotification(
            roomId: room.id,
            eventId: lastEvent.eventId,
            counts: PushNotificationCounts(unread: room.notificationCount),
            devices: [
              PushNotificationDevice(data: {'client_name': client.clientName}),
            ],
            prio: 'high',
          ),
          clients: [client],
          l10n: l10n,
          activeRoomId: activeRoomId,
          flutterLocalNotificationsPlugin: _localNotifications,
          // App 自己就在前台服务里跑 sync，弹完通知不能把服务收掉，
          // 否则常驻通知会跟着消失、进程也失去保护。
          stopForegroundService: false,
        );
      } catch (e, s) {
        Logs().w('[notif] 发送通知失败', e, s);
      }
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _reminderTimer?.cancel();
    _listener?.dispose();

    for (final sub in onRoomKeyRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onKeyVerificationRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onLogoutSub.values) {
      sub.cancel();
    }
    for (final sub in onNotification.values) {
      sub.cancel();
    }
    for (final sub in onUiaRequest.values) {
      sub.cancel();
    }
    for (final sub in onReceipts.values) {
      sub.cancel();
    }
    onRoomKeyRequestSub.clear();
    onKeyVerificationRequestSub.clear();
    onLogoutSub.clear();
    onNotification.clear();
    onUiaRequest.clear();

    voiceMessageEventId.dispose();

    for (final c in widget.clients) {
      unawaited(MatrixVoip.of(c)?.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(create: (_) => this, child: widget.child);
  }

  Future<void> dehydrateAction(BuildContext context) async {
    final l10n = L10n.of(context);
    final response = await showOkCancelAlertDialog(
      context: context,
      isDestructive: true,
      title: l10n.dehydrate,
      message: l10n.dehydrateWarning,
    );
    if (response != OkCancelResult.ok) {
      return;
    }
    if (!context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: client.exportDump,
    );
    final export = result.result;
    if (export == null) return;

    final exportBytes = Uint8List.fromList(const Utf8Codec().encode(export));

    final exportFileName =
        'fluffychat-export-${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}.fluffybackup';

    final file = MatrixFile(bytes: exportBytes, name: exportFileName);
    if (!context.mounted) return;
    file.save(context);
  }
}

enum CallPosition { fullScreen, top }
