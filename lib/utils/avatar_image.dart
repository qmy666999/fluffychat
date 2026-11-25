// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片格式解不开（最常见的是 HEIC：iPhone / 部分小米相册的默认格式）。
///
/// Synapse 生成不了 HEIC 的缩略图，直接传上去头像会变成灰色，所以宁可在客户端
/// 明确拒绝，也不静默传一个坏文件。
class UnsupportedAvatarFormat implements Exception {
  const UnsupportedAvatarFormat();

  @override
  String toString() => 'UnsupportedAvatarFormat';
}

/// 头像统一转成 JPEG（最长边 512px），保证 Synapse 能生成缩略图。
///
/// 从相册选的照片经常是 HEIC，`package:image` 解不了 HEIC，会抛
/// [UnsupportedAvatarFormat]，由界面提示用户换一张。
Uint8List prepareAvatarBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const UnsupportedAvatarFormat();

  final needsResize = decoded.width > 512 || decoded.height > 512;
  final image = needsResize
      ? (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: 512)
            : img.copyResize(decoded, height: 512))
      : decoded;

  return img.encodeJpg(image, quality: 88);
}
