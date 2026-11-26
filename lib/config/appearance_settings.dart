// SPDX-FileCopyrightText: 2026 FluffyChatX Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/color_value.dart';
import 'package:material_ui/material_ui.dart';

/// Material You 的配色风格：同一颗种子色，派生出来的色板脾气不同。
///
/// 对应 Flutter 的 `DynamicSchemeVariant`，只暴露我们给用户看的那四种。
enum SchemeVariantOption {
  tonal('tonal', DynamicSchemeVariant.tonalSpot),
  vibrant('vibrant', DynamicSchemeVariant.vibrant),
  neutral('neutral', DynamicSchemeVariant.neutral),
  mono('mono', DynamicSchemeVariant.monochrome);

  final String id;
  final DynamicSchemeVariant variant;

  const SchemeVariantOption(this.id, this.variant);

  static SchemeVariantOption? fromId(String? id) {
    for (final option in SchemeVariantOption.values) {
      if (option.id == id) return option;
    }
    return null;
  }
}

/// 预设强调色（种子色）。选中一个就等于「用这颗颜色重新生成整套 MD3 色板」。
enum SeedColorOption {
  violet(0xFF6750A4),
  ocean(0xFF0061A4),
  teal(0xFF006A6A),
  matcha(0xFF4A6543),
  amber(0xFF7D5700),
  coral(0xFF8B4F45),
  rose(0xFF8E4585),
  graphite(0xFF4A4A4A);

  final int argb;

  const SeedColorOption(this.argb);

  Color get color => Color(argb);

  static SeedColorOption? fromColor(Color? color) {
    if (color == null) return null;
    for (final option in SeedColorOption.values) {
      if (option.argb == color.hexValue) return option;
    }
    return null;
  }
}
