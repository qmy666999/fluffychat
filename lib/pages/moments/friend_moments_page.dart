// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/moments/moment_image.dart';
import 'package:fluffychat/pages/moments/moment_model.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'friend_moments_model.dart';

/// 看别人的朋友圈：只显示这个人的动态，按「日期分组 + 左侧大日期」排版。
///
/// 和「我自己的朋友圈」的区别：数据只筛 sender、没有删除按钮、
/// 封面用对方的（来自房间状态事件）。
class FriendMomentsPage extends StatefulWidget {
  final String userId;

  const FriendMomentsPage({required this.userId, super.key});

  @override
  State<FriendMomentsPage> createState() => _FriendMomentsPageState();
}

class _FriendMomentsPageState extends State<FriendMomentsPage> {
  Room? _room;
  Uri? _cover;
  List<MomentViewData> _moments = const [];
  bool _loading = true;

  MomentsService get _service => MomentsService(Matrix.of(context).client);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final room = _service.room;
      final events = await _service.momentsBySender(widget.userId);
      final cover = await _service.coverForAsync(widget.userId);
      if (!mounted) return;
      setState(() {
        _room = room;
        _cover = cover;
        _moments = events
            .map(
              (event) => MomentViewData(
                moment: event,
                text: event.content['text'] as String? ?? '',
                images: MomentsService.images(event),
                ts: MomentsService.momentTs(event),
                likers: const [],
                comments: const [],
                likedByMe: false,
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[moments] friend moments failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _nameOf(String userId) {
    final member = _room?.getState(EventTypes.RoomMember, userId);
    final displayName = (member?.content['displayname'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return userId.localpart ?? userId;
  }

  Uri? _avatarOf(String userId) {
    final member = _room?.getState(EventTypes.RoomMember, userId);
    final url = member?.content['avatar_url'] as String?;
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final name = _nameOf(widget.userId);
    final cover = _cover;
    final groups = groupMomentsByDate(_moments, l10n: l10n);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: theme.colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              background: _Cover(
                cover: cover,
                name: name,
                avatar: _avatarOf(widget.userId),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (_moments.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    l10n.noMomentsForFriend,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, i) => _DateGroup(
                group: groups[i],
                onOpenImage: (uri) => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    // 点开看大图：要原图
                    child: MomentImage(
                      uri: uri,
                      fit: BoxFit.contain,
                      original: true,
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final Uri? cover;
  final String name;
  final Uri? avatar;

  const _Cover({required this.cover, required this.name, required this.avatar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          MomentImage(uri: cover, fit: BoxFit.cover, original: true)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.6),
                ],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.photo_camera_outlined,
                size: 40,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 12,
          child: Row(
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              const SizedBox(width: 10),
              Avatar(
                mxContent: avatar,
                name: name,
                size: 64,
                // 方形圆角，和微信一致
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateGroup extends StatelessWidget {
  final MomentDateGroup group;
  final void Function(Uri uri) onOpenImage;

  const _DateGroup({required this.group, required this.onOpenImage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧大日期：今天 / 昨天 / 23 + 11月
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.topLine,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (group.bottomLine != null)
                  Text(
                    group.bottomLine!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                for (final moment in group.moments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (moment.text.isNotEmpty) Text(moment.text),
                        if (moment.images.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final image in moment.images.take(9))
                                  GestureDetector(
                                    onTap: () {
                                      final uri = Uri.tryParse(image);
                                      if (uri != null) onOpenImage(uri);
                                    },
                                    child: SizedBox(
                                      width: 84,
                                      height: 84,
                                      child: MomentImage(
                                        uri: Uri.tryParse(image),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
