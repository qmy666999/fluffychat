// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/config/appearance_settings.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 当前生效的外观设置。交给 [ThemeBuilder.builder] 去搭 MaterialApp。
class ThemeSettings {
  final ThemeMode themeMode;

  /// 强调色（种子色）。null 表示用 App 默认种子色。
  final Color? primaryColor;

  /// 是否跟随系统壁纸取色（Material You）。
  final bool useDynamicColor;

  /// 配色风格（同一颗种子色派生出不同脾气的色板）。
  final SchemeVariantOption variant;

  /// 系统给的两套动态色板；非空代表这台设备支持动态取色。
  final ColorScheme? dynamicLight;
  final ColorScheme? dynamicDark;

  const ThemeSettings({
    required this.themeMode,
    required this.primaryColor,
    required this.useDynamicColor,
    required this.variant,
    required this.dynamicLight,
    required this.dynamicDark,
  });

  bool get dynamicAvailable => dynamicLight != null || dynamicDark != null;

  /// 真正要用的动态色板：用户没开或者系统不支持时返回 null（退回种子色派生）。
  ColorScheme? dynamicSchemeFor(Brightness brightness) {
    if (!useDynamicColor) return null;
    return brightness == Brightness.light ? dynamicLight : dynamicDark;
  }
}

class ThemeBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, ThemeSettings settings) builder;

  final String themeModeSettingsKey;
  final String primaryColorSettingsKey;
  final String useDynamicColorSettingsKey;
  final String schemeVariantSettingsKey;

  const ThemeBuilder({
    required this.builder,
    this.themeModeSettingsKey = 'theme_mode',
    this.primaryColorSettingsKey = 'primary_color',
    this.useDynamicColorSettingsKey = 'use_dynamic_color',
    this.schemeVariantSettingsKey = 'scheme_variant',
    super.key,
  });

  @override
  State<ThemeBuilder> createState() => ThemeController();
}

class ThemeController extends State<ThemeBuilder> {
  SharedPreferences? _sharedPreferences;
  ThemeMode? _themeMode;
  Color? _primaryColor;
  bool _useDynamicColor = false;
  SchemeVariantOption _variant = SchemeVariantOption.tonal;

  ThemeMode get themeMode => _themeMode ?? ThemeMode.system;

  Color? get primaryColor => _primaryColor;

  bool get useDynamicColor => _useDynamicColor;

  SchemeVariantOption get variant => _variant;

  static ThemeController of(BuildContext context) =>
      Provider.of<ThemeController>(context, listen: false);

  Future<void> _loadData(_) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();

    final rawThemeMode = preferences.getString(widget.themeModeSettingsKey);
    final rawColor = preferences.getInt(widget.primaryColorSettingsKey);
    final rawDynamic = preferences.getBool(widget.useDynamicColorSettingsKey);
    final rawVariant = preferences.getString(widget.schemeVariantSettingsKey);

    setState(() {
      _themeMode = ThemeMode.values.singleWhereOrNull(
        (value) => value.name == rawThemeMode,
      );
      _primaryColor = rawColor == null ? null : Color(rawColor);
      _useDynamicColor = rawDynamic ?? false;
      _variant =
          SchemeVariantOption.fromId(rawVariant) ?? SchemeVariantOption.tonal;
    });
  }

  Future<void> setThemeMode(ThemeMode newThemeMode) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString(widget.themeModeSettingsKey, newThemeMode.name);
    setState(() {
      _themeMode = newThemeMode;
    });
  }

  Future<void> setPrimaryColor(Color? newPrimaryColor) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    if (newPrimaryColor == null) {
      await preferences.remove(widget.primaryColorSettingsKey);
    } else {
      await preferences.setInt(
        widget.primaryColorSettingsKey,
        newPrimaryColor.hexValue,
      );
    }
    setState(() {
      _primaryColor = newPrimaryColor;
    });
  }

  Future<void> setUseDynamicColor(bool value) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setBool(widget.useDynamicColorSettingsKey, value);
    setState(() {
      _useDynamicColor = value;
    });
  }

  Future<void> setVariant(SchemeVariantOption value) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString(widget.schemeVariantSettingsKey, value.id);
    setState(() {
      _variant = value;
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback(_loadData);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => this,
      child: DynamicColorBuilder(
        builder: (light, dark) => widget.builder(
          context,
          ThemeSettings(
            themeMode: themeMode,
            primaryColor: primaryColor,
            useDynamicColor: _useDynamicColor,
            variant: _variant,
            dynamicLight: light,
            dynamicDark: dark,
          ),
        ),
      ),
    );
  }
}
