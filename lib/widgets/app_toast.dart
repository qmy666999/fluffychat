// SPDX-FileCopyrightText: 2026 FluffyChatX contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show Logs;

/// 胶囊轻提示。
///
/// 以前全 App 用的是 SnackBar：白色通栏、贴底、默认 4 秒，会把输入栏盖住。
/// 这里换成微信那种居中的小黑胶囊：
///
/// * 只包住文字，最大 `屏宽 * 0.7`；
/// * 圆角等于高度一半（纯胶囊），水平内边距 16、垂直 8；
/// * 位置贴着输入栏 / 底部导航栏上沿再往上 12dp，两者都没有时距屏幕底 80dp；
/// * 淡入 + 上浮 8dp 120ms，淡出 200ms，默认停留 1.5 秒（错误 2.5 秒）；
/// * [IgnorePointer] 包住，显示期间下面照样能点；
/// * 同一时间只有一条，新的直接顶掉旧的，不排队。
///
/// 它挂在根 Overlay 上，所以**不需要页面传 BuildContext**——这样也不会在异步流程里
/// 触发 `use_build_context_synchronously`。位置锚点由聊天输入栏、底部导航栏自己注册。
///
/// 注意：这只是「轻提示」。确认弹窗（Dialog / BottomSheet）、表单里的红字错误、
/// 加载态、上传进度条都不要换成它。
class AppToast {
  AppToast._();

  /// 默认停留时长。
  static const Duration defaultDuration = Duration(milliseconds: 1500);

  /// 错误类提示的停留时长。
  static const Duration errorDuration = Duration(milliseconds: 2500);

  static const Duration _inDuration = Duration(milliseconds: 120);
  static const Duration _outDuration = Duration(milliseconds: 200);

  static OverlayEntry? _entry;
  static Timer? _timer;
  static _ToastState? _state;

  /// 聊天页输入栏注册的锚点（由 `ChatInputRow` 在 initState 里设置）。
  static GlobalKey? composerKey;

  /// 底部四项导航栏注册的锚点（由 `ChatListBottomBar` 设置）。
  static GlobalKey? bottomBarKey;

  /// 根 Navigator 的 Overlay。
  ///
  /// 注意：不能用 `Overlay.maybeOf(navigatorKey.currentContext)`——那个 context
  /// 是 Navigator 自己，Overlay 是它的**子节点**，向上查找永远拿不到，于是提示
  /// 全部静默丢掉（1.19.0 的 bug）。这里直接取 `NavigatorState.overlay`。
  static OverlayState? get _rootOverlay =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentState?.overlay;

  /// 弹一条文字提示。
  static void show(
    String text, {
    bool isError = false,
    AppToastAction? action,
  }) {
    if (text.trim().isEmpty) return;
    // 诊断日志：提示本身就是「用户到底看到没看到」的证据。
    ActionLogger.I.log('toast', extra: {'text': text, 'error': isError});
    _show(
      child: _ToastText(text: text, action: action),
      duration: isError ? errorDuration : defaultDuration,
    );
  }

  /// 弹一条自定义内容的提示（例如带转圈的进度条），一直显示到 [dismiss]。
  static AppToastHandle showCustom(Widget child, {Duration? duration}) {
    _show(child: child, duration: duration);
    return const AppToastHandle._();
  }

  static void _show({required Widget child, Duration? duration}) {
    final overlay = _rootOverlay;
    if (overlay == null) {
      Logs().w('[AppToast] no root overlay, dropped');
      return;
    }

    // 只保留一条：新的直接顶掉旧的。
    _dismiss(immediate: true);

    final state = _ToastState();
    final entry = OverlayEntry(
      builder: (overlayContext) {
        final bottom = _anchorBottom(overlayContext);
        return Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          child: IgnorePointer(
            child: Center(
              child: _ToastBubble(state: state, child: child),
            ),
          ),
        );
      },
    );
    _state = state;
    _entry = entry;
    overlay.insert(entry);
    // 下一帧再点亮，保证进场动画从隐藏状态开始。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_state != state || !state.mounted) return;
      state.visible = true;
    });

    if (duration != null) {
      _timer = Timer(duration, () {
        if (_state != state) return;
        _dismiss();
      });
    }
  }

  /// 收起当前提示。默认先播 200ms 淡出再移除。
  static void _dismiss({bool immediate = false}) {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    final state = _state;
    _entry = null;
    _state = null;
    if (entry == null) return;
    if (immediate || state == null) {
      if (entry.mounted) entry.remove();
      entry.dispose();
      return;
    }
    state.visible = false;
    Timer(_outDuration + const Duration(milliseconds: 20), () {
      if (entry.mounted) entry.remove();
      entry.dispose();
    });
  }

  /// 立刻收起（例如上传完成、页面销毁时）。
  static void dismiss() => _dismiss(immediate: true);

  static double _anchorBottom(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = size.height;

    double? topOf(GlobalKey? key) {
      final renderObject = key?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return null;
      if (!renderObject.attached || !renderObject.hasSize) return null;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      if (top <= 0 || top > height) return null;
      return top;
    }

    final maxBottom = height - 200;
    final minBottom = maxBottom > 60 ? 60.0 : 0.0;

    double clampBottom(double value) =>
        value.clamp(minBottom, maxBottom > minBottom ? maxBottom : minBottom);

    final composerTop = topOf(composerKey);
    if (composerTop != null) {
      final bottom = height - composerTop + 12;
      Logs().v('[AppToast] bottom=$bottom composer=$composerTop');
      return clampBottom(bottom);
    }
    final barTop = topOf(bottomBarKey);
    if (barTop != null) {
      final bottom = height - barTop + 12;
      Logs().v('[AppToast] bottom=$bottom bottombar=$barTop');
      return clampBottom(bottom);
    }
    // 没有输入栏也没有底部导航栏：距屏幕底 80dp。
    Logs().v('[AppToast] bottom=80 (no anchor)');
    return clampBottom(80);
  }

  /// 提示条上那个按钮（例如「返回通话」）。
  static void runAction(AppToastAction action) {
    _dismiss(immediate: true);
    action.onPressed();
  }
}

/// 提示条上的可选按钮（例如「返回通话」）。
class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// [AppToast.showCustom] 返回的句柄。
class AppToastHandle {
  const AppToastHandle._();

  void dismiss() => AppToast.dismiss();
}

class _ToastState extends ChangeNotifier {
  bool _visible = false;
  bool _disposed = false;

  bool get visible => _visible;
  bool get mounted => !_disposed;

  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _ToastBubble extends StatelessWidget {
  const _ToastBubble({required this.state, required this.child});

  final _ToastState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? theme.colorScheme.inverseSurface
        : Colors.black.withValues(alpha: 0.78);
    final foreground = isDark
        ? theme.colorScheme.onInverseSurface
        : Colors.white;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.7;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final visible = state.visible;
        return AnimatedSlide(
          offset: visible || reduceMotion ? Offset.zero : const Offset(0, 0.35),
          duration: reduceMotion
              ? Duration.zero
              : (visible ? AppToast._inDuration : AppToast._outDuration),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: reduceMotion
                ? Duration.zero
                : (visible ? AppToast._inDuration : AppToast._outDuration),
            curve: Curves.easeOut,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.antiAlias,
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    height: 1.3,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToastText extends StatelessWidget {
  const _ToastText({required this.text, this.action});

  final String text;
  final AppToastAction? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    if (action == null) {
      return Text(text, textAlign: TextAlign.center);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(text, textAlign: TextAlign.center)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => AppToast.runAction(action),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: DefaultTextStyle.of(context).style.color,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(action.label),
        ),
      ],
    );
  }
}
