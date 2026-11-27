import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 微信式的「按住说话」浮层：圆角胶囊 + 横向柱状声波。
///
/// 不是圆圈向外扩散的波纹——那是录音机 App 的风格。这里是：
/// 一排竖条（中间高两边低），高度跟音量联动，新的从右边进、往左滚。
///
/// 放在 Overlay 里渲染（而不是聊天页的 Stack 里），因为聊天页的输入栏被
/// [Material.clipBehavior] = [Clip.hardEdge] 裁掉了，画不到输入栏外面去。
class RecordingBubble extends StatefulWidget {
  const RecordingBubble({
    super.key,
    required this.level,
    required this.duration,
    required this.cancelling,
    required this.visible,
  });

  /// 当前音量，0..1；返回 null 表示拿不到真实振幅，浮层会退化成 sin 伪波形。
  final double? Function() level;

  /// 当前录音时长。
  final Duration Function() duration;

  /// 手指是否在左上角的取消区。
  final bool cancelling;

  /// false 时播放淡出动画（由调用方在动画结束后移除 OverlayEntry）。
  final bool visible;

  /// 柱子根数（微信大约 30~40 根）
  static const int barCount = 36;

  @override
  State<RecordingBubble> createState() => _RecordingBubbleState();
}

class _RecordingBubbleState extends State<RecordingBubble>
    with SingleTickerProviderStateMixin {
  /// 从右往左滚动的音量序列，长度固定 [RecordingBubble.barCount]
  final List<double> _levels = <double>[];

  /// 平滑后的当前音量（0..1），避免柱子一跳一跳
  double _smoothed = 0;

  Timer? _ticker;
  late final AnimationController _appear;
  int _elapsedTicks = 0;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.visible ? 0 : 1,
    );
    if (widget.visible) _appear.forward();
    // 先铺一段静态波形，避免刚按下时是一条直线
    for (var i = 0; i < RecordingBubble.barCount; i++) {
      _levels.add(0.2 + 0.6 * math.sin(i / 4).abs());
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant RecordingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _appear.forward();
      } else {
        _appear.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _appear.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    _elapsedTicks++;
    final raw = widget.level();
    final target = raw == null
        ? _pseudoLevel
        : math.max(0.05, math.min(1.0, raw));
    // 起音快、回落慢，看起来才像在说话
    final factor = target > _smoothed ? 0.55 : 0.22;
    _smoothed = math.max(
      0.05,
      math.min(1.0, _smoothed + (target - _smoothed) * factor),
    );
    setState(() {
      _levels.add(_smoothed);
      while (_levels.length > RecordingBubble.barCount) {
        _levels.removeAt(0);
      }
    });
  }

  double get _pseudoLevel {
    final t = _elapsedTicks / 10;
    return 0.2 + 0.6 * math.sin(t * 2.2).abs();
  }

  String get _durationLabel {
    final duration = widget.duration();
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = widget.cancelling
        ? colorScheme.error
        : colorScheme.primary;
    final foreground = widget.cancelling
        ? colorScheme.onError
        : colorScheme.onPrimary;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.75, 300.0);

    return FadeTransition(
      opacity: _appear,
      child: AnimatedBuilder(
        animation: _appear,
        builder: (context, child) {
          // 从下方 12dp 上浮出现
          return Transform.translate(
            offset: Offset(0, (1 - _appear.value) * 12),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          height: 72,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  child: CustomPaint(
                    painter: _WavePainter(
                      levels: List<double>.of(_levels),
                      color: foreground,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 6,
                child: Text(
                  _durationLabel,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  static const double _minHeight = 4;
  static const double _maxHeight = 40;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final count = levels.length;
    // 柱宽由可用宽度算出来，保证 36 根一定塞得进去，不会画到胶囊外面
    final step = size.width / count;
    final barWidth = (step * 0.62).clamp(1.2, 3.0);
    final centerY = size.height / 2;
    final middle = (count - 1) / 2;

    for (var i = 0; i < count; i++) {
      // 中间高、两边低的山形包络
      final envelope =
          1 - (i - middle).abs() / (middle == 0 ? 1 : middle) * 0.55;
      final level = levels[i].clamp(0.0, 1.0);
      final height = _minHeight + level * envelope * (_maxHeight - _minHeight);
      final left = i * step + (step - barWidth) / 2;
      final rect = Rect.fromLTWH(left, centerY - height / 2, barWidth, height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(2, barWidth / 2)),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.levels.length != levels.length) return true;
    for (var i = 0; i < levels.length; i++) {
      if (oldDelegate.levels[i] != levels[i]) return true;
    }
    return false;
  }
}
