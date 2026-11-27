// SPDX-FileCopyrightText: 2019-Present FluffyChatX contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Shrinks images on device before they are uploaded.
///
/// The upload link of a self hosted homeserver behind a tunnel can be as slow
/// as a few kilobytes per second, so a 4 MB camera picture would take minutes.
/// Re-encoding at 1280 px and JPEG quality 80 turns it into roughly 200-400 kB
/// without a visible difference on a phone screen.
class ImageCompressor {
  /// Longest side of the resulting image in pixels.
  static const int defaultMaxSide = 1280;

  /// JPEG quality used for the first encoding attempt.
  static const int defaultQuality = 80;

  /// Hard upper bound for the encoded image. Lowered quality until it fits.
  static const int defaultMaxBytes = 600 * 1000;

  static const int _minQuality = 40;

  /// Returns the re-encoded JPEG bytes or null if the image could not be
  /// decoded (for example a HEIC file) or compression failed.
  static Future<Uint8List?> compress(
    Uint8List bytes, {
    int maxSide = defaultMaxSide,
    int quality = defaultQuality,
    int maxBytes = defaultMaxBytes,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      return await compute(
        _compressInIsolate,
        _CompressArguments(
          bytes: bytes,
          maxSide: maxSide,
          quality: quality,
          maxBytes: maxBytes,
        ),
      );
    } catch (e, s) {
      debugPrint('[image_compressor] failed: $e\n$s');
      return null;
    }
  }
}

@immutable
class _CompressArguments {
  const _CompressArguments({
    required this.bytes,
    required this.maxSide,
    required this.quality,
    required this.maxBytes,
  });

  final Uint8List bytes;
  final int maxSide;
  final int quality;
  final int maxBytes;
}

Uint8List? _compressInIsolate(_CompressArguments args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;

  var image = img.bakeOrientation(decoded);
  final longestSide = image.width > image.height ? image.width : image.height;
  if (longestSide > args.maxSide) {
    final scale = args.maxSide / longestSide;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  var quality = args.quality;
  var encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
  while (encoded.length > args.maxBytes &&
      quality > ImageCompressor._minQuality) {
    quality -= 10;
    if (quality < ImageCompressor._minQuality) {
      quality = ImageCompressor._minQuality;
    }
    encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (quality == ImageCompressor._minQuality) break;
  }
  return encoded;
}
