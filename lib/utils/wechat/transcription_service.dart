import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// 一条语音的转文字状态。
enum TranscriptionStatus { loading, done, failed }

@immutable
class TranscriptionEntry {
  const TranscriptionEntry(this.status, [this.text = '', this.detail]);

  final TranscriptionStatus status;
  final String text;

  /// 失败原因（HTTP 状态码 / 连接错误），显示在气泡下面。
  final String? detail;
}

/// 语音转文字。
///
/// 服务地址存在本地设置（默认家里的 9100 端口），**没配置就不显示入口**。
/// 结果按 eventId 缓存到本地，重进聊天不用重新请求。
class TranscriptionService {
  TranscriptionService._();

  static const Duration requestTimeout = Duration(seconds: 60);
  static const Duration downloadTimeout = Duration(seconds: 30);
  static const String _cacheKey = 'wechat_transcription_cache';
  static const int _cacheLimit = 300;

  static final Map<String, TranscriptionEntry> _entries = {};

  /// 用于通知界面刷新（气泡下的转文字结果）。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static TranscriptionEntry? entryOf(String eventId) => _entries[eventId];

  /// 没配置服务地址时，长按菜单里不出现「转文字」。
  static bool get enabled => WechatPrefs.transcriptionUrl.trim().isNotEmpty;

  /// 规范化服务地址：
  /// - 缺 `http://` 自动补（用户很可能只填 `192.168.31.154:9100`）
  /// - 去掉结尾的 `/`
  /// - 去掉结尾的 `/transcribe`（拼路径时会重复成 `/transcribe/transcribe`）
  static String normalizeUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/transcribe')) {
      value = value.substring(0, value.length - '/transcribe'.length);
    }
    return value;
  }

  /// 打 `/health` 判断服务是否可达（设置页保存时用）。
  static Future<bool> testConnection() async {
    final base = normalizeUrl(WechatPrefs.transcriptionUrl);
    if (base.isEmpty) return false;
    try {
      final response = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      Logs().w('[asr] 连通性检查失败: $e');
      return false;
    }
  }

  /// 读本地缓存（启动后第一次用到时调一次即可，重复调用没有副作用）。
  static void loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    final raw = WechatPrefs.store?.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is! String || value is! String || value.isEmpty) return;
        _entries[key] = TranscriptionEntry(TranscriptionStatus.done, value);
      });
    } catch (e, s) {
      Logs().w('[asr] 读取缓存失败', e, s);
    }
  }

  static bool _cacheLoaded = false;

  static Future<void> transcribe(Event event) async {
    if (!enabled) return;
    loadCache();
    final current = _entries[event.eventId];
    if (current?.status == TranscriptionStatus.loading) return;
    if (current?.status == TranscriptionStatus.done) return;

    _set(event.eventId, const TranscriptionEntry(TranscriptionStatus.loading));
    try {
      final text = await _request(event);
      if (text.trim().isEmpty) {
        _set(
          event.eventId,
          const TranscriptionEntry(TranscriptionStatus.failed),
        );
        return;
      }
      _set(
        event.eventId,
        TranscriptionEntry(TranscriptionStatus.done, text.trim()),
      );
      await _persist();
    } catch (e, s) {
      Logs().w('[asr] 转文字失败 event=${event.eventId}', e, s);
      _set(
        event.eventId,
        TranscriptionEntry(TranscriptionStatus.failed, '', _describeError(e)),
      );
    }
  }

  static String _describeError(Object error) {
    final text = error.toString();
    if (text.contains('Connection refused') || text.contains('拒绝')) {
      return '连接被拒绝';
    }
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return '超时';
    }
    if (text.contains('Failed host lookup')) return '找不到主机';
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  static void _set(String eventId, TranscriptionEntry entry) {
    _entries[eventId] = entry;
    revision.value++;
  }

  static Future<void> _persist() async {
    final store = WechatPrefs.store;
    if (store == null) return;
    final done = <String, String>{};
    for (final entry in _entries.entries) {
      if (entry.value.status != TranscriptionStatus.done) continue;
      final text = entry.value.text;
      if (text.isEmpty) continue;
      done[entry.key] = text;
      if (done.length >= _cacheLimit) break;
    }
    try {
      await store.setString(_cacheKey, jsonEncode(done));
    } catch (e, s) {
      Logs().w('[asr] 写缓存失败', e, s);
    }
  }

  static Future<String> _request(Event event) async {
    final file = await event.downloadAndDecryptAttachment().timeout(
      downloadTimeout,
    );

    final base = normalizeUrl(WechatPrefs.transcriptionUrl);

    // 兼容两种常见部署：直接 /transcribe，以及 OpenAI 风格的
    // /v1/audio/transcriptions（faster-whisper、whisper.cpp 之类）。
    final candidates = <String>[
      '$base/transcribe',
      '$base/v1/audio/transcriptions',
    ];

    Object? lastError;
    for (final endpoint in candidates) {
      try {
        final response = await _post(
          endpoint,
          file,
          filename: event.body.isEmpty ? 'voice.ogg' : event.body,
        );
        if (response.statusCode == 404 || response.statusCode == 405) {
          lastError = 'HTTP ${response.statusCode}';
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final snippet = response.body.length > 200
              ? response.body.substring(0, 200)
              : response.body;
          ActionLogger.I.log(
            'asr_fail',
            extra: {
              'status': response.statusCode,
              'body': snippet,
              'endpoint': endpoint,
            },
          );
          throw Exception('HTTP ${response.statusCode}');
        }
        return _textFrom(response.bodyBytes);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('转文字请求失败: $lastError');
  }

  static Future<http.Response> _post(
    String endpoint,
    MatrixFile file, {
    required String filename,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    // 服务端要求的字段名是 audio（发 file= 会 422）。
    request.files.add(
      http.MultipartFile.fromBytes('audio', file.bytes, filename: filename),
    );
    final contentType = file.mimeType;
    if (contentType.isNotEmpty) {
      request.fields['mime'] = contentType;
    }
    final streamed = await request.send().timeout(requestTimeout);
    return http.Response.fromStream(streamed);
  }

  static String _textFrom(List<int> bodyBytes) {
    final body = utf8.decode(bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text =
            decoded['text'] ?? decoded['result'] ?? decoded['transcript'];
        if (text is String) return text;
      }
      if (decoded is String) return decoded;
    } catch (_) {
      // 不是 JSON 就直接当文本用。
    }
    return body;
  }
}
