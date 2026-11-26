// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

/// 微信式「设置」：一层只放分组入口，具体开关都在二级页里。
class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: ListView(
          key: const Key('SettingsListViewContent'),
          children: <Widget>[
            _ProfileHeader(controller: controller),
            _SettingsEntry(
              icon: Icons.account_circle_outlined,
              title: l10n.settingsAccountSecurity,
              route: '/rooms/settings/wechat-account',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.notifications_outlined,
              title: l10n.settingsNewMessage,
              route: '/rooms/settings/wechat-notifications',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.forum_outlined,
              title: l10n.chat,
              route: '/rooms/settings/wechat-chat',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.settings_outlined,
              title: l10n.settingsGeneral,
              route: '/rooms/settings/wechat-general',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.lock_outline,
              title: l10n.privacy,
              route: '/rooms/settings/wechat-privacy',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.group_outlined,
              title: l10n.settingsFriendPermission,
              route: '/rooms/settings/wechat-friend-permission',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.verified_user_outlined,
              title: l10n.settingsPersonalInfo,
              route: '/rooms/settings/wechat-personal-info',
              activeRoute: activeRoute,
            ),
            Divider(color: theme.dividerColor),
            _SettingsEntry(
              icon: Icons.info_outline_rounded,
              title: l10n.about,
              route: '/rooms/settings/wechat-about',
              activeRoute: activeRoute,
            ),
            _SettingsEntry(
              icon: Icons.help_outline,
              title: l10n.settingsHelp,
              route: '/rooms/settings/wechat-help',
              activeRoute: activeRoute,
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: Text(l10n.logout),
              onTap: controller.logoutAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String route;
  final String activeRoute;

  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.route,
    required this.activeRoute,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      tileColor: activeRoute.startsWith(route)
          ? theme.colorScheme.surfaceContainerHigh
          : null,
      onTap: () => context.go(route),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final SettingsController controller;

  const _ProfileHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return FutureBuilder<Profile>(
      future: controller.profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final avatar = profile?.avatarUrl;
        final mxid = Matrix.of(context).client.userID ?? l10n.user;
        final displayname = profile?.displayName ?? mxid.localpart ?? mxid;
        final avatarActions = [
          if (PlatformInfos.isMobile) AvatarAction.camera,
          AvatarAction.file,
          if (avatar != null) AvatarAction.remove,
        ];
        final avatarButtonStyle = IconButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          shadowColor: theme.colorScheme.shadow,
          elevation: 2,
        );
        return Column(
          crossAxisAlignment: .center,
          mainAxisSize: .min,
          children: [
            const SizedBox(height: 16),
            Stack(
              children: [
                Avatar(
                  mxContent: avatar,
                  name: displayname,
                  size: Avatar.defaultSize * 2.5,
                  animated: true,
                  onTap: avatar != null
                      ? () => showDialog(
                          context: context,
                          builder: (_) => MxcImageViewer(avatar),
                        )
                      : null,
                ),
                if (profile != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: avatarActions.length == 1
                        ? IconButton(
                            style: avatarButtonStyle,
                            tooltip: l10n.changeYourAvatar,
                            onPressed: () => controller.setAvatarAction(
                              avatarActions.single,
                            ),
                            icon: const Icon(Icons.camera_alt_outlined),
                          )
                        : PopupMenuButton<AvatarAction>(
                            style: avatarButtonStyle,
                            tooltip: l10n.changeYourAvatar,
                            onSelected: controller.setAvatarAction,
                            icon: const Icon(Icons.camera_alt_outlined),
                            itemBuilder: (context) => [
                              for (final action in avatarActions)
                                PopupMenuItem(
                                  value: action,
                                  child: Row(
                                    mainAxisSize: .min,
                                    spacing: 12,
                                    children: [
                                      Icon(switch (action) {
                                        AvatarAction.camera =>
                                          Icons.camera_alt_outlined,
                                        AvatarAction.file =>
                                          Icons.photo_outlined,
                                        AvatarAction.remove =>
                                          Icons.delete_outlined,
                                      }),
                                      Text(switch (action) {
                                        AvatarAction.camera => l10n.openCamera,
                                        AvatarAction.file => l10n.openGallery,
                                        AvatarAction.remove =>
                                          l10n.removeYourAvatar,
                                      }),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: controller.setDisplaynameAction,
              icon: const Icon(Icons.edit_outlined, size: 16),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                iconColor: theme.colorScheme.onSurface,
              ),
              label: Text(
                displayname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            TextButton(
              onPressed: () => FluffyShare.share(mxid, context),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.secondary,
                iconColor: theme.colorScheme.secondary,
              ),
              child: Text(mxid, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 8),
            Divider(color: theme.dividerColor),
          ],
        );
      },
    );
  }
}
