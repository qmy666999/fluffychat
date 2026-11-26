// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:material_ui/material_ui.dart';

/// 设置 → 通用 → 发现页管理：开关 + 拖动排序。
class DiscoverManagePage extends StatefulWidget {
  const DiscoverManagePage({super.key});

  @override
  State<DiscoverManagePage> createState() => _DiscoverManagePageState();
}

class _DiscoverManagePageState extends State<DiscoverManagePage> {
  List<String> get _order => WechatPrefs.discoverOrder;

  String _label(BuildContext context, String id) {
    final l10n = L10n.of(context);
    return switch (id) {
      'moments' => l10n.moments,
      'scan' => l10n.scan,
      _ => id,
    };
  }

  IconData _icon(String id) => switch (id) {
    'moments' => Icons.camera_outlined,
    'scan' => Icons.qr_code_scanner,
    _ => Icons.apps,
  };

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).discoverManage)),
      body: ReorderableListView.builder(
        itemCount: order.length,
        onReorderItem: (oldIndex, newIndex) {
          final next = [...order];
          final moved = next.removeAt(oldIndex);
          next.insert(newIndex, moved);
          WechatPrefs.setDiscoverOrder(next);
          setState(() {});
        },
        itemBuilder: (context, i) {
          final id = order[i];
          return ListTile(
            key: ValueKey('discover_manage_$id'),
            leading: Icon(_icon(id)),
            title: Text(_label(context, id)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: !WechatPrefs.isDiscoverHidden(id),
                  onChanged: (value) {
                    WechatPrefs.setDiscoverHidden(id, !value);
                    setState(() {});
                  },
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.drag_handle,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
