// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fluffychat/config/server_endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新过程中可能出现的错误。
enum AppUpdateError {
  /// 服务器返回的更新信息不合法（例如 APK 地址指向了外部域名）
  rejected,

  /// 下载失败
  network,

  /// sha256 校验失败
  checksum,

  /// 调不起系统安装器
  install,
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.error, [this.detail]);

  final AppUpdateError error;
  final String? detail;

  @override
  String toString() => 'AppUpdateException($error, $detail)';
}

/// 服务器上 latest.json 的内容。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUri,
    required this.sha256,
    required this.size,
    required this.changelog,
    required this.force,
    required this.minSupportedVersionCode,
  });

  final int versionCode;
  final String versionName;
  final Uri apkUri;
  final String sha256;
  final int size;
  final String changelog;

  /// 服务器要求强制更新，或者当前版本低于最低支持版本
  final bool force;
  final int minSupportedVersionCode;

  /// 解析 [json]，并把相对路径的 apk_url 解析成当前服务器上的绝对地址。
  ///
  /// 只接受相对路径或者与本服务器同源的绝对地址，避免被指向第三方域名。
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json, String baseUrl) {
    final rawUrl = json['apk_url'];
    if (rawUrl is! String || rawUrl.isEmpty) {
      throw const AppUpdateException(AppUpdateError.rejected, 'apk_url');
    }
    final apkUri = resolveApkUri(rawUrl, baseUrl);
    final versionCode = json['version_code'];
    if (versionCode is! int) {
      throw const AppUpdateException(AppUpdateError.rejected, 'version_code');
    }
    return AppUpdateInfo(
      versionCode: versionCode,
      versionName: (json['version_name'] as String?) ?? '$versionCode',
      apkUri: apkUri,
      sha256: (json['sha256'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      changelog: (json['changelog'] as String?) ?? '',
      force: json['force'] == true,
      minSupportedVersionCode:
          (json['min_supported_version_code'] as num?)?.toInt() ?? 0,
    );
  }

  /// 把 latest.json 里的 apk_url 解析成绝对地址，并校验同源。
  @visibleForTesting
  static Uri resolveApkUri(String raw, String baseUrl) {
    final base = Uri.parse(baseUrl);
    final parsed = Uri.parse(raw);
    final uri = parsed.hasScheme ? parsed : base.resolveUri(parsed);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw const AppUpdateException(AppUpdateError.rejected, 'scheme');
    }
    if (uri.host.toLowerCase() != base.host.toLowerCase()) {
      throw const AppUpdateException(AppUpdateError.rejected, 'host');
    }
    if (uri.port != base.port) {
      throw const AppUpdateException(AppUpdateError.rejected, 'port');
    }
    return uri;
  }
}

/// 应用内更新：检查 latest.json、下载 APK、校验 sha256、调起系统安装器。
///
/// 更新包始终放在我们自己的服务器上（`<base_url>/updates/`），所以局域网和
/// 公网两个入口都能下，跟随 [ServerEndpoints] 自动切换。
class AppUpdateService {
  static const updatePath = '/updates/latest.json';

  /// 上次自动弹窗提示的日期（yyyy-MM-dd），一天最多提示一次。
  static const promptedKey = 'app_update_prompted_on';

  static Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  /// 当前安装包的 versionCode。
  static Future<int> currentVersionCode() async {
    final info = await packageInfo();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// 当前安装包的版本号，例如 `1.12.0 (35)`。
  static Future<String> currentVersionLabel() async {
    final info = await packageInfo();
    return '${info.version} (${info.buildNumber})';
  }

  /// 向当前服务器上的 `latest.json` 请求更新信息。
  ///
  /// 返回 null 表示已经是最新版；网络错误或数据不合法会抛 [AppUpdateException]。
  static Future<AppUpdateInfo?> checkForUpdate() async {
    final base = ServerEndpoints.current;
    final uri = Uri.parse('$base$updatePath');
    final client = http.Client();
    try {
      final response = await client
          .get(uri, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw AppUpdateException(
          AppUpdateError.network,
          'HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const AppUpdateException(AppUpdateError.rejected, 'json');
      }
      final info = AppUpdateInfo.fromJson(decoded, base);
      final current = await currentVersionCode();
      if (info.versionCode <= current) return null;
      if (info.minSupportedVersionCode > current && !info.force) {
        return AppUpdateInfo(
          versionCode: info.versionCode,
          versionName: info.versionName,
          apkUri: info.apkUri,
          sha256: info.sha256,
          size: info.size,
          changelog: info.changelog,
          force: true,
          minSupportedVersionCode: info.minSupportedVersionCode,
        );
      }
      return info;
    } on AppUpdateException {
      rethrow;
    } on Exception catch (e, s) {
      Logs().w('[Update] 检查更新失败', e, s);
      throw AppUpdateException(AppUpdateError.network, e.toString());
    } finally {
      client.close();
    }
  }

  /// 是否应该自动弹窗提示（一天一次，强制更新不受限制）。
  static Future<bool> shouldPromptAutomatically(bool force) async {
    if (force) return true;
    final store = await SharedPreferences.getInstance();
    final today = _dayKey(DateTime.now());
    return store.getString(promptedKey) != today;
  }

  /// 记录今天已经提示过。
  static Future<void> markPrompted() async {
    final store = await SharedPreferences.getInstance();
    await store.setString(promptedKey, _dayKey(DateTime.now()));
  }

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 下载并调起安装器。[onProgress] 的取值是 0~1。
  static Future<void> downloadAndInstall(
    AppUpdateInfo info, {
    ValueChanged<double>? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/FluffyChatX-${info.versionName}.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', info.apkUri);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw AppUpdateException(
          AppUpdateError.network,
          'HTTP ${response.statusCode}',
        );
      }
      final total = response.contentLength ?? info.size;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }
      if (received == 0) {
        throw const AppUpdateException(AppUpdateError.network, 'empty body');
      }
    } on AppUpdateException {
      rethrow;
    } on Exception catch (e, s) {
      Logs().w('[Update] 下载安装包失败', e, s);
      if (await file.exists()) {
        await file.delete();
      }
      throw AppUpdateException(AppUpdateError.network, e.toString());
    } finally {
      client.close();
    }

    if (info.sha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toUpperCase() != info.sha256.toUpperCase()) {
        await file.delete();
        throw const AppUpdateException(AppUpdateError.checksum);
      }
    }
    onProgress?.call(1);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      Logs().w('[Update] 无法调起安装器: ${result.type} ${result.message}');
      throw AppUpdateException(AppUpdateError.install, result.message);
    }
  }
}
