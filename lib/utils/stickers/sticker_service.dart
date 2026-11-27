// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/stickers/sticker_image.dart';
import 'package:fluffychat/utils/stickers/sticker_store.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 最近使用的表情（只在本机保存，最多 9 个，和微信一致）。
class StickerRecents {
  static const String _key = 'wechat_recent_stickers';
  static const int maxItems = 9;

  static Future<List<StickerItem>> load() async {
    final store = await SharedPreferences.getInstance();
    final raw = store.getStringList(_key) ?? const [];
    final items = <StickerItem>[];
    for (final entry in raw) {
      try {
        final json = jsonDecode(entry);
        if (json is Map) {
          items.add(StickerItem.fromJson(Map<String, Object?>.from(json)));
        }
      } catch (_) {
        // 旧版本留下的脏数据直接跳过
      }
    }
    return items;
  }

  static Future<List<StickerItem>> push(StickerItem item) async {
    final store = await SharedPreferences.getInstance();
    final current = [
      item,
      ...(await load()).where((entry) => entry.url != item.url),
    ].take(maxItems).toList();
    await store.setStringList(
      _key,
      current.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
    return current;
  }

  static Future<void> clear() async {
    final store = await SharedPreferences.getInstance();
    await store.remove(_key);
  }
}

/// 把一张本地图片变成可用的表情：按规格压缩 → 上传 → 返回 [StickerItem]。
class StickerUploader {
  static String bodyForName(String name) {
    var body = name.replaceAll('\\', '/').split('/').last;
    final dot = body.lastIndexOf('.');
    if (dot > 0) body = body.substring(0, dot);
    body = body.trim();
    if (body.isEmpty) return 'sticker';
    return body;
  }

  static Future<StickerItem> upload(
    Client client,
    Uint8List bytes, {
    required String name,
    String? mimetype,
  }) async {
    final prepared = await StickerImage.prepare(
      bytes,
      mimetype: mimetype,
      name: name,
    );
    final uri = await client.uploadContent(
      prepared.bytes,
      filename:
          '$name.${prepared.animated ? (prepared.mimetype == 'image/gif' ? 'gif' : 'webp') : (prepared.mimetype == 'image/png' ? 'png' : 'jpg')}',
      contentType: prepared.mimetype,
    );
    return StickerItem(
      url: uri.toString(),
      body: bodyForName(name),
      mimetype: prepared.mimetype,
      width: prepared.width,
      height: prepared.height,
      size: prepared.bytes.length,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      animated: prepared.animated,
    );
  }

  /// 从一条 `m.sticker` 事件里取出表情（长按「添加到表情」用）。
  static StickerItem? fromEvent(Event event) {
    final url = event.content.tryGet<String>('url');
    if (url == null || !url.startsWith('mxc://')) return null;
    final info = event.content.tryGetMap<String, Object?>('info');
    return StickerItem(
      url: url,
      body: event.body.isNotEmpty ? event.body : 'sticker',
      mimetype: info?.tryGet<String>('mimetype'),
      width: info?.tryGet<int>('w'),
      height: info?.tryGet<int>('h'),
      size: info?.tryGet<int>('size'),
      addedAt: DateTime.now().millisecondsSinceEpoch,
      animated: (info?.tryGet<String>('mimetype') ?? '').contains('gif'),
    );
  }
}

/// 长按别人的表情气泡时调用的「添加到表情」。
Future<void> addStickerFromEvent(BuildContext context, Event event) async {
  final l10n = L10n.of(context);
  final item = StickerUploader.fromEvent(event);
  if (item == null) {
    AppToast.show(l10n.stickerUploadFailed, isError: true);
    return;
  }
  final result = await StickerStore(event.room.client).add(item);
  switch (result) {
    case StickerAddResult.added:
      StickerStore.revision.value++;
      AppToast.show(l10n.stickerAddedCount('1'));
    case StickerAddResult.duplicate:
      AppToast.show(l10n.stickerAlreadyAdded);
    case StickerAddResult.failed:
      AppToast.show(l10n.stickerUploadFailed, isError: true);
  }
}
