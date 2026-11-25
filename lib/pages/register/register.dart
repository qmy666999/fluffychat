// SPDX-FileCopyrightText: 2026 Contributors to the FluffyChat register fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'register_view.dart';

/// Thrown when an account could not be created for a reason which is not
/// covered by an HTTP/Matrix error, for example when the homeserver can not be
/// reached at all.
class RegisterException implements Exception {
  final String message;

  const RegisterException(this.message);

  @override
  String toString() => message;
}

/// Account registration page.
///
/// FluffyChat upstream has no in app registration: its sign up flow only
/// forwards to the registration website of the selected homeserver. This page
/// creates the account through the Matrix client-server API
/// (`POST /_matrix/client/v3/register`) and logs the new account in afterwards
/// so that a fresh user can start chatting without leaving the app.
class Register extends StatefulWidget {
  /// A client which is already connected to the homeserver where the account
  /// should be created on.
  ///
  /// When this is null (for example when the page is opened by a deep link)
  /// the user gets a homeserver input on the page itself.
  final Client? client;

  const Register({this.client, super.key});

  @override
  RegisterController createState() => RegisterController();
}

class RegisterController extends State<Register> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController passwordConfirmController =
      TextEditingController();
  final TextEditingController serverController = TextEditingController();

  String? usernameError;
  String? passwordError;

  /// A general error which is not bound to a single input field. It always
  /// carries the raw status code and response body, so a failing request can be
  /// diagnosed without a debugger.
  String? error;

  bool loading = false;
  bool showPassword = false;

  /// Synapse only accepts these characters in a username localpart by default.
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9._=\-/]+$');

  static const int minPasswordLength = 8;

  /// The only registration stage this page can complete by itself. Servers
  /// which require anything else have to be handled on their website.
  static const String dummyAuthType = 'm.login.dummy';

  static const Duration requestTimeout = Duration(seconds: 30);

  Client? _client;

  Client? get client => widget.client ?? _client;

  String? get homeserverName {
    final homeserver = client?.homeserver;
    if (homeserver == null) return null;
    return homeserver.toString().replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/+$'), '');
  }

  @override
  void initState() {
    super.initState();
    serverController.text =
        homeserverName ?? AppSettings.defaultHomeserver.value;
  }

  void toggleShowPassword() => setState(() => showPassword = !showPassword);

  /// Strips an optional `@` and `:domain` so that both `alice` and
  /// `@alice:example.org` are accepted in the username field.
  static String usernameLocalpart(String input) {
    var username = input.trim();
    if (username.startsWith('@')) username = username.substring(1);
    final colon = username.indexOf(':');
    if (colon != -1) username = username.substring(0, colon);
    return username;
  }

  /// Returns a client which is connected to the selected homeserver.
  ///
  /// When the page was opened without a client, the login client is created
  /// here and connected to the homeserver which the user typed in.
  Future<Client> _resolveClient() async {
    final existing = client;
    if (existing?.homeserver != null) return existing!;

    var input = serverController.text.trim();
    if (input.isEmpty) throw const RegisterException('No homeserver given');
    if (!input.contains('://')) input = 'https://$input';
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty) {
      throw const RegisterException('Invalid homeserver');
    }

    final loginClient =
        existing ?? await Matrix.of(context).getLoginClient();
    _client = loginClient;
    await loginClient.checkHomeserver(uri);
    if (loginClient.homeserver == null) {
      throw const RegisterException('Unable to reach the homeserver');
    }
    return loginClient;
  }

  /// Builds the registration endpoint URL without relying on any SDK path
  /// joining, so the request goes to exactly `/_matrix/client/v3/register`.
  Uri registrationUrl(Client client) {
    final base = client.homeserver.toString().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return Uri.parse('$base/_matrix/client/v3/register');
  }

  Future<void> register() async {
    if (loading) return;
    final l10n = L10n.of(context);
    final username = usernameLocalpart(usernameController.text);
    final password = passwordController.text;

    final usernameError = username.isEmpty
        ? l10n.pleaseEnterYourUsername
        : !usernamePattern.hasMatch(username)
        ? l10n.registerUsernameInvalid
        : null;

    final passwordError = password.isEmpty
        ? l10n.pleaseEnterYourPassword
        : password.length < minPasswordLength
        ? l10n.registerPasswordTooShort(minPasswordLength)
        : password != passwordConfirmController.text
        ? l10n.registerPasswordsDoNotMatch
        : null;

    setState(() {
      this.usernameError = usernameError;
      this.passwordError = passwordError;
      error = null;
    });

    if (usernameError != null || passwordError != null) return;

    setState(() => loading = true);

    Client? client;
    try {
      client = await _resolveClient();
    } on RegisterException catch (exception) {
      if (!mounted) return;
      return setState(() {
        error = exception.message;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      return setState(() {
        error = 'checkHomeserver failed: $exception';
        loading = false;
      });
    }

    final url = registrationUrl(client);
    debugPrint('REGISTER URL = $url');

    http.Response response;
    try {
      response = await http
          .post(
            url,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'username': username,
              'password': password,
              'auth': <String, Object?>{'type': dummyAuthType},
              'initial_device_display_name': PlatformInfos.appDisplayName,
              // Let the login below create the device so the account does not
              // end up with an orphaned session, and so no access token ends up
              // in the logs.
              'inhibit_login': true,
            }),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      if (!mounted) return;
      return setState(() {
        error = 'REGISTER timeout after ${requestTimeout.inSeconds}s\n$url';
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      return setState(() {
        error = 'REGISTER request failed\n$url\n$exception';
        loading = false;
      });
    }

    debugPrint('REGISTER RESP = ${response.statusCode} ${response.body}');

    if (response.statusCode != 200) {
      if (!mounted) return;
      final l10n = L10n.of(context);
      final hint = _hintFor(response, l10n);
      return setState(() {
        error = hint == null
            ? '${response.statusCode}: ${response.body}'
            : '$hint\n\n${response.statusCode}: ${response.body}';
        loading = false;
      });
    }

    String? userId;
    try {
      final json = jsonDecode(response.body);
      if (json is Map) userId = json['user_id'] as String?;
    } catch (_) {
      // The account exists at this point, the login below will report problems.
    }

    try {
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: userId ?? username),
        password: password,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
    } catch (exception) {
      if (!mounted) return;
      return setState(() {
        error =
            '账号已注册成功（${userId ?? username}），但自动登录失败：\n'
            '${exception is MatrixException ? exception.errorMessage : exception}';
        loading = false;
      });
    }

    if (!mounted) return;
    context.go('/backup');
  }

  /// A short explanation for the most common registration failures. The raw
  /// status code and body are always appended by the caller.
  String? _hintFor(http.Response response, L10n l10n) {
    String? errcode;
    try {
      final json = jsonDecode(response.body);
      if (json is Map) errcode = json['errcode'] as String?;
    } catch (_) {
      // not json, keep errcode null
    }

    if (response.statusCode == 401) return l10n.registerUnsupportedAuth;
    if (response.statusCode == 404) {
      return '服务器没有这个接口（404），请确认服务器地址和版本';
    }

    switch (errcode) {
      case 'M_USER_IN_USE':
        return l10n.registerUsernameTaken;
      case 'M_INVALID_USERNAME':
        return l10n.registerUsernameInvalid;
      case 'M_WEAK_PASSWORD':
        return l10n.registerWeakPassword;
      case 'M_FORBIDDEN':
      case 'M_GUEST_ACCESS_FORBIDDEN':
        return l10n.registerRegistrationDisabled;
      case 'M_LIMIT_EXCEEDED':
        return l10n.registerRateLimited;
      case 'M_UNRECOGNIZED':
        return '服务器不认识这个请求（M_UNRECOGNIZED），请确认服务器地址';
      default:
        return null;
    }
  }

  /// Goes back to the login page of the same homeserver.
  void backToLogin() {
    final pathSegments = List.of(
      GoRouter.of(context).routeInformationProvider.value.uri.pathSegments,
    );
    if (pathSegments.isNotEmpty) pathSegments.removeLast();
    pathSegments.add('login');
    if (!mounted) return;
    context.go('/${pathSegments.join('/')}', extra: client);
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    passwordConfirmController.dispose();
    serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RegisterView(this);
}
