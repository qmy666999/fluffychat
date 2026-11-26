// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 三个上下跳动的小圆点，用于「正在等待对方接受邀请…」。
class LoadingDots extends StatefulWidget {
  const LoadingDots({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _dot(i),
              ),
          ],
        );
      },
    );
  }

  Widget _dot(int index) {
    final phase = (_controller.value + index * 0.18) % 1.0;
    final wave = math.sin(phase * math.pi * 2);
    return Transform.translate(
      offset: Offset(0, -3 * (wave < 0 ? 0 : wave)),
      child: Opacity(
        opacity: 0.35 + 0.65 * (0.5 + wave / 2),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
