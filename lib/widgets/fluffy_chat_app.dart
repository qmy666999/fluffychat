// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:developer';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/active_call_banner.dart';
import 'package:fluffychat/utils/diagnostics/diag_route_observer.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/layouts/call_overlay.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class FluffyChatApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final ({String? pincode, bool useBiometrics}) appLockSettings;
  final SharedPreferences store;
  final Locale? locale;

  const FluffyChatApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    required this.appLockSettings,
    this.locale,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: true,
    // 记录路由栈：出「返回到底关掉了谁」这类问题时，日志里能直接看到栈。
    observers: [DiagRouteObserver()],
    redirect: (context, state) {
      // Workaround for content sharings passed to go router:
      if ({
        'content',
        'sharemedia-im.fluffychat.app',
      }.contains(state.uri.scheme)) {
        Logs().d('Ignore content sharing handling in go router', state.uri);
        return '/';
      }

      if (state.uri.scheme == 'matrix') {
        debugger();
        final type = state.uri.pathSegments.first;
        final id = state.uri.pathSegments[1];
        switch (type) {
          case 'roomid':
            final roomId = '!$id';
            return '/rooms/$roomId';
          case 'r':
            final alias = '#$id';
            return '/rooms/newprivatechat#$alias';
          case 'u':
            final userId = '@$id';
            return '/rooms/newprivatechat#$userId';
        }
      }

      // Pass deep links to app:
      if (state.uri.toString().startsWith(AppConfig.deepLinkPrefix)) {
        return '/rooms/newprivatechat#${state.uri}';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder: (context, settings) => MaterialApp.router(
        title: AppSettings.applicationName.value,
        themeMode: settings.themeMode,
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: FluffyThemes.buildTheme(
          context,
          Brightness.light,
          seed: settings.primaryColor,
          scheme: settings.dynamicSchemeFor(Brightness.light),
          variant: settings.variant.variant,
        ),
        darkTheme: FluffyThemes.buildTheme(
          context,
          Brightness.dark,
          seed: settings.primaryColor,
          scheme: settings.dynamicSchemeFor(Brightness.dark),
          variant: settings.variant.variant,
        ),
        scrollBehavior: CustomScrollBehavior(),
        localizationsDelegates: [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
          ...GlobalCupertinoLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
        // 注意：`MaterialApp.router` 的 builder 在 Router **外面**（WidgetsApp
        // 是先用 builder 包住整个 routing，再挂到 MaterialApp 上的），这里
        // 一旦放 `BackButtonListener` 之类要找 `Router` 祖先的组件，release
        // 包里就是一句 `Null check operator used on a null value`，整个界面
        // 变成错误页。所以返回手势的日志改由 [DiagRouteObserver.didPop] 记。
        builder: (context, child) => AppLockWidget(
          pincode: appLockSettings.pincode,
          useBiometrics: appLockSettings.useBiometrics,
          isLoggedIn: clients.any((client) => client.isLogged()),
          // 全局通话横幅：挂在 Navigator 外面，所以切到通讯录、发现、我
          // 这些页面时横幅也一直在。放在 AppLockWidget 里面，锁屏时它会被
          // 锁屏界面盖住，不会泄露通话状态。
          child: GlobalCallBannerHost(
            // Need a navigator above the Matrix widget for
            // displaying dialogs
            child: Matrix(
              clients: clients,
              store: store,
              child: CallOverlay(
                child: testWidget ?? child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
