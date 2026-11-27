// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 分片元数据：当前片数与总数。
class StickerStoreMeta {
  const StickerStoreMeta({required this.shards, required this.total});

  final int shards;
  final int total;
}

/// 一个自定义表情。
///
/// 字段刻意和 `m.sticker` 事件的字段保持一致（`body` / `url` / `info`），
/// 以后如果换成「表情收藏房间」方案，结构可以直接复用。
class StickerItem {
  const StickerItem({
    required this.url,
    required this.body,
    this.mimetype,
    this.width,
    this.height,
    this.size,
    this.addedAt = 0,
    this.animated = false,
  });

  final String url;
  final String body;
  final String? mimetype;
  final int? width;
  final int? height;
  final int? size;
  final int addedAt;
  final bool animated;

  factory StickerItem.fromJson(Map<String, Object?> json) => StickerItem(
    url: (json['url'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    mimetype: json['mimetype'] as String?,
    width: json['w'] as int?,
    height: json['h'] as int?,
    size: json['size'] as int?,
    addedAt: (json['addedAt'] as int?) ?? 0,
    animated: (json['animated'] as bool?) ?? false,
  );

  Map<String, Object?> toJson() => {
    'url': url,
    'body': body,
    if (mimetype != null) 'mimetype': mimetype,
    if (width != null) 'w': width,
    if (height != null) 'h': height,
    if (size != null) 'size': size,
    'addedAt': addedAt,
    if (animated) 'animated': true,
  };

  /// 发送时的 `m.sticker` content。
  Map<String, Object?> toStickerContent() => {
    'body': body,
    'url': url,
    'info': {
      if (mimetype != null) 'mimetype': mimetype,
      if (width != null) 'w': width,
      if (height != null) 'h': height,
      if (size != null) 'size': size,
    },
  };
}

/// 分片存储的自定义表情库。
///
/// Matrix 对单条事件有大小限制（Synapse 默认 `max_event_size` 约 64KB），
/// 所以一个 account data key 装不下太多表情。这里按 [shardSize] 条一片：
///
/// ```
/// com.dafeiyu.stickers.meta → {"shards": 3, "total": 240}
/// com.dafeiyu.stickers.0    → {"items": [ … 80 条 … ]}
/// com.dafeiyu.stickers.1    → {"items": [ … ]}
/// ```
///
/// 写入规则：
/// 1. 先写分片，再写 meta（反了会出现「meta 说有 N 片但数据还没写」的空洞）
/// 2. 所有写操作串行（[_serial]），否则两次并发追加会互相覆盖
/// 3. 删除不缩片，只改 meta.total
class StickerStore {
  StickerStore(this.client);

  final Client client;

  static const String metaKey = 'com.dafeiyu.stickers.meta';
  static const String shardPrefix = 'com.dafeiyu.stickers.';
  static const int shardSize = 80;

  /// 数据变更计数器：面板、管理页监听它来刷新。
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<void> _queue = Future<void>.value();

  /// 每个账号的已读缓存：userId -> (shardIndex -> items)
  static final Map<String, Map<int, List<StickerItem>>> _cache = {};

  String get _userId => client.userID ?? '';

  Map<int, List<StickerItem>> get _shardCache =>
      _cache.putIfAbsent(_userId, () => {});

  static Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  StickerStoreMeta loadMeta() {
    final content = client.accountData[metaKey]?.content;
    if (content == null) return const StickerStoreMeta(shards: 0, total: 0);
    return StickerStoreMeta(
      shards: (content['shards'] as int?) ?? 0,
      total: (content['total'] as int?) ?? 0,
    );
  }

  List<StickerItem> loadShard(int index) {
    final cached = _shardCache[index];
    if (cached != null) return cached;
    final content = client.accountData['$shardPrefix$index']?.content;
    final rawItems = content?['items'];
    final items = <StickerItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          items.add(StickerItem.fromJson(Map<String, Object?>.from(raw)));
        }
      }
    }
    _shardCache[index] = items;
    return items;
  }

  /// 读取 [count] 条（从 [start] 开始），只摸到需要的那几片。
  Future<List<StickerItem>> loadRange({int start = 0, int count = 240}) {
    final meta = loadMeta();
    final result = <StickerItem>[];
    var index = start ~/ shardSize;
    final shards = meta.shards;
    while (index < shards && result.length < count) {
      result.addAll(loadShard(index));
      index++;
    }
    return Future.value(result);
  }

  /// 读出全部表情（管理页、搜索用）。
  Future<List<StickerItem>> loadAll() async {
    final meta = loadMeta();
    final result = <StickerItem>[];
    for (var i = 0; i < meta.shards; i++) {
      result.addAll(loadShard(i));
    }
    return result;
  }

  int get cachedTotal => loadMeta().total;

  Future<bool> contains(String url) async {
    final meta = loadMeta();
    for (var i = 0; i < meta.shards; i++) {
      if (loadShard(i).any((item) => item.url == url)) return true;
    }
    return false;
  }

  Future<StickerAddResult> add(StickerItem item) => _serial(() async {
    if (item.url.isEmpty) return StickerAddResult.failed;
    if (await contains(item.url)) return StickerAddResult.duplicate;

    final meta = loadMeta();
    final shards = meta.shards;
    if (shards == 0) {
      await _writeShard(0, [item]);
      await _writeMeta(shards: 1, total: meta.total + 1);
      return StickerAddResult.added;
    }
    final last = shards - 1;
    final items = loadShard(last);
    if (items.length >= shardSize) {
      await _writeShard(last + 1, [item]);
      await _writeMeta(shards: last + 2, total: meta.total + 1);
    } else {
      await _writeShard(last, [...items, item]);
      await _writeMeta(shards: shards, total: meta.total + 1);
    }
    return StickerAddResult.added;
  });

  Future<void> remove(String url) => _serial(() async {
    final meta = loadMeta();
    for (var i = 0; i < meta.shards; i++) {
      final items = loadShard(i);
      if (!items.any((item) => item.url == url)) continue;
      await _writeShard(i, items.where((item) => item.url != url).toList());
      await _writeMeta(
        shards: meta.shards,
        total: meta.total > 0 ? meta.total - 1 : 0,
      );
      return;
    }
  });

  Future<void> removeMany(Iterable<String> urls) => _serial(() async {
    final targets = urls.toSet();
    if (targets.isEmpty) return;
    final meta = loadMeta();
    var removed = 0;
    for (var i = 0; i < meta.shards; i++) {
      final items = loadShard(i);
      final kept = items.where((item) => !targets.contains(item.url)).toList();
      if (kept.length == items.length) continue;
      removed += items.length - kept.length;
      await _writeShard(i, kept);
    }
    if (removed == 0) return;
    await _writeMeta(
      shards: meta.shards,
      total: (meta.total - removed).clamp(0, meta.total),
    );
  });

  /// 长按菜单里的「移到最前」：从原片删掉，插到第 0 片最前面。
  Future<void> moveToFront(String url) => _serial(() async {
    final meta = loadMeta();
    StickerItem? item;
    for (var i = 0; i < meta.shards; i++) {
      final items = loadShard(i);
      final index = items.indexWhere((entry) => entry.url == url);
      if (index == -1) continue;
      item = items[index];
      await _writeShard(i, [...items]..removeAt(index));
      break;
    }
    if (item == null) return;
    final first = loadShard(0);
    await _writeShard(0, [item, ...first]);
    // total 没变
    await _writeMeta(shards: meta.shards, total: meta.total);
  });

  /// 拖动排序：整体按新的顺序重写分片。
  Future<void> reorder(List<String> orderedUrls) => _serial(() async {
    final all = <String, StickerItem>{};
    for (final item in await loadAll()) {
      all[item.url] = item;
    }
    final ordered = <StickerItem>[];
    for (final url in orderedUrls) {
      final item = all.remove(url);
      if (item != null) ordered.add(item);
    }
    // 没有出现在 orderedUrls 里的（并发新增）保持原有顺序接在后面
    ordered.addAll(all.values);

    final shards = (ordered.length + shardSize - 1) ~/ shardSize;
    for (var i = 0; i < shards; i++) {
      final start = i * shardSize;
      final end = (start + shardSize).clamp(0, ordered.length);
      await _writeShard(i, ordered.sublist(start, end));
    }
    _shardCache.removeWhere((index, _) => index >= shards);
    await _writeMeta(shards: shards, total: ordered.length);
  });

  Future<void> _writeShard(int index, List<StickerItem> items) async {
    _shardCache[index] = List<StickerItem>.of(items);
    final content = <String, Object?>{
      'items': items.map((item) => item.toJson()).toList(),
    };
    await client.setAccountData(_userId, '$shardPrefix$index', content);
    _mirror('$shardPrefix$index', content);
  }

  Future<void> _writeMeta({required int shards, required int total}) async {
    final content = <String, Object?>{'shards': shards, 'total': total};
    await client.setAccountData(_userId, metaKey, content);
    _mirror(metaKey, content);
    revision.value++;
  }

  /// `setAccountData` 只是 HTTP，不会更新 `client.accountData`。
  /// 这里手动镜像一份，界面才能在 sync 回来之前就看到新数据。
  void _mirror(String key, Map<String, Object?> content) {
    client.accountData[key] = BasicEvent(type: key, content: content);
  }

  static void invalidate(String? userId) {
    if (userId == null) {
      _cache.clear();
    } else {
      _cache.remove(userId);
    }
    revision.value++;
  }
}

enum StickerAddResult { added, duplicate, failed }
