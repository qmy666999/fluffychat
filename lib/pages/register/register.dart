// SPDX-FileCopyrightText: 2026 Contributors to the FluffyChat register fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'register_view.dart';

/// Thrown when an account could not be created for a reason which is not
/// covered by a [MatrixException], for example because the homeserver does not
/// allow registrations at all.
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
/// creates the account directly through the Matrix client-server API
/// (`POST /_matrix/client/v3/register`) and connects the client with the
/// session which the homeserver returns, so a new user can start chatting
/// without leaving the app.
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

  /// A general error which is not bound to a single input field.
  String? error;

  bool loading = false;
  bool showPassword = false;

  /// Synapse only accepts these characters in a username localpart by default.
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9._=\-/]+$');

  static const int minPasswordLength = 8;

  static const String dummyAuthType = 'm.login.dummy';

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
  /// Reads the registration flows which the homeserver offers.
  ///
  /// Returns the `stages` of every flow. An open Synapse with
  /// `enable_registration: true` and no captcha answers
  /// `{"flows": [{"stages": ["m.login.dummy"]}]}`.
  Future<List<List<String>>> _registrationFlows(Client client) async {
    final response = await client.request(
      RequestType.GET,
      '/client/v3/register',
    );
    final flows = response['flows'];
    if (flows is! List) return const [];
    final result = <List<String>>[];
    for (final flow in flows.whereType<Map>()) {
      final stages = flow['stages'];
      if (stages is! List) continue;
      result.add(stages.whereType<String>().toList());
    }
    return result;
  }

  /// Creates the account and connects [client] with the new session.
  ///
  /// A registration which only requires `m.login.dummy` is usually accepted
  /// without a user interactive authentication round trip. Servers which still
  /// answer with a `401` and a `session` get one more try with that session.
  Future<void> _createAccount(
    Client client,
    String username,
    String password,
  ) async {
    var auth = AuthenticationData(type: dummyAuthType);
    for (var attempt = 0; ; attempt++) {
      try {
        await client.register(
          username: username,
          password: password,
          initialDeviceDisplayName: PlatformInfos.appDisplayName,
          auth: auth,
        );
        return;
      } on MatrixException catch (exception) {
        final session = exception.session;
        if (attempt > 1 || session == null) rethrow;
        auth = AuthenticationData(
          type: dummyAuthType,
          session: session,
        );
      }
    }
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
    try {
      final client = await _resolveClient();

      final flows = await _registrationFlows(client);
      if (flows.isEmpty) {
        throw RegisterException(l10n.registerRegistrationDisabled);
      }
      // Only flows which can be completed with just m.login.dummy are
      // supported. Anything else (captcha, terms, email verification) needs
      // interaction with the registration website of the homeserver.
      final dummyOnly = flows.any(
        (stages) => stages.length == 1 && stages.single == dummyAuthType,
      );
      if (!dummyOnly) {
        throw RegisterException(l10n.registerUnsupportedAuth);
      }

      await _createAccount(client, username, password);

      if (!mounted) return;
      context.go('/backup');
    } on MatrixException catch (exception) {
      if (!mounted) return;
      setState(() {
        error = _matrixExceptionMessage(exception, context);
        loading = false;
      });
    } on RegisterException catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.message;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  String _matrixExceptionMessage(
    MatrixException exception,
    BuildContext context,
  ) {
    final l10n = L10n.of(context);
    switch (exception.errcode) {
      case 'M_USER_IN_USE':
        return l10n.registerUsernameTaken;
      case 'M_INVALID_USERNAME':
        return l10n.registerUsernameInvalid;
      case 'M_WEAK_PASSWORD':
        return l10n.registerWeakPassword;
      case 'M_FORBIDDEN':
        if (exception.requireAdditionalAuthentication) {
          return l10n.registerUnsupportedAuth;
        }
        return l10n.registerRegistrationDisabled;
      case 'M_LIMIT_EXCEEDED':
        return l10n.registerRateLimited;
      default:
        return exception.errorMessage;
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
