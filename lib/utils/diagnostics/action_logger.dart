// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' show Logs;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 操作日志。
///
/// 一行一条 JSON（JSON Lines），只记「能定位 bug 的骨架事件」，**绝不记消息
/// 正文、图片内容、密码、token**。日志先写本地文件（异步批量，避免卡 UI），
/// 再由 [DiagService] 定期上报到自己的诊断房间。
class ActionLogger {
  ActionLogger._();

  static final ActionLogger I = ActionLogger._();

  /// 攒够多少条就写一次盘。
  static const int flushThreshold = 20;

  /// 文件超过这个大小就砍掉前半部分，只保留最近的一半。
  static const int maxFileBytes = 2 * 1024 * 1024;

  static const String _seqKey = 'chat.fluffy.diag_seq';
  static const String _cursorKey = 'chat.fluffy.diag_cursor';

  SharedPreferences? _store;
  File? _file;
  final List<String> _buf = [];
  int _seq = 0;
  int _cursor = 0;
  bool _initialized = false;
  Timer? _flushTimer;

  /// 写盘串行化：并发 flush 时不会把行序写乱。
  Future<void> _queue = Future<void>.value();

  bool get isInitialized => _initialized;

  File? get file => _file;

  int get sequence => _seq;

  /// 已经上报到哪一条（本地游标），重启后从这里继续。
  int get cursor => _cursor;

  Future<void> init(SharedPreferences store) async {
    if (_initialized) return;
    _store = store;
    _seq = store.getInt(_seqKey) ?? 0;
    _cursor = store.getInt(_cursorKey) ?? 0;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/actions.log');
    } catch (e, s) {
      Logs().w('[diag] 无法获取日志目录', e, s);
    }
    _initialized = true;
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(flush()),
    );
  }

  /// 记一条事件。不会阻塞调用方。
  void log(
    String ev, {
    Map<String, Object?> extra = const {},
    String? route,
    List<String>? stack,
  }) {
    if (!_initialized) return;
    final data = <String, Object?>{
      't': DateTime.now().toIso8601String(),
      'seq': ++_seq,
      'ev': ev,
      'extra': extra,
    };
    if (route != null) data['route'] = route;
    if (stack != null) data['stack'] = stack;
    final line = jsonEncode(data);
    _buf.add(line);
    if (_buf.length >= flushThreshold) unawaited(flush());
  }

  /// 把缓冲区刷到磁盘。多次调用会排队执行。
  Future<void> flush() {
    return _queue = _queue.then((_) async {
      final file = _file;
      if (file == null) return;
      if (_buf.isEmpty) {
        await _store?.setInt(_seqKey, _seq);
        return;
      }
      final count = _buf.length;
      final data = '${_buf.take(count).join('\n')}\n';
      _buf.removeRange(0, count);
      try {
        await file.writeAsString(data, mode: FileMode.append, flush: true);
        await _rotate(file);
      } catch (e, s) {
        Logs().w('[diag] 写日志失败', e, s);
      }
      await _store?.setInt(_seqKey, _seq);
    });
  }

  Future<void> _rotate(File file) async {
    try {
      if (await file.length() < maxFileBytes) return;
      final lines = await file.readAsLines();
      final keep = lines.sublist(lines.length ~/ 2);
      await file.writeAsString('${keep.join('\n')}\n', flush: true);
    } catch (e, s) {
      Logs().w('[diag] 日志滚动失败', e, s);
    }
  }

  /// 读出「还没上报」的日志（按 seq 游标），最多 [limit] 条，返回最旧的。
  Future<List<Map<String, Object?>>> readPending({int limit = 300}) async {
    await flush();
    final entries = await _readAll();
    final pending = <Map<String, Object?>>[];
    for (final entry in entries) {
      final seq = (entry['seq'] as num?)?.toInt() ?? 0;
      if (seq > _cursor) pending.add(entry);
      if (pending.length >= limit) break;
    }
    return pending;
  }

  Future<List<Map<String, Object?>>> _readAll() async {
    final file = _file;
    if (file == null) return const [];
    try {
      if (!await file.exists()) return const [];
      final text = await file.readAsString();
      final entries = <Map<String, Object?>>[];
      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line);
          if (json is Map<String, Object?>) entries.add(json);
        } catch (_) {
          // 半行（写到一半被杀）直接跳过。
        }
      }
      return entries;
    } catch (e, s) {
      Logs().w('[diag] 读日志失败', e, s);
      return const [];
    }
  }

  /// 上报成功后推进游标。
  Future<void> advanceCursor(int seq) async {
    if (seq <= _cursor) return;
    _cursor = seq;
    await _store?.setInt(_cursorKey, _cursor);
  }

  /// 导出用的完整文本（先 flush，保证包含最新的）。
  Future<String> exportText() async {
    await flush();
    final file = _file;
    if (file == null) return '';
    try {
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (e, s) {
      Logs().w('[diag] 导出日志失败', e, s);
      return '';
    }
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    _buf.clear();
    _seq = 0;
    _cursor = 0;
    _initialized = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
