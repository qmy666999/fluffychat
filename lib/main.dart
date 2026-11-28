// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:fluffychat/utils/updates/app_update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/universal_html.dart' as web;

import 'config/motion_settings.dart';
import 'config/server_endpoints.dart';
import 'config/setting_keys.dart';
import 'utils/background_push.dart';
import 'utils/diagnostics/action_logger.dart';
import 'utils/diagnostics/diag_bootstrap.dart';
import 'utils/diagnostics/diag_route_observer.dart';
import 'utils/server_probe.dart';
import 'utils/wechat/wechat_prefs.dart';
import 'widgets/fluffy_chat_app.dart';
import 'widgets/startup_failure_app.dart';

ReceivePort? mainIsolateReceivePort;

bool _vodozemacInitialized = false;

bool isIntegrationTest = false;

/// 启动阶段最多等这么久：12 秒还没画出首帧就直接显示错误页，不再让人对着灰屏。
const Duration _startupWatchdogTimeout = Duration(seconds: 12);

/// `runApp` 有没有被调用过（含兜底页）。用来避免重复 runApp。
bool _bootSettled = false;

void main(List<String> args) => runZonedGuarded(
  () async {
    try {
      await _boot(args);
    } catch (e, s) {
      // 启动路径上的任何异常都不能变成静默灰屏。
      _reportStartupFailure(e, s);
    }
  },
  (error, stack) {
    ActionLogger.I.log(
      'error',
      extra: {'msg': '$error', 'stack': '$stack'},
      stack: DiagRouteObserver.stack,
    );
    if (_bootSettled) {
      // 跑起来之后的异常还是走原来的全局错误对话框。
      ErrorReporter.onFlutterError(error, stack);
      return;
    }
    _reportStartupFailure(error, stack);
  },
);

/// 把启动失败变成一张能读、能复制的错误页，而不是灰屏。
void _reportStartupFailure(Object error, StackTrace stack) {
  debugPrint('FATAL startup: $error\n$stack');
  if (_bootSettled) return;
  _bootSettled = true;
  try {
    runApp(StartupFailureApp(error: '$error\n\n$stack'));
  } catch (e, s) {
    // 连兜底页都画不出来就只能留在 logcat 里了。
    debugPrint('FATAL startup: unable to render failure page: $e\n$s');
  }
}

Future<void> _boot(List<String> args) async {
  // 局域网入口是自签证书，只对私有网段放行，必须在任何 HttpClient 创建之前装上。
  installPrivateCertOverride();

  // Forward Flutter errors to global error reporter
  FlutterError.onError = (details) {
    ActionLogger.I.log(
      'error',
      extra: {
        'msg': details.exceptionAsString(),
        'stack': details.stack?.toString() ?? '',
      },
      stack: DiagRouteObserver.stack,
    );
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ActionLogger.I.log(
      'error',
      extra: {'msg': '$error', 'stack': '$stack'},
      stack: DiagRouteObserver.stack,
    );
    return true;
  };

  isIntegrationTest = args.singleOrNull == 'integration_test';
  if (PlatformInfos.isAndroid) {
    final port = mainIsolateReceivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(AppConfig.mainIsolatePortName);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      AppConfig.mainIsolatePortName,
    );
    await waitForPushIsolateDone();
  }

  // Sanitize hash for OIDC:
  if (kIsWeb) {
    final hash = web.window.location.hash;
    if (hash.isNotEmpty && !hash.startsWith('/')) {
      web.window.location.hash = hash.replaceFirst('#', '#?');
    }
  }

  // Our background push shared isolate accesses flutter-internal things very early in the startup proccess
  // To make sure that the parts of flutter needed are started up already, we need to ensure that the
  // widget bindings are initialized already.
  WidgetsFlutterBinding.ensureInitialized();

  // 首帧没出来之前，任何 widget 构建异常都要能看见文字，不能是纯灰块。
  ErrorWidget.builder = (details) {
    // 只显示异常文字时，`Null check operator used on a null value` 这类
    // 消息没有任何位置信息，等于没法定位。这里把堆栈前 12 帧一起画出来，
    // 同时打到 logcat，用户截个图就够了。
    final stackLines = (details.stack?.toString() ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(12)
        .join('\n');
    debugPrint('[ui-error] ${details.exceptionAsString()}\n$stackLines');
    return StartupErrorPanel(
      message: details.exceptionAsString(),
      stack: stackLines,
    );
  };

  // 启动看门狗：卡在 await 上超过 12 秒也强制给出一张错误页。
  Timer(_startupWatchdogTimeout, () {
    if (_bootSettled) return;
    _reportStartupFailure(
      '启动超过 ${_startupWatchdogTimeout.inSeconds} 秒还没画出首帧'
      '（多半是启动路径上某个 await 卡住了）',
      StackTrace.current,
    );
  });

  // 局域网优先：两个端点并行探测，各 2 秒封顶，最坏让启动慢 2 秒。
  await pickFastestServer();
  Logs().i('[ServerEndpoints] using ${ServerEndpoints.current}');

  final store = await AppSettings.init();
  // 操作日志初始化是纯本地 IO：**不能 await**，它一旦卡住就是永久灰屏。
  // 初始化完成之前的日志会被丢掉，这部分损失可以接受。
  unawaited(
    initDiagnostics(store).timeout(const Duration(seconds: 2)).catchError((
      Object error,
      StackTrace stack,
    ) {
      Logs().w('[diag] 日志初始化失败，跳过（不影响启动）', error, stack);
    }),
  );
  // 动效设置要在任何路由构造之前读进内存（路由里取的是静态字段，不能 await）。
  MotionSettings.load(store);
  WechatPrefs.init(store);
  Logs().i('Welcome to ${AppSettings.applicationName.value} <3');

  kEnableMatrixSdkBenchmarks = AppSettings.benchmarksInLogs.value;

  if (!_vodozemacInitialized) {
    await vod.init(
      wasmPath: './assets/assets/vodozemac/${AppConfig.vodozemacVersion}/',
    );
    _vodozemacInitialized = true;
  }

  Logs().nativeColors = !PlatformInfos.isIOS;

  // If the app starts in detached mode, we assume that it is in
  // background fetch mode for processing push notifications. This is
  // currently only supported on Android.
  if (PlatformInfos.isAndroid &&
      AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState) {
    await ForegroundServices.startService('background_push');

    final clients = await ClientManager.getClients(store: store);

    // Do not send online presences when app is in background fetch mode.
    for (final client in clients) {
      client.backgroundSync = false;
      client.syncPresence = PresenceType.offline;
    }

    // In the background fetch mode we do not want to waste ressources with
    // starting the Flutter engine but process incoming push notifications.
    BackgroundPush.clientOnly(clients);
    // To start the flutter engine afterwards we add an custom observer.
    WidgetsBinding.instance.addObserver(AppStarter(clients, store));
    Logs().i(
      '${AppSettings.applicationName.value} started in background-fetch mode. No GUI will be created unless the app is no longer detached.',
    );
    // 后台保活模式本来就**不画界面**，别让看门狗误报成「启动失败」。
    _bootSettled = true;
    return;
  }

  final clients = await ClientManager.getClients(store: store);

  // Started in foreground mode.
  Logs().i(
    '${AppSettings.applicationName.value} started in foreground mode. Rendering GUI...',
  );
  await startGui(clients, store);
}

