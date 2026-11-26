// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// 我们的 Synapse 有两个入口，指向同一台服务器、同一套账号：
///
/// - [lan] 家里的局域网（满速），证书是自签的，只对私有网段放行；
/// - [wan] 公网（Tailscale Funnel，正规证书），在外面用。
///
/// App 启动时探测一次，能连上局域网就用局域网，否则回落公网。
/// **只换 base_url，不动 server_name** —— 用户 ID 里的域名必须永远保持
/// [serverName]，否则会被当成另一台服务器、账号就对不上了。
class ServerEndpoints {
  const ServerEndpoints._();

  static const String lan = 'https://192.168.31.154:8444';
  static const String wan = 'https://qmypc.tail7337aa.ts.net';

  /// 用户 ID 的域名，永远不跟着 base_url 变
  static const String serverName = 'qmypc.tail7337aa.ts.net';

  /// 启动时探测决定的端点，App 没探测前先用公网（最保守）
  static String current = wan;

  static bool isLan = false;

  /// 是否已经探测过。没探测过时不要把 [current] 当成用户的服务器地址。
  static bool probed = false;

  /// 两个端点都连不上时仍然用公网地址进 App，另外标记一下好提示用户。
  static bool reachable = true;

  static Uri get uri => Uri.parse(current);

  /// 只处理我们自己的服务器，别的 Matrix 服务器一律不动
  static bool isOwnHost(String? host) =>
      host == '192.168.31.154' || host == serverName;

  /// 把指向我们自己服务器的地址换成当前选中的端点
  static Uri resolve(Uri uri) =>
      isOwnHost(uri.host) ? ServerEndpoints.uri : uri;

  /// 同上，给只接受「裸 host[:port]」的地方（注册页）用
  static String resolveAuthority(String authority) {
    if (!isOwnHost(authority.split(':').first)) return authority;
    final endpoint = uri;
    return endpoint.hasPort
        ? '${endpoint.host}:${endpoint.port}'
        : endpoint.host;
  }

  static void select(String url, {required bool isReachable}) {
    current = url;
    isLan = url == lan;
    probed = true;
    reachable = isReachable;
  }

  /// 把已登录客户端的 base_url 切到当前端点。
  ///
  /// `Client.homeserver` 是 MatrixApi 里 `baseUri` 的 getter/setter，改完之后的
  /// 所有请求（包括 mxc 媒体上传/下载）都会立刻走新地址，不用重建 Client。
  static void applyTo(Client client) {
    final homeserver = client.homeserver;
    if (homeserver == null || !isOwnHost(homeserver.host)) return;
    final target = uri;
    if (homeserver.host == target.host && homeserver.port == target.port) {
      return;
    }
    client.homeserver = target;
    Logs().i('[ServerEndpoints] ${homeserver.host} -> ${target.host}');
  }
}
