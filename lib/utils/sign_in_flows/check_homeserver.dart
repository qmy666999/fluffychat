// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/server_endpoints.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/oidc_login.dart';
import 'package:fluffychat/utils/sign_in_flows/sso_login.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

Future<void> connectToHomeserverFlow(
  PublicHomeserverData homeserverData,
  BuildContext context,
  void Function(AsyncSnapshot<bool>) setState,
  bool signUp,
) async {
  setState(AsyncSnapshot.waiting());
  try {
    final homeserverInput = homeserverData.name!;
    var homeserver = Uri.parse(homeserverInput);
    if (homeserver.scheme.isEmpty) {
      homeserver = Uri.https(homeserverInput, '');
    }
    // 我们自己服务器的域名（不管是预设还是手输）都换成启动时探测到的端点：
    // 在家走局域网满速，在外面走公网。
    homeserver = ServerEndpoints.resolve(homeserver);
    final l10n = L10n.of(context);
    final client = await Matrix.of(context).getLoginClient();
    final (_, _, loginFlows, authMetadata) = await client.checkHomeserver(
      homeserver,
      fetchAuthMetadata: true,
      // 我们自己的服务器的 well-known 永远指向公网，在家会白白绕出去，
      // 所以走自己的端点时跳过它。
      checkWellKnown: !ServerEndpoints.isOwnHost(homeserver.host),
    );

    final regLink = homeserverData.regLink;
    final supportsSso = loginFlows.any((flow) => flow.type == 'm.login.sso');

    if ((kIsWeb || PlatformInfos.isLinux) &&
        (supportsSso || authMetadata != null || (signUp && regLink != null))) {
      if (!context.mounted) return;
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: l10n.appWantsToUseForLogin(homeserverInput),
        message: l10n.appWantsToUseForLoginDescription,
        okLabel: l10n.continueText,
      );
      if (consent != OkCancelResult.ok) return;
      if (!context.mounted) return;
    }
    if (!context.mounted) return;

    if (authMetadata != null && AppSettings.enableMatrixNativeOIDC.value) {
      await oidcLoginFlow(client, context, signUp);
    } else if (supportsSso) {
      await ssoLoginFlow(client, context, signUp, loginFlows);
    } else {
      if (signUp && regLink != null) {
        await launchUrlString(regLink);
      }
      if (!context.mounted) return;
      // 登录页路径要按当前入口算，入口层级并不一样：
      //   /home                  → /home/login
      //   /home/sign_in          → /home/login
      //   /rooms/settings/addaccount → /rooms/settings/addaccount/login
      // 以前是「去掉最后一段再拼 login」，从「添加账户」进来就会拼成
      // /rooms/settings/login —— 路由表里没有，直接 Page Not Found。
      final pathSegments = GoRouterState.of(
        context,
      ).uri.path.split('/').where((segment) => segment.isNotEmpty).toList();
      if (pathSegments.isNotEmpty &&
          (pathSegments.last == 'sign_in' || pathSegments.last == 'sign_up')) {
        pathSegments.removeLast();
      }
      if (pathSegments.isEmpty) pathSegments.add('home');
      pathSegments.add('login');
      context.push('/${pathSegments.join('/')}', extra: client);
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
      return;
    }

    await AppSettings.defaultHomeserver.setItem(homeserverInput);

    if (context.mounted) {
      setState(AsyncSnapshot.withData(ConnectionState.done, true));
      context.go('/backup');
    }
  } catch (e, s) {
    Logs().w('Unable to login', e, s);
    setState(AsyncSnapshot.withError(ConnectionState.done, e, s));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e.toLocalizedString(context, ExceptionContext.checkHomeserver),
        ),
      ),
    );
  }
}
