// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// 服务器要求了本客户端无法自动完成的 UIA 阶段（例如 recaptcha、email）。
///
/// 注册是两段式的：第一次 POST /register 只带用户名密码，服务器回 401 + flows +
/// session，客户端必须再 POST 一次并带上 `auth: {type, session}`。这里能自动完成的
/// 阶段是 m.login.dummy 和 m.login.terms，其余阶段要把 stages 交给 UI 去提示用户。
class RegistrationUiaUnsupported implements Exception {
  final List<String> stages;

  const RegistrationUiaUnsupported(this.stages);

  @override
  String toString() => 'RegistrationUiaUnsupported(${stages.join(', ')})';
}

const _supportedStages = {'m.login.dummy', 'm.login.terms'};

/// 在 [homeserver] 上注册一个全新账号，成功后 client 已处于登录态。
///
/// 抛出的异常：
/// - [RegistrationUiaUnsupported] 服务器要求本客户端做不了的 UIA 阶段
/// - [MatrixException] 服务器直接拒绝（M_FORBIDDEN 表示不允许注册，
///   M_USER_IN_USE 表示用户名被占用，M_INVALID_USERNAME 表示用户名不合法……）
Future<void> registerNewAccount({
  required Client client,
  required Uri homeserver,
  required String username,
  required String password,
}) async {
  // 必须先把 client 指向目标 homeserver，register 的 baseUri 由它决定。
  await client.checkHomeserver(homeserver);

  final initialDeviceDisplayName = PlatformInfos.appDisplayName;

  Future<RegisterResponse> attempt(AuthenticationData? auth) => client.register(
    username: username,
    password: password,
    initialDeviceDisplayName: initialDeviceDisplayName,
    auth: auth,
  );

  try {
    final response = await attempt(null);
    _logSuccess(response, 'password');
    return;
  } on MatrixException catch (e) {
    // 401 = 需要额外认证（UIA），其它错误直接交给调用方显示。
    if (!e.requireAdditionalAuthentication) rethrow;

    final stage = _pickStage(e.authenticationFlows);
    if (stage == null) {
      throw RegistrationUiaUnsupported(_allStages(e.authenticationFlows));
    }

    Logs().i('[register] UIA stage: $stage');
    final response = await attempt(
      AuthenticationData(type: stage, session: e.session),
    );
    _logSuccess(response, 'uia($stage)');
  }
}

void _logSuccess(RegisterResponse response, String how) {
  debugPrint(
    '[register] success ($how) '
    'user_id=${response.userId} device_id=${response.deviceId}',
  );
}

/// 优先选只包含单个、且我们能自动完成的阶段的 flow。
///
/// Synapse 打开注册时通常直接给 `[m.login.dummy]`；开了条款确认会给
/// `[m.login.terms]`。多阶段组合（dummy→terms 之类）需要循环提交，
/// MVP 先不猜，交给 UI 明确告知用户。
String? _pickStage(List<AuthenticationFlow>? flows) {
  if (flows == null || flows.isEmpty) return null;
  for (final flow in flows) {
    if (flow.stages.length == 1 && _supportedStages.contains(flow.stages.single)) {
      return flow.stages.single;
    }
  }
  return null;
}

List<String> _allStages(List<AuthenticationFlow>? flows) {
  if (flows == null) return const [];
  return flows.expand((flow) => flow.stages).toSet().toList();
}
