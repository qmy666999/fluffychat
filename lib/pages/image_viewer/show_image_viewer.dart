// SPDX-FileCopyrightText: 2026 FluffyChatX contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 统一的「点开看大图」入口。
///
/// 以前这里是 `showDialog`：对话框虽然也是个路由，但在 GoRouter 应用里
/// 返回手势偶尔会把**底下的聊天页**先弹掉、对话框反而留在屏幕上
/// （Bug 报告「图片预览返回顺序错乱」）。改成真正的全屏路由之后，
/// 预览页就是路由栈顶，返回键/右滑必然先关它。
///
/// 所有入口（聊天图片、视频封面、搜索里的图片、头像）都应该走这里，
/// 不要各写一套 `showDialog`。
Future<void> showImageViewer(
  BuildContext context, {
  required Event event,
  Timeline? timeline,
  BuildContext? outerContext,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return navigator.push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      fullscreenDialog: true,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => ImageViewer(
        event,
        timeline: timeline,
        outerContext: outerContext ?? context,
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

/// 头像/表情这类按 mxc 内容打开的图片查看器，同样走路由。
Future<void> showMxcImageViewer(BuildContext context, Uri? mxContent) {
  if (mxContent == null) return Future.value();
  final navigator = Navigator.of(context, rootNavigator: true);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return navigator.push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      fullscreenDialog: true,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => MxcImageViewer(mxContent),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}
