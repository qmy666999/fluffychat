// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Material 3 Expressive 的动效令牌。
///
/// 这里只放「常量」和两个工具方法：时长统一从 [short] / [medium] / [long] 里挑，
/// 曲线统一用 [emphasized] / [emphasizedDecel] / [standard]，弹簧用
/// [spatialSpring] / [effectSpring]。零散的 `Duration(milliseconds: ...)` 只允许
/// 出现在这里，方便以后统一调速、也方便检查「单次动画不超过 600ms」这条红线。
class M3Motion {
  M3Motion._();

  /// 90dp 以内的小位移、按压反馈。
  static const Duration short = Duration(milliseconds: 150);

  /// 页面转场、菜单展开。
  static const Duration medium = Duration(milliseconds: 300);

  /// 最大的一次性动画（撤回破碎、删除收起）。
  static const Duration long = Duration(milliseconds: 450);

  /// 标准强调曲线：起步慢、结尾稳。
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 减速强调曲线：用于「从无到有」的入场。
  static const Curve emphasizedDecel = Cubic(0.05, 0.7, 0.1, 1.0);

  /// 标准曲线：用于尺寸/淡入淡出这类不强调方向的动画。
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 空间弹簧：按压回弹、面板弹出。
  static const SpringDescription spatialSpring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 28,
  );

  /// 效果弹簧：颜色/透明度这类不涉及空间的属性。
  static const SpringDescription effectSpring = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 40,
  );

  /// 系统开了「移除动画」（无障碍功能或开发者选项里动画缩放为 0）。
  static bool reduceMotionOf(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  /// 需要尊重系统的「移除动画」：开了就返回 [Duration.zero]，动画瞬间完成。
  static Duration of(BuildContext context, Duration duration) =>
      reduceMotionOf(context) ? Duration.zero : duration;
}
