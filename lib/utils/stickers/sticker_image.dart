// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum StickerImageError {
  /// 不是图片
  unsupported,

  /// 动图超过 1MB
  animatedTooLarge,

  /// 动图尺寸超过 1024×1024
  animatedTooBig,

  /// 图片解码失败
  decodeFailed,
}

class StickerImageException implements Exception {
  const StickerImageException(this.error, {this.name});

  final StickerImageError error;
  final String? name;

  @override
  String toString() => 'StickerImageException($error, $name)';
}

class StickerImageResult {
  const StickerImageResult({
    required this.bytes,
    required this.mimetype,
    required this.width,
    required this.height,
    required this.animated,
  });

  final Uint8List bytes;
  final String mimetype;
  final int width;
  final int height;
  final bool animated;
}

/// 表情图片的规格校验与压缩。
///
/// | 类型 | 规则 |
/// | --- | --- |
/// | 静态图 PNG / JPG / WebP | 最长边 512，≤ 512KB，PNG 保透明 |
/// | 动图 GIF / 动态 WebP | 原样保留（不转码），≤ 1MB，≤ 1024×1024 |
class StickerImage {
  static const int staticMaxSide = 512;
  static const int staticMaxBytes = 512 * 1000;
  static const int animatedMaxBytes = 1000 * 1000;
  static const int animatedMaxSide = 1024;
  static const int _minQuality = 60;

  static bool isAnimated(List<int> bytes, String? mimetype) {
    if (mimetype == 'image/gif') return true;
    if (bytes.length < 12) return false;
    // GIF: 头 6 字节是 GIF87a / GIF89a
    final header = String.fromCharCodes(bytes.sublist(0, 6));
    if (header == 'GIF87a' || header == 'GIF89a') return true;
    if (mimetype == 'image/webp') {
      // 动态 WebP 在 RIFF 里带 ANIM 块
      final probe = bytes.length < 64 ? bytes : bytes.sublist(0, 64);
      return String.fromCharCodes(probe).contains('ANIM');
    }
    return false;
  }

  /// GIF 的宽高直接读文件头，省一次解码。
  static (int, int)? _gifSize(List<int> bytes) {
    if (bytes.length < 10) return null;
    final width = bytes[6] | (bytes[7] << 8);
    final height = bytes[8] | (bytes[9] << 8);
    if (width <= 0 || height <= 0) return null;
    return (width, height);
  }

  static Future<StickerImageResult> prepare(
    Uint8List bytes, {
    String? mimetype,
    String? name,
  }) async {
    final animated = isAnimated(bytes, mimetype);
    if (animated) {
      if (bytes.length > animatedMaxBytes) {
        throw StickerImageException(
          StickerImageError.animatedTooLarge,
          name: name,
        );
      }
      var size = _gifSize(bytes);
      if (size == null) {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw StickerImageException(
            StickerImageError.decodeFailed,
            name: name,
          );
        }
        size = (decoded.width, decoded.height);
      }
      final (width, height) = size;
      if (width > animatedMaxSide || height > animatedMaxSide) {
        throw StickerImageException(
          StickerImageError.animatedTooBig,
          name: name,
        );
      }
      return StickerImageResult(
        bytes: bytes,
        mimetype: mimetype == 'image/gif' ? 'image/gif' : 'image/webp',
        width: width,
        height: height,
        animated: true,
      );
    }

    final keepAlpha =
        mimetype == 'image/png' || mimetype == 'image/webp' || mimetype == null;
    final result = await compute(
      _compressStatic,
      _StaticArguments(
        bytes: bytes,
        maxSide: staticMaxSide,
        maxBytes: staticMaxBytes,
        keepAlpha: keepAlpha,
      ),
    );
    if (result == null) {
      throw StickerImageException(StickerImageError.decodeFailed, name: name);
    }
    return StickerImageResult(
      bytes: result.bytes,
      mimetype: result.mimetype,
      width: result.width,
      height: result.height,
      animated: false,
    );
  }
}

class _StaticArguments {
  const _StaticArguments({
    required this.bytes,
    required this.maxSide,
    required this.maxBytes,
    required this.keepAlpha,
  });

  final Uint8List bytes;
  final int maxSide;
  final int maxBytes;
  final bool keepAlpha;
}

class _StaticResult {
  const _StaticResult({
    required this.bytes,
    required this.mimetype,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimetype;
  final int width;
  final int height;
}

_StaticResult? _compressStatic(_StaticArguments args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  if (image.width > args.maxSide || image.height > args.maxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: args.maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: args.maxSide,
            interpolation: img.Interpolation.average,
          );
  }

  // 只有真的带透明通道才坚持 PNG；不透明图走 JPG，体积小很多。
  final keepAlpha = args.keepAlpha && image.numChannels == 4;
  for (final scale in const [1.0, 0.85, 0.72, 0.6, 0.5, 0.4, 0.32]) {
    final current = scale >= 1.0
        ? image
        : img.copyResize(
            image,
            width: (image.width * scale).round().clamp(16, image.width),
            height: (image.height * scale).round().clamp(16, image.height),
            interpolation: img.Interpolation.average,
          );

    if (keepAlpha) {
      final png = img.encodePng(current, level: 9);
      if (png.length <= args.maxBytes) {
        return _StaticResult(
          bytes: png,
          mimetype: 'image/png',
          width: current.width,
          height: current.height,
        );
      }
      continue;
    }

    var quality = 85;
    var encoded = img.encodeJpg(current, quality: quality);
    while (encoded.length > args.maxBytes &&
        quality > StickerImage._minQuality) {
      quality -= 10;
      encoded = img.encodeJpg(current, quality: quality);
    }
    if (encoded.length <= args.maxBytes) {
      return _StaticResult(
        bytes: encoded,
        mimetype: 'image/jpeg',
        width: current.width,
        height: current.height,
      );
    }
  }

  // 兜底：极小尺寸的 JPG，保证一定落在上限内（丢掉透明，但不会超限）。
  final tiny = img.copyResize(
    image,
    width: (image.width * 0.25).round().clamp(16, image.width),
    height: (image.height * 0.25).round().clamp(16, image.height),
    interpolation: img.Interpolation.average,
  );
  return _StaticResult(
    bytes: img.encodeJpg(tiny, quality: StickerImage._minQuality),
    mimetype: 'image/jpeg',
    width: tiny.width,
    height: tiny.height,
  );
}
