// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/app_settings_launcher.dart';
import 'package:fluffychat/utils/diagnostics/action_logger.dart';
import 'package:fluffychat/utils/diagnostics/diag_exporter.dart';
import 'package:fluffychat/utils/notifications/app_notifications.dart';
import 'package:fluffychat/utils/notifications/notification_log.dart';
import 'package:fluffychat/utils/updates/app_update_service.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_toast.dart';
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
  bool _sendingTest = false;

  Future<void> _sendTestNotification() async {
    if (_sendingTest) return;
    setState(() => _sendingTest = true);
    final l10n = L10n.of(context);
    final ok = await AppNotifications.showTestNotification(
      Matrix.of(context).localNotifications,
      l10n,
    );
    if (!mounted) return;
    setState(() => _sendingTest = false);
    if (!ok) {
      AppToast.show(l10n.notificationTestBlocked);
    }
  }

  Future<void> _openSystemNotificationSettings() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    final opened = await openAppNotificationSettings();
    if (!mounted) return;
    setState(() => _openingSettings = false);
    if (!opened) {
      AppToast.show(L10n.of(context).openNotificationSettingsFailed);
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
        ListTile(
          leading: const Icon(Icons.notification_add_outlined),
          title: Text(l10n.notificationTest),
          subtitle: Text(l10n.notificationTestBody),
          trailing: _sendingTest
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _sendingTest ? null : _sendTestNotification,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(color: theme.colorScheme.outlineVariant),
        ),
        const _NotificationDiagnosticsTile(),
      ],
    );
  }
}

/// 「通知诊断」：把最近 60 条 [NotificationLog] 显示出来。
///
/// 没有 adb 的时候，复现一次消息、然后截图这里，就能看出通知是卡在
/// 「不在前台 / 自己发的 / 被推送规则过滤 / show() 失败」哪一步。
class _NotificationDiagnosticsTile extends StatelessWidget {
  const _NotificationDiagnosticsTile();

