// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/state_message.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/app_config.dart';
import '../../config/appearance_settings.dart';
import '../../config/motion_settings.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SegmentedButton<ThemeMode>(
                selected: {controller.currentTheme},
                onSelectionChanged: (selected) =>
                    controller.switchTheme(selected.single),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(L10n.of(context).lightTheme),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(L10n.of(context).darkTheme),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(L10n.of(context).systemTheme),
                    icon: const Icon(Icons.auto_mode_outlined),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).setColorTheme,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DynamicColorBuilder(
              builder: (light, dark) {
                final dynamicAvailable = light != null || dark != null;
                final dynamicOn =
                    controller.useDynamicColor && dynamicAvailable;
                return Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.palette_outlined),
                      title: Text(L10n.of(context).useDynamicColor),
                      subtitle: Text(
                        dynamicAvailable
                            ? L10n.of(context).useDynamicColorHint
                            : L10n.of(context).useDynamicColorUnavailable,
                      ),
                      value: dynamicOn,
                      onChanged: dynamicAvailable
                          ? controller.setUseDynamicColor
                          : null,
                    ),
                    // 从壁纸取色时，强调色和配色风格都不起作用，所以整块置灰。
                    Opacity(
                      opacity: dynamicOn ? 0.4 : 1,
                      child: IgnorePointer(
                        ignoring: dynamicOn,
                        child: Column(
                          crossAxisAlignment: .stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Text(
                                L10n.of(context).accentColor,
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 64,
                                  ),
                              itemCount: SeedColorOption.values.length,
                              itemBuilder: (context, i) {
                                final option = SeedColorOption.values[i];
                                final selected =
                                    controller.currentColor?.hexValue ==
                                    option.argb;
                                return Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Tooltip(
                                    message: _seedLabel(context, option),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                        colorPickerSize,
                                      ),
                                      onTap: () =>
                                          controller.setChatColor(option.color),
                                      child: Material(
                                        color: option.color,
                                        elevation: 6,
                                        borderRadius: BorderRadius.circular(
                                          colorPickerSize,
                                        ),
                                        child: SizedBox(
                                          width: colorPickerSize,
                                          height: colorPickerSize,
                                          child: selected
                                              ? Center(
                                                  child: Icon(
                                                    Icons.check,
                                                    size: 16,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onPrimary,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Text(
                                L10n.of(context).schemeVariant,
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: SegmentedButton<SchemeVariantOption>(
                                selected: {controller.schemeVariant},
                                onSelectionChanged: (selected) => controller
                                    .setSchemeVariant(selected.single),
                                segments: [
                                  for (final option
                                      in SchemeVariantOption.values)
                                    ButtonSegment(
                                      value: option,
                                      label: Text(
                                        _variantLabel(context, option),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).messagesStyle,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            StreamBuilder(
              stream: client.onSync.stream.where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) =>
                          accountData.type ==
                          ApplicationAccountConfigExtension.accountDataKey,
                    ) ??
                    false,
              ),
              builder: (context, snapshot) {
                final accountConfig = client.applicationAccountConfig;

                return Column(
                  mainAxisSize: .min,
                  children: [
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          AppSettings.fontSizeFactor.value,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        decoration: const BoxDecoration(),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (accountConfig.wallpaperUrl != null)
                              Opacity(
                                opacity: controller.wallpaperOpacity,
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: controller.wallpaperBlur,
                                    sigmaY: controller.wallpaperBlur,
                                  ),
                                  child: MxcImage(
                                    key: ValueKey(accountConfig.wallpaperUrl),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    isThumbnail: true,
                                    width: FluffyThemes.columnWidth * 2,
                                    height: 212,
                                  ),
                                ),
                              ),
                            Column(
                              mainAxisSize: .min,
                              children: [
                                const SizedBox(height: 16),
                                StateMessage(
                                  Event(
                                    eventId: 'style_dummy',
                                    room: Room(
                                      id: '!style_dummy',
                                      client: client,
                                    ),
                                    content: {'membership': 'join'},
                                    type: EventTypes.RoomMember,
                                    senderId: client.userID!,
                                    originServerTs: DateTime.now(),
                                    stateKey: client.userID,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: 12 + 12 + Avatar.defaultSize,
                                    right: 12,
                                    top: accountConfig.wallpaperUrl == null
                                        ? 0
                                        : 12,
                                    bottom: 12,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.bubbleColor,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                                        style: TextStyle(
                                          color: theme.onBubbleColor,
                                          fontSize: AppConfig.messageFontSize,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: 12,
                                      left: 12,
                                      top: accountConfig.wallpaperUrl == null
                                          ? 0
                                          : 12,
                                      bottom: 12,
                                    ),
                                    child: Material(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Lorem ipsum dolor sit amet',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontSize: AppConfig.messageFontSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: controller.setWallpaper,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(L10n.of(context).setWallpaper),
                      ),
                      trailing: accountConfig.wallpaperUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              color: theme.colorScheme.error,
                              onPressed: controller.deleteChatWallpaper,
                            ),
                    ),
                    if (accountConfig.wallpaperUrl != null) ...[
                      ListTile(title: Text(L10n.of(context).opacity)),
                      Slider.adaptive(
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperOpacity,
                        onChanged: controller.updateWallpaperOpacity,
                        onChangeEnd: controller.saveWallpaperOpacity,
                      ),
                      ListTile(title: Text(L10n.of(context).blur)),
                      Slider.adaptive(
                        min: 0.0,
                        max: 10.0,
                        divisions: 10,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperBlur,
                        onChanged: controller.updateWallpaperBlur,
                        onChangeEnd: controller.saveWallpaperBlur,
                      ),
                    ],
                  ],
                );
              },
            ),
            ListTile(
              title: Text(L10n.of(context).fontSize),
              trailing: Text('× ${AppSettings.fontSizeFactor.value}'),
            ),
            Slider.adaptive(
              min: 0.5,
              max: 2.5,
              divisions: 20,
              value: AppSettings.fontSizeFactor.value,
              semanticFormatterCallback: (d) => d.toString(),
              onChanged: controller.changeFontSizeFactor,
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).motion,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final style in MotionStyle.values)
              ListTile(
                leading: Icon(
                  controller.motionStyle == style
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: controller.motionStyle == style
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(_motionLabel(context, style)),
                onTap: () => controller.setMotionStyle(style),
              ),
            if (MotionSettings.reduceMotion)
              ListTile(
                leading: const Icon(Icons.accessibility_new_outlined),
                subtitle: Text(L10n.of(context).motionReducedHint),
              ),
            ListTile(
              title: Text(L10n.of(context).motionSpeed),
              trailing: Text('× ${controller.motionSpeed.toStringAsFixed(2)}'),
            ),
            Slider.adaptive(
              min: MotionSettings.minSpeed,
              max: MotionSettings.maxSpeed,
              divisions: 4,
              value: controller.motionSpeed,
              label: '× ${controller.motionSpeed.toStringAsFixed(2)}',
              semanticFormatterCallback: (d) => d.toString(),
              onChanged: controller.previewMotionSpeed,
              onChangeEnd: controller.saveMotionSpeed,
            ),
          ],
        ),
      ),
    );
  }
}

String _seedLabel(BuildContext context, SeedColorOption option) {
  final l10n = L10n.of(context);
  return switch (option) {
    SeedColorOption.violet => l10n.seedViolet,
    SeedColorOption.ocean => l10n.seedOcean,
    SeedColorOption.teal => l10n.seedTeal,
    SeedColorOption.matcha => l10n.seedMatcha,
    SeedColorOption.amber => l10n.seedAmber,
    SeedColorOption.coral => l10n.seedCoral,
    SeedColorOption.rose => l10n.seedRose,
    SeedColorOption.graphite => l10n.seedGraphite,
  };
}

String _variantLabel(BuildContext context, SchemeVariantOption option) {
  final l10n = L10n.of(context);
  return switch (option) {
    SchemeVariantOption.tonal => l10n.variantTonal,
    SchemeVariantOption.vibrant => l10n.variantVibrant,
    SchemeVariantOption.neutral => l10n.variantNeutral,
    SchemeVariantOption.mono => l10n.variantMono,
  };
}

String _motionLabel(BuildContext context, MotionStyle style) {
  final l10n = L10n.of(context);
  return switch (style) {
    MotionStyle.system => l10n.motionStyleSystem,
    MotionStyle.fadeThrough => l10n.motionFadeThrough,
    MotionStyle.sharedAxisX => l10n.motionSharedAxisX,
    MotionStyle.sharedAxisY => l10n.motionSharedAxisY,
    MotionStyle.zoom => l10n.motionZoom,
    MotionStyle.containerTransform => l10n.motionContainerTransform,
    MotionStyle.none => l10n.motionNone,
  };
}
