// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:fluffychat/utils/diagnostics/diag_route_observer.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/matrix_sdk_extensions/event_extension.dart';

class ImageViewer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  const ImageViewer(
    this.event, {
    required this.outerContext,
    this.timeline,
    super.key,
  });

  @override
  ImageViewerController createState() => ImageViewerController();
}

class ImageViewerController extends State<ImageViewer> {
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    allEvents =
        widget.timeline?.events
            .where(
              (event) => {
                MessageTypes.Image,
                MessageTypes.Sticker,
                if (PlatformInfos.supportsVideoPlayer) MessageTypes.Video,
              }.contains(event.messageType),
            )
            .toList()
            .reversed
            .toList() ??
        [widget.event];
    var index = allEvents.indexWhere(
      (event) => event.eventId == widget.event.eventId,
    );
    if (index < 0) index = 0;
    pageController = PageController(initialPage: index);
  }

  late final PageController pageController;

  late final List<Event> allEvents;

  /// 打开时间与关闭方式，只用于 `close_image_viewer` 这条日志。
  late final DateTime _openedAt = DateTime.now();
  String _closeMethod = 'back';
  bool _closeLogged = false;

  /// 每张图一个变换控制器，用来判断当前是否被放大（放大时不要响应下拉关闭）。
  final Map<int, TransformationController> _transformationControllers = {};

  TransformationController transformControllerFor(int index) =>
      _transformationControllers.putIfAbsent(
        index,
        TransformationController.new,
      );

  double _dragOffset = 0;

  /// 手指向下拖动的距离，>0 时整页跟着下移。
  double get dragOffset => _dragOffset;

  Offset? _pointerStart;
  int _activePointers = 0;

  bool get _zoomed =>
      transformControllerFor(_index).value.getMaxScaleOnAxis() > 1.05;

  void onPointerDown(PointerDownEvent event) {
    _activePointers++;
    _pointerStart ??= event.position;
  }

  void onPointerMove(PointerMoveEvent event) {
    final start = _pointerStart;
    if (start == null || _activePointers != 1 || _zoomed) return;
    final delta = event.position - start;
    // 横向滑动交给 PageView 翻页，只有明显向下才跟随手指。
    if (delta.dy <= 0 || delta.dy < delta.dx.abs()) {
      if (_dragOffset != 0) setState(() => _dragOffset = 0);
      return;
    }
    setState(() => _dragOffset = delta.dy);
  }

  void onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 8);
    final start = _pointerStart;
    _pointerStart = null;
    if (start == null) return;
    final delta = event.position - start;
    final threshold = MediaQuery.sizeOf(context).height * 0.16;
    final shouldClose =
        _dragOffset > threshold ||
        (delta.dy > threshold && delta.dy > delta.dx.abs() * 1.5);
    if (shouldClose) {
      markClosed('drag');
      Navigator.of(context).maybePop();
      return;
    }
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  void onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 8);
    _pointerStart = null;
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  void onKeyEvent(KeyEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (canGoBack) prevImage();
        break;
      case LogicalKeyboardKey.arrowRight:
        if (canGoNext) nextImage();
        break;
    }
  }

  Future<void> prevImage() async {
    await pageController.previousPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> nextImage() async {
    await pageController.nextPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  int get _index => pageController.page?.toInt() ?? 0;

  Event get currentEvent => allEvents[_index];

  bool get canGoNext => _index < allEvents.length - 1;

  bool get canGoBack => _index > 0;

  /// Forward this image to another room.
  void forwardAction() => showScaffoldDialog(
    context: context,
    builder: (context) =>
        ShareScaffoldDialog(items: [ContentShareItem(currentEvent.content)]),
  );

  /// Save this file with a system call.
  void saveFileAction(BuildContext context) => currentEvent.saveFile(context);

  /// Save this file with a system call.
  void shareFileAction(BuildContext context) => currentEvent.shareFile(context);

  static const maxScaleFactor = 1.5;

  /// Go back if user swiped it away
  void onInteractionEnds(ScaleEndDetails endDetails) {
    if (PlatformInfos.usesTouchscreen == false) {
      if (endDetails.velocity.pixelsPerSecond.dy >
          MediaQuery.sizeOf(context).height * maxScaleFactor) {
        markClosed('fling');
        Navigator.of(context).maybePop();
      }
    }
  }

  /// 记录关闭方式（返回手势 / 点关闭 / 下拉），dispose 时一次性写日志。
  void markClosed(String method) {
    _closeMethod = method;
  }

  void _logClosed() {
    if (_closeLogged) return;
    _closeLogged = true;
    ActionLogger.I.log(
      'close_image_viewer',
      extra: {
        'event_id': widget.event.eventId,
        'room_id': widget.event.roomId,
        'method': _closeMethod,
        'duration_ms': DateTime.now().difference(_openedAt).inMilliseconds,
      },
      stack: DiagRouteObserver.stack,
    );
  }

  @override
  void dispose() {
    _logClosed();
    focusNode.dispose();
    pageController.dispose();
    for (final controller in _transformationControllers.values) {
      controller.dispose();
    }
    _transformationControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageViewerView(this);
}
