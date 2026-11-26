// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// 端点探测 + 局域网自签证书放行。
//
// 探测要直接用 `dart:io` 的 `HttpClient`（最轻、不受 App 内拦截器影响），
// 而 `dart:io` 在 web 上不存在，所以实现分两份做条件导入：
// 有 IO 用 server_probe_io.dart，否则用 server_probe_stub.dart。
export 'server_probe_stub.dart'
    if (dart.library.io) 'server_probe_io.dart'
    show installPrivateCertOverride, pickFastestServer;
