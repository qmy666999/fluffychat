// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/server_endpoints.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/sign_in_flows/register_flow.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'register_view.dart';

/// 应用内注册。
///
/// 上游 FluffyChat 本身没有注册页（「创建新账户」只是选服务器，最后落到登录页），
/// 这里补上真正的 POST /_matrix/client/v3/register + UIA 两段式。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  RegisterPageController createState() => RegisterPageController();
}

class RegisterPageController extends State<RegisterPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  late String homeserver;
  bool loading = false;
  bool showPassword = false;

  String? usernameError;
  String? passwordError;
  String? confirmPasswordError;

  /// 提交失败的整体原因，带 statusCode + 服务端原文，方便排查。
  String? formError;

  @override
  void initState() {
    super.initState();
    homeserver = _defaultHomeserver();
  }

  String _defaultHomeserver() {
    final preset = AppSettings.presetHomeserver.value.trim();
    final server = preset.isNotEmpty
        ? preset
        : AppSettings.defaultHomeserver.value.trim();
    // 预设的是服务器域名，真正连哪个入口由启动时的探测决定（局域网优先）。
    return ServerEndpoints.resolveAuthority(server);
  }

  void toggleShowPassword() =>
      setState(() => showPassword = !loading && !showPassword);

  /// 允许注册时切到别的服务器（03 要求：预设服务器之外还能切走）。
  Future<void> changeHomeserver() async {
    if (loading) return;
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).serverAddress,
      hintText: 'matrix.org',
      initialText: homeserver,
      validator: (value) {
        if (value.trim().isEmpty) {
          return L10n.of(context).pleaseEnterYourHomeserver;
        }
        return null;
      },
    );
    if (input == null) return;
    setState(() {
      homeserver = _normalizeHomeserver(input);
      formError = null;
    });
  }

  /// 用户可能粘进 https:// 前缀或末尾斜杠，统一成裸域名。
  String _normalizeHomeserver(String input) {
    var host = input.trim();
    if (host.startsWith('https://')) host = host.substring(8);
    if (host.startsWith('http://')) host = host.substring(7);
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    // 只换入口地址；server_name 由服务器决定，不受影响。
    return ServerEndpoints.resolveAuthority(host);
  }

  Future<void> register() async {
    final l10n = L10n.of(context);
    final username = usernameController.text.trim().toLowerCase();
    final password = passwordController.text;
    final confirm = confirmPasswordController.text;

    setState(() {
      usernameError = username.isEmpty ? l10n.pleaseEnterYourUsername : null;
      passwordError = password.length < 8
          ? l10n.registerPasswordTooShort
          : null;
      confirmPasswordError = password != confirm
          ? l10n.passwordsDoNotMatch
          : null;
      formError = null;
    });
    if (usernameError != null ||
        passwordError != null ||
        confirmPasswordError != null) {
      return;
    }

    setState(() => loading = true);
    try {
      final client = await Matrix.of(context).getLoginClient();
      await registerNewAccount(
        client: client,
        homeserver: Uri.https(homeserver, ''),
        username: username,
        password: password,
      );
      if (!mounted) return;
      // client 登录态监听（Matrix.getLoginClient）也会跳 /backup，这里保持同样的落点。
      context.go('/backup');
    } on RegistrationUiaUnsupported catch (e) {
      if (!mounted) return;
      setState(() {
        // flows 为空说明服务器其实没开放注册（或配置坏了），别给用户看空白提示。
        formError = e.stages.isEmpty
            ? l10n.registerServerDoesNotSupport
            : l10n.registerUiaUnsupported(e.stages.join(', '));
      });
    } on MatrixException catch (e) {
      if (!mounted) return;
      setState(() {
        formError = e.error == MatrixError.M_FORBIDDEN
            ? l10n.registerServerDoesNotSupport
            : l10n.registerFailed(_describe(e));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => formError = l10n.registerFailed(e.toString()));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// "403 M_FORBIDDEN: ..." 这种，前端能看、贴给管理员也能看懂。
  String _describe(MatrixException e) {
    final status = e.response?.statusCode;
    final raw = e.response?.body;
    final message = e.errorMessage;
    final head = [if (status != null) status.toString(), e.errcode].join(' ');
    final body = raw == null || raw.isEmpty
        ? ''
        : ' ${raw.length > 300 ? '${raw.substring(0, 300)}…' : raw}';
    return '$head: $message$body';
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RegisterView(this);
}
