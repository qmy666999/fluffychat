// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' show Logs;

/// 手动出口：把本地操作日志写到系统的 Download 目录（万一上报通道坏了，
/// 还能让用户点一下导出发过来）。
class DiagExporter {
  DiagExporter._();

  static const MethodChannel _channel = MethodChannel('chat.fluffychatx/logs');

  /// 导出的文件名，例如 `FluffyChatX-log-20261128-120000.txt`。
  static String fileName([DateTime? now]) {
    final time = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'FluffyChatX-log-'
        '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}.txt';
  }

  /// 返回是否成功。失败只记日志，不抛异常。
  static Future<bool> exportToDownloads() async {
    if (!PlatformInfos.isAndroid) return false;
    try {
      final content = await ActionLogger.I.exportText();
      if (content.isEmpty) return false;
      final saved = await _channel.invokeMethod<bool>('saveToDownloads', {
        'name': fileName(),
        'content': content,
      });
      return saved ?? false;
    } catch (e, s) {
      Logs().w('[diag] 导出日志失败', e, s);
      return false;
    }
  }
}
