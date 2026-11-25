// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 发现页：只放「朋友圈」这一项。点进去是全屏朋友圈，不带底部导航。
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
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bottomTabDiscover)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.camera_outlined),
            title: Text(l10n.moments),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasNew)
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
            onTap: _openMoments,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
