// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// 把一张位图（一般是气泡的截图）切碎后飞散出去的一层。
///
/// 故意做成「只依赖 material_ui + dart:ui」的纯视觉组件：
/// * 真正的撤回流程在 `message_shatter.dart` 里调用它；
/// * 预览工程 `C:\matrix-ai\bubble_preview` 直接拷贝这个文件，
///   把 [progress] 固定成某个值就能截一张静态图来核对碎片形态。
class ShatterLayer extends StatefulWidget {
  const ShatterLayer({
    super.key,
    required this.image,
    required this.rect,
    required this.duration,
    this.progress,
    this.disposeImage = true,
  });

  final ui.Image image;

  /// 原气泡在屏幕上的位置（用来给 Overlay 里的 Positioned 定位）。
  final Rect rect;

  final Duration duration;

  /// 指定后不再自己跑动画，直接画这一帧（预览/测试用）。
  final double? progress;

  /// 预览里传 false，避免把外部传入的图片 dispose 掉。
  final bool disposeImage;

  @override
  State<ShatterLayer> createState() => _ShatterLayerState();
}

class _ShatterLayerState extends State<ShatterLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  late final List<_Shard> _shards = _Shard.build(widget.rect.size);

  @override
  void dispose() {
    _controller.dispose();
    if (widget.disposeImage) widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final raw = widget.progress ?? _controller.value;
            return Opacity(
              opacity: (1 - raw * 0.9).clamp(0.0, 1.0),
              child: CustomPaint(
                painter: _ShatterPainter(
                  image: widget.image,
                  shards: _shards,
                  // 这里传原始进度，缓动只在 painter 里做一次 ——
                  // 两端各缓动一次会让碎片「嗖」地飞没影。
                  progress: raw,
                ),
                size: widget.rect.size,
              ),
            );
          },
        ),
      ),
    );

    if (widget.progress != null) {
      // 预览模式：不自带 Positioned，交给外层布局。
      return SizedBox(
        width: widget.rect.width,
        height: widget.rect.height,
        child: layer,
      );
    }

    return Positioned(
      left: widget.rect.left,
      top: widget.rect.top,
      width: widget.rect.width,
      height: widget.rect.height,
      child: layer,
    );
  }
}

/// 一片碎片：从哪块原图切下来、往哪飞、转多少、什么时候开始飞。
class _Shard {
  const _Shard({
    required this.source,
    required this.destination,
    required this.direction,
    required this.distance,
    required this.rotation,
    required this.delay,
  });

  static const int columns = 8;
  static const int rows = 6;
  static const double _pixelRatio = 2;

  /// 在原图（2 倍像素）里的矩形。
  final Rect source;

  /// 在原气泡坐标里的矩形。
  final Rect destination;
  final Offset direction;
  final double distance;
  final double rotation;
  final double delay;

  static List<_Shard> build(Size size) {
    final random = math.Random();
    final tileWidth = size.width / columns;
    final tileHeight = size.height / rows;
    final center = Offset(size.width / 2, size.height / 2);
    final shards = <_Shard>[];

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final destination = Rect.fromLTWH(
          column * tileWidth,
          row * tileHeight,
          tileWidth,
          tileHeight,
        );
        // 以气泡中心为原点向外飞，再叠加随机角度，
        // 保证 48 片碎片没有两片方向完全相同。
        final outward = destination.center - center;
        final baseAngle = outward.distance == 0
            ? random.nextDouble() * math.pi * 2
            : outward.direction;
        final angle = baseAngle + (random.nextDouble() - 0.5) * 1.8;
        shards.add(
          _Shard(
            source: Rect.fromLTWH(
              destination.left * _pixelRatio,
              destination.top * _pixelRatio,
              destination.width * _pixelRatio,
              destination.height * _pixelRatio,
            ),
            destination: destination,
            direction: Offset(math.cos(angle), math.sin(angle)),
            distance: 30 + random.nextDouble() * 90,
            rotation: (random.nextDouble() - 0.5) * 2.2,
            delay: random.nextDouble() * 0.12,
          ),
        );
      }
    }
    return shards;
  }
}

class _ShatterPainter extends CustomPainter {
  _ShatterPainter({
    required this.image,
    required this.shards,
    required this.progress,
  });

  final ui.Image image;
  final List<_Shard> shards;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (progress <= 0.001) {
      // 第 0 帧还没开始碎，画整张图（预览时用来看「原样」）。
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        paint,
      );
      return;
    }
    for (final shard in shards) {
      final window = 1 - shard.delay;
      final local = ((progress - shard.delay) / window).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // 用 easeInOutCubic 而不是 easeOut：一上来就把碎片甩出去的话，
      // 观众看到的只是「气泡突然消失 + 一群碎片飞过」，没有「先裂开再生开」的过程。
      final eased = Curves.easeInOutCubic.transform(local);
      final offset = shard.direction * (shard.distance * eased);
      canvas.save();
      canvas.translate(
        shard.destination.center.dx + offset.dx,
        shard.destination.center.dy + offset.dy,
      );
      canvas.rotate(shard.rotation * eased);
      canvas.drawImageRect(
        image,
        shard.source,
        Rect.fromCenter(
          center: Offset.zero,
          width: shard.destination.width,
          height: shard.destination.height,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ShatterPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.image != image;
}
