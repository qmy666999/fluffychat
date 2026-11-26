// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

enum PlaceholderKind { contacts, discover }

/// 底部导航里「通讯录」「发现」暂时没有页面，先给个空白页占位。
class PlaceholderPage extends StatelessWidget {
  final PlaceholderKind kind;

  const PlaceholderPage({required this.kind, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final (title, icon) = switch (kind) {
      PlaceholderKind.contacts => (
        l10n.bottomTabContacts,
        Icons.contacts_outlined,
      ),
      PlaceholderKind.discover => (
        l10n.bottomTabDiscover,
        Icons.explore_outlined,
      ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(l10n.comingSoon, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
