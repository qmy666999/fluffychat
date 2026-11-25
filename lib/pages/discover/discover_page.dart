// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_bottom_bar.dart';
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
      appBar: AppBar(
        title: Text(l10n.bottomTabDiscover),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: l10n.addToContacts,
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/contacts/add'),
          ),
        ],
      ),
      bottomNavigationBar: const ChatListBottomBar(currentIndex: 2),
      body: ListView(
        children: [
          SizedBox(
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
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 22,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
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
          ),
          // 分割线从头像右侧开始（16 + 40 + 16 = 72）
          const Divider(height: 1, indent: 72),
        ],
      ),
    );
  }
}
