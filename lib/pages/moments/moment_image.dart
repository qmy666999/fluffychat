// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 朋友圈用的 mxc 图片。
///
/// 为什么不直接用 [MxcImage]：它在拿不到数据时会一直显示占位转圈
/// （IOException 还会无限重试），而且宽高传 null 时缩略图请求本身就是无效的。
/// 这里显式给宽高、10 秒超时、失败显示破碎图标，高度保持稳定不跳版。
class MomentImage extends StatefulWidget {
  final Uri? uri;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  /// true = 直接取原图（封面、点开的大图）；
  /// false = 按显示尺寸取缩略图（列表九宫格）。
  final bool original;

  const MomentImage({
    required this.uri,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.original = false,
    super.key,
  });

  @override
  State<MomentImage> createState() => _MomentImageState();
}

class _MomentImageState extends State<MomentImage> {
  Uint8List? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MomentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _data = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final uri = widget.uri;
    if (uri == null || uri.scheme != 'mxc') {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final client = Matrix.of(context).client;
    try {
      final data = await client
          .downloadMxcCached(
            uri,
            // 缩略图必须带尺寸，否则请求本身就是无效的。
            // 尺寸 ×2 是为了适配高 DPI 屏幕；服务器开了动态缩略图后
            // 会按这个尺寸现场生成，不会再拿 96px 拉伸。
            width: widget.original
                ? null
                : (widget.width ?? 240) * 2,
            height: widget.original
                ? null
                : (widget.height ?? 240) * 2,
            isThumbnail: !widget.original,
            thumbnailMethod: ThumbnailMethod.crop,
          )
          .timeout(Duration(seconds: widget.original ? 20 : 10));
      if (!mounted) return;
      setState(() {
        _data = data;
        _failed = data.isEmpty;
      });
    } catch (e) {
      debugPrint('[moments] image load failed: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(4);

    Widget child;
    if (_failed) {
      child = SizedBox(
        width: widget.width,
        height: widget.height,
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else if (_data == null) {
      child =
          widget.placeholder ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            ),
          );
    } else {
      child = Image.memory(
        _data!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, _, _) => SizedBox(
          width: widget.width,
          height: widget.height,
          child: Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ClipRRect(borderRadius: radius, child: child);
  }
}
