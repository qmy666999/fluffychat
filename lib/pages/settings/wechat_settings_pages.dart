// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/app_settings_launcher.dart';
import 'package:fluffychat/utils/updates/app_update_service.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'server_endpoint_tile.dart';
import 'update_check_tile.dart';

/// 微信式「设置」的二级页集合。
///
/// 第一版只把入口和下钻结构摆对：能用的开关都真的能用（存 SharedPreferences
/// 或走 Matrix 设置），暂不支持的项给出明确提示，不做假开关。

class SettingsNotificationsPage extends StatefulWidget {
  const SettingsNotificationsPage({super.key});

  @override
  State<SettingsNotificationsPage> createState() =>
      _SettingsNotificationsPageState();
}

class _SettingsNotificationsPageState extends State<SettingsNotificationsPage> {
  bool _openingSettings = false;

  Future<void> _openSystemNotificationSettings() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    final opened = await openAppNotificationSettings();
    if (!mounted) return;
    setState(() => _openingSettings = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).openNotificationSettingsFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return _WechatSettingsScaffold(
      title: l10n.settingsNewMessage,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.keepAliveTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.keepAliveHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _openingSettings
                        ? null
                        : _openSystemNotificationSettings,
                    child: Text(l10n.openSystemNotificationSettings),
                  ),
                ),
              ],
            ),
          ),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.notifyReceive),
          value: WechatPrefs.notifyReceive,
          onChanged: (value) => setState(() {
            WechatPrefs.setNotifyReceive(value);
          }),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.notifyDetail),
          value: WechatPrefs.notifyDetail,
          onChanged: (value) => setState(() {
            WechatPrefs.setNotifyDetail(value);
          }),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.notifyCall),
          value: WechatPrefs.notifyCall,
          onChanged: (value) => setState(() {
            WechatPrefs.setNotifyCall(value);
          }),
        ),
        ListTile(
          title: Text(l10n.notifySystem),
          subtitle: Text(l10n.notifyReceive),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/rooms/settings/notifications'),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.notifySound),
          value: WechatPrefs.notifySound,
          onChanged: (value) => setState(() {
            WechatPrefs.setNotifySound(value);
          }),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.notifyRingtone),
          value: WechatPrefs.notifyRingtone,
          onChanged: (value) => setState(() {
            WechatPrefs.setNotifyRingtone(value);
          }),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.notifyVibrate),
          value: WechatPrefs.notifyVibrate,
          onChanged: (value) => setState(() {
            WechatPrefs.setNotifyVibrate(value);
          }),
        ),
      ],
    );
  }
}

class SettingsChatPage extends StatefulWidget {
  const SettingsChatPage({super.key});

  @override
  State<SettingsChatPage> createState() => _SettingsChatPageState();
}

class _SettingsChatPageState extends State<SettingsChatPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _WechatSettingsScaffold(
      title: l10n.chat,
      children: [
        SwitchListTile.adaptive(
          title: Text(l10n.chatEarpiece),
          value: WechatPrefs.chatEarpiece,
          onChanged: (value) => setState(() {
            WechatPrefs.setChatEarpiece(value);
          }),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.chatEnterToSend),
          value: WechatPrefs.chatEnterToSend,
          onChanged: (value) => setState(() {
            WechatPrefs.setChatEnterToSend(value);
          }),
        ),
        ListTile(
          title: Text(l10n.chatBackupMigrate),
          subtitle: Text(l10n.featureComingSoon),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon(context),
        ),
        ListTile(
          title: Text(l10n.fontSize),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/rooms/settings/style'),
        ),
      ],
    );
  }
}

class SettingsGeneralPage extends StatefulWidget {
  const SettingsGeneralPage({super.key});

  @override
  State<SettingsGeneralPage> createState() => _SettingsGeneralPageState();
}

class _SettingsGeneralPageState extends State<SettingsGeneralPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _WechatSettingsScaffold(
      title: l10n.settingsGeneral,
      children: [
        ListTile(
          title: Text(l10n.generalDarkMode),
          subtitle: Text(l10n.changeTheme),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/rooms/settings/style'),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.generalLandscape),
          value: WechatPrefs.landscapeMode,
          onChanged: (value) => setState(() {
            WechatPrefs.setLandscapeMode(value);
          }),
        ),
        ListTile(
          title: Text(l10n.generalLanguage),
          subtitle: Text(l10n.featureComingSoon),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon(context),
        ),
        ListTile(
          title: Text(l10n.fontSize),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/rooms/settings/style'),
        ),
        ListTile(
          title: Text(l10n.generalMedia),
          subtitle: Text(l10n.featureComingSoon),
          onTap: () => _showComingSoon(context),
        ),
        ListTile(
          title: Text(l10n.discoverManage),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/rooms/settings/discover-manage'),
        ),
        ListTile(
          title: Text(l10n.storageSpace),
          subtitle: Text(l10n.featureComingSoon),
          onTap: () => _showComingSoon(context),
        ),
      ],
    );
  }
}

