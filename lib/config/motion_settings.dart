// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 页面切换的动效风格。
///
/// `system` 就是 App 原本的样子（Android 上是 Zoom，iOS 上是 Cupertino 侧滑），
/// 其余几项是 Material 3 的动效规范。
enum MotionStyle {
  system,
  fadeThrough,
  sharedAxisX,
  sharedAxisY,
  zoom,
  containerTransform,
  none;

  static MotionStyle? fromName(String? name) {
    for (final style in MotionStyle.values) {
      if (style.name == name) return style;
    }
    return null;
  }
}

/// 动效相关的全局状态。
///
/// 只在启动时读一次 `SharedPreferences`（`main()` 里调 [load]），之后全部走内存，
/// 这样路由构造函数里取 style/speed 不需要 context、也不需要 await。
class MotionSettings {
  MotionSettings._();

  static const String styleKey = 'motion_style';
  static const String speedKey = 'motion_speed';

  static const double minSpeed = 0.5;
  static const double maxSpeed = 1.5;

  /// 基础时长：300ms 是 MD3 里最常用的中距离转场时长。
  static const Duration baseDuration = Duration(milliseconds: 300);

  static MotionStyle style = MotionStyle.system;
  static double speed = 1.0;

  static SharedPreferences? _store;

  static void load(SharedPreferences store) {
    _store = store;
    style =
        MotionStyle.fromName(store.getString(styleKey)) ?? MotionStyle.system;
    speed = (store.getDouble(speedKey) ?? 1.0).clamp(minSpeed, maxSpeed);
  }

  static Future<void> setStyle(MotionStyle newStyle) async {
    style = newStyle;
    await _store?.setString(styleKey, newStyle.name);
  }

  static Future<void> setSpeed(double newSpeed) async {
    speed = newSpeed.clamp(minSpeed, maxSpeed);
    await _store?.setDouble(speedKey, speed);
  }

  /// 把基础时长按「动画速度」缩放：0.5x 更慢，1.5x 更快。
  static Duration scaled(Duration base) => Duration(
    milliseconds: (base.inMilliseconds / speed).round().clamp(50, 2000),
  );

  /// 系统开了「移除动画」（无障碍 / 开发者选项里的动画缩放 0）时，一律瞬移。
  static bool get reduceMotion => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  /// 真正生效的风格：
  /// - 系统要求减少动效 → 无动画
  /// - tab 之间切换不用纵向共享轴（四个 tab 是平级页面，上下方向会晃得像压栈）
  static MotionStyle effectiveStyle({required bool isTab}) {
    final chosen = style;
    if (reduceMotion) return MotionStyle.none;
    if (isTab && chosen == MotionStyle.sharedAxisY) {
      return MotionStyle.fadeThrough;
    }
    return chosen;
  }
}
