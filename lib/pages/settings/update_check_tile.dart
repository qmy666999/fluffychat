// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/updates/app_update_service.dart';
import 'package:fluffychat/widgets/app_update_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页里的「检查更新」。
class UpdateCheckTile extends StatelessWidget {
  const UpdateCheckTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListTile(
      leading: const Icon(Icons.system_update_alt_outlined),
      title: Text(l10n.updateCheck),
      subtitle: FutureBuilder<String>(
        future: AppUpdateService.currentVersionLabel(),
        builder: (context, snapshot) =>
            Text('${l10n.updateCurrentVersion} ${snapshot.data ?? '—'}'),
      ),
      trailing: const Icon(Icons.chevron_right_outlined),
      onTap: () => checkAndPromptUpdate(context),
    );
  }
}