  Future<void> _copy(BuildContext context) async {
    final l10n = L10n.of(context);
    final entries = NotificationLog.entries;
    await Clipboard.setData(
      ClipboardData(
        text: entries.isEmpty
            ? l10n.notificationDiagnosticsEmpty
            : entries.join('\n'),
      ),
    );
    if (!context.mounted) return;
    AppToast.show(l10n.copy);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: NotificationLog.revision,
      builder: (context, _, _) {
        final entries = NotificationLog.entries;
        return ExpansionTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(l10n.notificationDiagnostics),
          subtitle: Text(
            entries.isEmpty
                ? l10n.notificationDiagnosticsHint
                : '${entries.length}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.notificationDiagnosticsHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: entries.isEmpty
                  ? Text(
                      l10n.notificationDiagnosticsEmpty,
                      style: theme.textTheme.bodySmall,
                    )
                  : SelectableText(
                      entries.join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: entries.isEmpty ? null : () => _copy(context),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l10n.copy),
                ),
                TextButton.icon(
                  onPressed: entries.isEmpty ? null : NotificationLog.clear,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(l10n.clear),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SettingsChatPage extends StatefulWidget {
  const SettingsChatPage({super.key});

  @override
  State<SettingsChatPage> createState() => _SettingsChatPageState();
}

class _SettingsChatPageState extends State<SettingsChatPage> {
  Future<void> _editTranscriptionUrl() async {
    final l10n = L10n.of(context);
    final result = await showTextInputDialog(
      context: context,
      title: l10n.transcriptionService,
      hintText: WechatPrefs.defaultTranscriptionUrl,
      initialText: WechatPrefs.transcriptionUrl,
      useRootNavigator: false,
      autocorrect: false,
      keyboardType: TextInputType.url,
    );
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('http')) {
      AppToast.show(l10n.transcriptionServiceInvalid, isError: true);
      return;
    }
    await WechatPrefs.setTranscriptionUrl(trimmed);
    if (!mounted) return;
    setState(() {});
  }

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
        SwitchListTile.adaptive(
          title: Text(l10n.sendOriginalImages),
          subtitle: Text(l10n.sendOriginalImagesHint),
          value: WechatPrefs.sendOriginalImages,
          onChanged: (value) => setState(() {
            WechatPrefs.setSendOriginalImages(value);
          }),
        ),
        SwitchListTile.adaptive(
          // 关掉「显示撤回提示」= 撤回后彻底消失（微信默认行为）
          title: Text(l10n.showRedactedMessages),
          subtitle: Text(l10n.showRedactedMessagesHint),
          value: !AppSettings.hideRedactedEvents.value,
          onChanged: (value) => setState(() {
            AppSettings.hideRedactedEvents.setItem(!value);
          }),
        ),
        ListTile(
          title: Text(l10n.chatBackupMigrate),
          subtitle: Text(l10n.featureComingSoon),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showComingSoon(context),
        ),
        ListTile(
          title: Text(l10n.transcriptionService),
          subtitle: Text(
            WechatPrefs.transcriptionUrl.trim().isEmpty
                ? l10n.transcriptionServiceOff
                : WechatPrefs.transcriptionUrl,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editTranscriptionUrl,
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
  bool _exporting = false;

  Future<void> _exportLogs() async {
    final l10n = L10n.of(context);
    setState(() => _exporting = true);
    final content = await ActionLogger.I.exportText();
    if (!mounted) return;
    if (content.isEmpty) {
      setState(() => _exporting = false);
      AppToast.show(l10n.diagExportEmpty);
      return;
    }
    final saved = await DiagExporter.exportToDownloads();
    if (!mounted) return;
    setState(() => _exporting = false);
    AppToast.show(
      saved ? l10n.exportLogsDone : l10n.exportLogsFailed,
      isError: !saved,
    );
  }

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
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/rooms/settings/storage'),
        ),
        const Divider(),
        SwitchListTile.adaptive(
          title: Text(l10n.diagUploadLogs),
          subtitle: Text(l10n.diagUploadLogsHint),
          value: AppSettings.diagUploadEnabled.value,
          onChanged: (value) {
            AppSettings.diagUploadEnabled.setItem(value);
            setState(() {});
          },
        ),
        ListTile(
          title: Text(l10n.exportLogs),
          trailing: _exporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _exporting ? null : _exportLogs,
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

/// 存储空间：只清「已经不在里面」的房间的本地缓存。
///
/// 退出的群/私聊会一直躺在本地数据库里，占地方也拖慢启动。这里不会替用户
/// 主动退出任何房间（那会给对方发「你退出了群聊」），只清理已经离开的那些。
class StorageSpacePage extends StatefulWidget {
  const StorageSpacePage({super.key});

  @override
  State<StorageSpacePage> createState() => _StorageSpacePageState();
}

class _StorageSpacePageState extends State<StorageSpacePage> {
  bool _cleaning = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final leftRooms = client.rooms
        .where((room) => room.membership != Membership.join)
        .toList();
    final joinedCount = client.rooms.length - leftRooms.length;
    return _WechatSettingsScaffold(
      title: l10n.storageSpace,
      children: [
        ListTile(title: Text(l10n.joinedChats), trailing: Text('$joinedCount')),
        ListTile(
          title: Text(l10n.leftChats),
          subtitle: Text(l10n.cleanLeftRoomsHint),
          trailing: Text('${leftRooms.length}'),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(l10n.cleanLeftRooms),
          subtitle: const Text(''),
          enabled: !_cleaning && leftRooms.isNotEmpty,
          onTap: _cleaning ? null : () => _cleanLeftRooms(leftRooms),
        ),
      ],
    );
  }

  Future<void> _cleanLeftRooms(List<Room> rooms) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.cleanLeftRooms,
      message: l10n.cleanLeftRoomsConfirm('${rooms.length}'),
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok) return;
    setState(() => _cleaning = true);
    var count = 0;
    for (final room in rooms) {
      try {
        await client.database.forgetRoom(room.id);
        count++;
      } catch (e, s) {
        Logs().w('[storage] 清理失败 ${room.id}', e, s);
      }
    }
    client.rooms.removeWhere((room) => room.membership != Membership.join);
    if (!mounted) return;
    setState(() => _cleaning = false);
    AppToast.show(l10n.cleanLeftRoomsDone('$count'));
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
  AppToast.show(L10n.of(context).featureComingSoon);
}