class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    return _WechatSettingsScaffold(
      title: l10n.about,
      children: [
        FutureBuilder<String>(
          future: AppUpdateService.currentVersionLabel(),
          builder: (context, snapshot) => ListTile(
            title: Text(l10n.versionNumber),
            trailing: Text(snapshot.data ?? ''),
          ),
        ),
        const UpdateCheckTile(),
        const ServerEndpointTile(),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(
            l10n.aboutHomeserver(client.userID?.domain ?? 'homeserver'),
          ),
          onTap: () => context.go('/rooms/settings/homeserver'),
        ),
        ListTile(
          leading: const Icon(Icons.code_outlined),
          title: Text(l10n.sourceCode),
          onTap: () =>
              launchUrlString('https://github.com/qmy666999/fluffychat'),
        ),
      ],
    );
  }
}

class SettingsAccountPage extends StatelessWidget {
  const SettingsAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final userId = client.userID ?? '';
    return _WechatSettingsScaffold(
      title: l10n.settingsAccountSecurity,
      children: [
        ListTile(
          title: Text(l10n.wechatId),
          subtitle: Text(userId),
          onTap: () => Clipboard.setData(ClipboardData(text: userId)),
        ),
        ListTile(
          leading: const Icon(Icons.devices_outlined),
          title: Text(l10n.devices),
          onTap: () => context.go('/rooms/settings/devices'),
        ),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(l10n.security),
          onTap: () => context.go('/rooms/settings/security'),
        ),
        ListTile(
          leading: const Icon(Icons.password_outlined),
          title: Text(l10n.password),
          onTap: () => context.go('/rooms/settings/password'),
        ),
        ListTile(
          leading: const Icon(Icons.person_add_outlined),
          title: Text(l10n.addAccount),
          onTap: () => context.go('/rooms/settings/addaccount'),
        ),
      ],
    );
  }
}

class SettingsPrivacyPage extends StatelessWidget {
  const SettingsPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _WechatSettingsScaffold(
      title: l10n.privacy,
      children: [
        ListTile(
          leading: const Icon(Icons.block_outlined),
          title: Text(l10n.blockedUsers),
          onTap: () => context.go('/rooms/settings/ignorelist'),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.privacy),
          onTap: () => launchUrlString(AppSettings.privacyPolicy.value),
        ),
      ],
    );
  }
}

class SettingsFriendPermissionPage extends StatelessWidget {
  const SettingsFriendPermissionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _WechatSettingsScaffold(
      title: l10n.settingsFriendPermission,
      children: [
        ListTile(
          title: Text(l10n.moments),
          subtitle: Text(l10n.featureComingSoon),
          onTap: () => _showComingSoon(context),
        ),
        ListTile(
          title: Text(l10n.addFriend),
          subtitle: Text(l10n.featureComingSoon),
          onTap: () => _showComingSoon(context),
        ),
      ],
    );
  }
}

class SettingsPersonalInfoPage extends StatelessWidget {
  const SettingsPersonalInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final userId = client.userID ?? '';
    final profile = client.fetchOwnProfile();
    return _WechatSettingsScaffold(
      title: l10n.settingsPersonalInfo,
      children: [
        FutureBuilder<Profile>(
          future: profile,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final name = data?.displayName ?? userId;
            return ListTile(
              leading: Avatar(mxContent: data?.avatarUrl, name: name, size: 44),
              title: Text(name),
              onTap: () => context.go('/rooms/settings/style'),
            );
          },
        ),
        ListTile(
          title: Text(l10n.qrCode),
          leading: const Icon(Icons.qr_code_2),
          onTap: () => showDialog(
            context: context,
            builder: (context) => AlertDialog(
              content: SizedBox(
                width: 220,
                height: 220,
                child: PrettyQrView.data(data: 'https://matrix.to/#/$userId'),
              ),
            ),
          ),
        ),
        ListTile(
          title: Text(l10n.wechatId),
          subtitle: Text(userId),
          onTap: () => Clipboard.setData(ClipboardData(text: userId)),
        ),
      ],
    );
  }
}

class SettingsHelpPage extends StatelessWidget {
  const SettingsHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _WechatSettingsScaffold(
      title: l10n.settingsHelp,
      children: [
        ListTile(
          title: Text(l10n.featureComingSoon),
          onTap: () => _showComingSoon(context),
        ),
        ListTile(
          leading: const Icon(Icons.code_outlined),
          title: Text(l10n.sourceCode),
          onTap: () =>
              launchUrlString('https://github.com/qmy666999/fluffychat'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _WechatSettingsScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _WechatSettingsScaffold({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(children: children),
    );
  }
}

void _showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(L10n.of(context).featureComingSoon)));
}
