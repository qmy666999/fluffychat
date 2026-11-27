// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'moment_image.dart';

/// 朋友圈图片全屏查看器：黑底、左右滑同组图片、右上角页码、
/// 双击放大 / 还原、单击或向下拖关闭。
class MomentGalleryPage extends StatefulWidget {
  const MomentGalleryPage({
    required this.images,
    this.initialIndex = 0,
    super.key,
  });

  final List<Uri> images;
  final int initialIndex;

  @override
  State<MomentGalleryPage> createState() => _MomentGalleryPageState();
}

class _MomentGalleryPageState extends State<MomentGalleryPage> {
  late final PageController _pageController;
  final Map<int, TransformationController> _transforms = {};
  late int _index;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _transformOf(int index) =>
      _transforms.putIfAbsent(index, TransformationController.new);

  bool _isZoomed(int index) =>
      _transformOf(index).value.getMaxScaleOnAxis() > 1.05;

  void _toggleZoom(int index) {
    final controller = _transformOf(index);
    controller.value = _isZoomed(index)
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(2.5, 2.5, 1);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    final top = MediaQuery.paddingOf(context).top;
    // 往下拖得越多，背景越透明，给「拖走关闭」的手感。
    final fade = (1 - (_dragOffset.abs() / 400)).clamp(0.2, 1.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: fade),
              child: PageView.builder(
                controller: _pageController,
                physics: _dragOffset == 0 && !_isZoomed(_index)
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() {
                  _index = index;
                  _dragOffset = 0;
                }),
                itemCount: count,
                itemBuilder: _buildPage,
              ),
            ),
          ),
          Positioned(
            top: top + 12,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_index + 1} / $count',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          Positioned(
            top: top,
            left: 4,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final controller = _transformOf(index);
    final zoomed = _isZoomed(index);
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      onDoubleTap: () => _toggleZoom(index),
      onVerticalDragUpdate: zoomed
          ? null
          : (details) => setState(() {
              _dragOffset += details.delta.dy;
            }),
      onVerticalDragEnd: zoomed
          ? null
          : (_) {
              if (_dragOffset.abs() > 120) {
                Navigator.of(context).maybePop();
              } else {
                setState(() => _dragOffset = 0);
              }
            },
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: InteractiveViewer(
          transformationController: controller,
          minScale: 1,
          maxScale: 4,
          panEnabled: zoomed,
          onInteractionEnd: (_) => setState(() {}),
          child: Center(
            child: MomentImage(
              // 缩略图先进来，原图下载完再替换（MomentImage 内部就是这个顺序）。
              uri: widget.images[index],
              original: true,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.zero,
              placeholder: const Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开朋友圈图片查看器。
Future<void> showMomentGallery(
  BuildContext context, {
  required List<Uri> images,
  required int index,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) =>
          MomentGalleryPage(images: images, initialIndex: index),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
