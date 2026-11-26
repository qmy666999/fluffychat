// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/server_endpoints.dart';

/// web 上没有 dart:io，也没有局域网直连这回事，直接用公网。
Future<String> pickFastestServer() async {
  ServerEndpoints.select(ServerEndpoints.wan, isReachable: true);
  return ServerEndpoints.wan;
}

/// web 上不需要（也没法）改证书校验。
void installPrivateCertOverride() {}
