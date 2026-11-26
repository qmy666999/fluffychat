// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_bottom_bar.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/utils/scan_flow.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 发现页：朋友圈、扫一扫，可在设置里隐藏/排序。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  bool _hasNew = false;

  MomentsService get _service => MomentsService(Matrix.of(context).client);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshDot();
    // 打开发现页时兜底再试一次静默加入（启动时可能还没解析到别名）。
    _service.ensureJoined();
  }

  Future<void> _refreshDot() async {
    final hasNew = await _service.hasNewMoments();
    if (!mounted) return;
    setState(() => _hasNew = hasNew);
  }

  Future<void> _openMoments() async {
    await context.push('/moments');
    // 回来后重新判断红点（朋友圈页里已经标记过已读）。
    await _refreshDot();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final order = WechatPrefs.discoverOrder
        .where((id) => !WechatPrefs.isDiscoverHidden(id))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bottomTabDiscover),
        centerTitle: true,
        automaticallyImplyLeading: false,
        // 发现页没有「添加联系人」入口，右上角保持干净。
      ),
      bottomNavigationBar: const ChatListBottomBar(currentIndex: 2),
      body: ListView(
        children: [
          for (final id in order)
            if (id == 'moments')
              _DiscoverRow(
                icon: Icons.photo_camera_outlined,
                label: l10n.moments,
                showDot: _hasNew,
                onTap: _openMoments,
              )
            else if (id == 'scan')
              _DiscoverRow(
                icon: Icons.qr_code_scanner,
                label: l10n.scan,
                onTap: () => startMatrixScan(context),
              ),
        ],
      ),
    );
  }
}

/// 发现页的一行：40×40 彩色圆角图标 + 名称 + 可选红点。
class _DiscoverRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showDot;
  final VoidCallback onTap;

  const _DiscoverRow({
    required this.icon,
    required this.label,
    this.showDot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 72,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 22, color: theme.colorScheme.onPrimary),
        ),
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_outlined),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
