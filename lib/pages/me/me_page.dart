// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_bottom_bar.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 「我」tab：头像、昵称、ID、二维码，以及常用入口。
///
/// 以前点「我」弹的是账号切换抽屉，现在是一页正常的个人中心，
/// 抽屉里的设置等入口都收到这里。
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final userId = client.userID ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bottomTabMe),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const ChatListBottomBar(currentIndex: 3),
      body: ListView(
        children: [
          FutureBuilder<Profile>(
            future: client.isLogged() ? client.fetchOwnProfile() : null,
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final name =
                  profile?.displayName ??
                  userId.localpart ??
                  l10n.unknownDevice;
              return InkWell(
                onTap: () => _showQr(context, userId, name),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Row(
                    children: [
                      Avatar(
                        mxContent: profile?.avatarUrl,
                        name: name,
                        size: 64,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: theme.textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(
                              userId,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.qr_code_2_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.camera_outlined),
            title: Text(l10n.moments),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => context.push('/moments'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: Text(l10n.favoritesEntry),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => context.push('/me/favorites'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text(l10n.newFriends),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => context.push('/contacts/new'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.settings),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => context.push('/rooms/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_outlined),
            title: Text(l10n.addAccount),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => context.push('/rooms/settings/addaccount'),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(l10n.archive),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => context.push('/rooms/archive'),
          ),
        ],
      ),
    );
  }

  void _showQr(BuildContext context, String userId, String name) {
    if (userId.isEmpty) return;
    final link = 'https://matrix.to/#/$userId';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: SizedBox(
          width: 220,
          height: 220,
          child: PrettyQrView.data(data: link),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.of(context).close),
          ),
        ],
      ),
    );
  }
}