/// Fetch the pincode for the applock and start the flutter engine.
Future<void> startGui(List<Client> clients, SharedPreferences store) async {
  // Fetch the pin for the applock if existing for mobile applications.
  String? pin;
  var useBiometrics = false;
  if (PlatformInfos.supportsAppLock) {
    try {
      pin = await const FlutterSecureStorage().read(
        key: 'chat.fluffy.app_lock',
      );
      useBiometrics =
          (await const FlutterSecureStorage().read(
            key: 'chat.fluffy.use_biometrics',
          )) ==
          'true';
    } catch (e, s) {
      Logs().d('Unable to read PIN from Secure storage', e, s);
    }
  }

  if (PlatformInfos.isLinux || PlatformInfos.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Preload first client（数据库预加载只是「快了更好」，卡住不能拖死启动）。
  final firstClient = clients.firstOrNull;
  try {
    final roomsLoading = firstClient?.roomsLoading;
    if (roomsLoading != null) {
      await roomsLoading.timeout(const Duration(seconds: 3));
    }
    final accountDataLoading = firstClient?.accountDataLoading;
    if (accountDataLoading != null) {
      await accountDataLoading.timeout(const Duration(seconds: 3));
    }
  } catch (e, s) {
    Logs().w('预加载数据库超时或失败，直接进界面', e, s);
  }

  // 先把界面画出来：app_start 需要读取包信息和机型（都是平台通道），
  // 放在 runApp 之前会让弱网/异常直接把启动拖死。
  runApp(
    FluffyChatApp(
      clients: clients,
      appLockSettings: (pincode: pin, useBiometrics: useBiometrics),
      store: store,
    ),
  );
  _bootSettled = true;
  // 上次安装留下的 APK 在这里删：安装器在另一个进程里干活，
  // 装完立刻删会让「安装失败再点一次」没得点，所以放到下一次启动。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(AppUpdateService.cleanupUpdateDir());
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      logAppStart().catchError((Object error, StackTrace stack) {
        Logs().w('[diag] app_start 记录失败', error, stack);
      }),
    );
  });
}

/// Watches the lifecycle changes to start the application when it
/// is no longer detached.
class AppStarter with WidgetsBindingObserver {
  final List<Client> clients;
  final SharedPreferences store;
  bool guiStarted = false;

  AppStarter(this.clients, this.store);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (guiStarted) return;
    if (state == AppLifecycleState.detached) return;

    Logs().i(
      '${AppSettings.applicationName.value} switches from the detached background-fetch mode to ${state.name} mode. Rendering GUI...',
    );
    // Switching to foreground mode needs to reenable send online sync presence.
    for (final client in clients) {
      client.backgroundSync = true;
      client.syncPresence = PresenceType.online;
    }
    // 用户回到 App 就不再需要常驻通知撑着后台连接了，立刻收掉，
    // 免得状态栏（或通知中心的静默区）一直挂着「正在接收消息」。
    ForegroundServices.stopService('background_push');
    startGui(clients, store);
    // We must make sure that the GUI is only started once.
    guiStarted = true;
  }
}
