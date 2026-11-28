// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:flutter/widgets.dart';

/// 记录路由栈，供 [ActionLogger] 写进 `nav_push` / `nav_pop` / `back_gesture`。
///
/// 「返回到底关掉了谁」这类 bug 只有拿到**完整栈**才能一眼看出来，
/// 所以这里是全局唯一的栈快照来源。
class DiagRouteObserver extends NavigatorObserver {
  static final List<String> _stack = <String>[];

  /// 当前路由栈（从底到顶）。
  static List<String> get stack => List<String>.unmodifiable(_stack);

  static String? get current => _stack.isEmpty ? null : _stack.last;

  static String _nameOf(Route<dynamic>? route) {
    if (route == null) return '(none)';
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return route.settings.runtimeType.toString();
  }

  static void reset() => _stack.clear();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _nameOf(route);
    _stack.add(name);
    ActionLogger.I.log('nav_push', route: name, stack: stack);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final popped = _nameOf(route);
    _stack.remove(popped);
    ActionLogger.I.log('nav_pop', extra: {'popped': popped}, stack: stack);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final removed = _nameOf(route);
    _stack.remove(removed);
    ActionLogger.I.log('nav_remove', extra: {'removed': removed}, stack: stack);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final oldName = _nameOf(oldRoute);
    final newName = _nameOf(newRoute);
    if (_stack.isNotEmpty) _stack.remove(oldName);
    _stack.add(newName);
    ActionLogger.I.log(
      'nav_replace',
      route: newName,
      extra: {'replaced': oldName},
      stack: stack,
    );
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
