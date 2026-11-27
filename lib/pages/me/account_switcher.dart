// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 账号切换面板的操作结果。
enum AccountSwitcherResult {
  /// 已经切到另一个账号，界面需要刷新。
  switched,

  /// 用户点了「+ 添加账户」，要跳去登录页。
  addAccount,
}

/// 底部上滑的账号切换面板。
///
/// 返回 null 表示什么都没做（只关掉了面板）。
Future<AccountSwitcherResult?> showAccountSwitcher(BuildContext context) {
  final matrix = Matrix.of(context);
  if (matrix.widget.clients.isEmpty) return Future.value();
  return showModalBottomSheet<AccountSwitcherResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _AccountSwitcherSheet(matrix: matrix),
  );
}

class _AccountSwitcherSheet extends StatefulWidget {
  const _AccountSwitcherSheet({required this.matrix});

  final MatrixState matrix;

  @override
  State<_AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends State<_AccountSwitcherSheet> {
  /// 每个账号只取一次资料，避免每帧都重新请求。
  final Map<String, Future<Profile?>> _profiles = {};

  bool _busy = false;

  /// 已经退出、但可能还没从 clients 列表里搬走的账号（MatrixState 的退登
  /// 监听是异步的），先在这里挡掉，面板立刻就不显示它了。
  final Set<String> _loggedOut = {};

  List<Client> get _clients => widget.matrix.widget.clients
      .where((c) => c.userID != null && !_loggedOut.contains(c.userID))
      .toList();

  Future<Profile?> _profileOf(Client client) => _profiles.putIfAbsent(
    client.userID ?? '',
    () => client.isLogged() ? client.fetchOwnProfile() : Future.value(null),
  );

  void _select(Client client) {
    if (_busy) return;
    final active = widget.matrix.client;
    if (identical(client, active)) {
      Navigator.of(context).pop();
      return;
    }
    widget.matrix.setActiveClient(client);
    Navigator.of(context).pop(AccountSwitcherResult.switched);
  }

  void _addAccount() {
    if (_busy) return;
    Navigator.of(context).pop(AccountSwitcherResult.addAccount);
  }

  /// 长按非当前账号：底部弹「退出这个账号」。
  Future<void> _showLogoutMenu(Client client, String name) async {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                l10n.logoutThisAccount,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _logout(client);
  }

  Future<void> _logout(Client client) async {
    final me = client.userID;
    setState(() {
      _busy = true;
      if (me != null) _loggedOut.add(me);
    });
    try {
      await client.logout();
    } catch (e, s) {
      Logs().w('[account] 退出账号失败', e, s);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (me != null) _loggedOut.remove(me);
      });
      AppToast.show(L10n.of(context).oopsSomethingWentWrong);
      return;
    }
    if (!mounted) return;
    // 退出成功后 MatrixState 会把它从 widget.clients 里删掉，这里跟着刷新。
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final active = widget.matrix.client;
    final clients = _clients;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.switchAccount,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: clients.length,
                itemBuilder: (context, index) {
                  final client = clients[index];
                  return _AccountTile(
                    client: client,
                    isActive: identical(client, active),
                    profile: _profileOf(client),
                    enabled: !_busy,
                    onTap: () => _select(client),
                    onLongPress: identical(client, active)
                        ? null
                        : (name) => _showLogoutMenu(client, name),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              enabled: !_busy,
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: Text(l10n.addAccount),
              trailing: const Icon(Icons.chevron_right_outlined),
              onTap: _addAccount,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.client,
    required this.isActive,
    required this.profile,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  final Client client;
  final bool isActive;
  final Future<Profile?> profile;
  final bool enabled;
  final VoidCallback onTap;
  final void Function(String name)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = client.userID ?? '';
    final fallback = userId.localpart ?? userId;

    return FutureBuilder<Profile?>(
      future: profile,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final name = data?.displayName ?? fallback;
        return ListTile(
          enabled: enabled,
          onTap: onTap,
          onLongPress: onLongPress == null ? null : () => onLongPress!(name),
          leading: Avatar(
            mxContent: data?.avatarUrl,
            name: name,
            size: 40,
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            userId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: isActive
              ? Icon(Icons.check, color: theme.colorScheme.primary)
              : null,
        );
      },
    );
  }
}
