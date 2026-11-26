// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:fluffychat/config/server_endpoints.dart';
import 'package:matrix/matrix.dart';

const _probeTimeout = Duration(seconds: 2);

/// 每个端点最多等 2 秒，两个端点**并行**探测，所以 App 启动最多慢 2 秒。
Future<String> pickFastestServer() async {
  final results = await Future.wait([
    _ping(ServerEndpoints.lan),
    _ping(ServerEndpoints.wan),
  ]);
  final lanOk = results[0];
  final wanOk = results[1];

  final picked = lanOk
      ? ServerEndpoints.lan
      : wanOk
      ? ServerEndpoints.wan
      : ServerEndpoints.wan;
  // 两个都不通时仍然用公网地址进 App，由上层提示连不上，不能卡死在这里。
  ServerEndpoints.select(picked, isReachable: lanOk || wanOk);
  Logs().i(
    '[ServerEndpoints] picked $picked '
    '(lan=$lanOk wan=$wanOk reachable=${lanOk || wanOk})',
  );
  return picked;
}

Future<bool> _ping(String baseUrl) async {
  final client = HttpClient()..connectionTimeout = _probeTimeout;
  try {
    final request = await client
        .getUrl(Uri.parse('$baseUrl/_matrix/client/versions'))
        .timeout(_probeTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_probeTimeout);
    await response.drain<void>().timeout(_probeTimeout);
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// 只对我们的私有网段放行自签证书。
///
/// 绝对不能用 `(_, _, _) => true`：那等于对所有网站关掉证书校验。
bool _isPrivateHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
  if (host.startsWith('172.')) {
    final second = int.tryParse(host.split('.').elementAtOrNull(1) ?? '');
    return second != null && second >= 16 && second <= 31;
  }
  return false;
}

class _PrivateCertHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = ((cert, host, port) => _isPrivateHost(host));
}

void installPrivateCertOverride() {
  // 必须在第一次创建 HttpClient 之前装好；装上之后 IOClient、Image.network
  // 等所有走 dart:io 的请求都会经过这里。
  HttpOverrides.global = _PrivateCertHttpOverrides();
}
