// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/avatar_image.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'moment_image.dart';
import 'moment_model.dart';

/// 朋友圈：全屏页面，**没有底部导航**。
///
/// 数据是「朋友圈」房间里的 `com.dafeiyu.moment` 事件，明文存储。
class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final ScrollController _scroll = ScrollController();
  Timeline? _timeline;
  Room? _room;
  Uri? _cover;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  MomentsService get _service => MomentsService(Matrix.of(context).client);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool pull = false}) async {
    final startedAt = DateTime.now();
    final userId = Matrix.of(context).client.userID ?? '';
    try {
      final room = _service.room ?? await _service.ensureRoom();
      _room = room;
      final timeline = await room.getTimeline(
        limit: 20,
        onNewEvent: () {
          if (mounted) setState(() {});
        },
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );
      unawaited(_service.inviteMissingFriends(room));
      // 旧封面（账号数据/状态事件）迁成自己的普通消息事件。
      unawaited(_service.migrateLegacyCover());
      // 打开即标记已读：不写这条，发现页红点和底部角标会一直挂着。
      try {
        await _service.markSeen();
      } catch (e) {
        debugPrint('[moments] markSeen failed: $e');
      }
      final cover = await _service.coverForAsync(userId);
      if (pull) {
        // 下拉刷新转圈至少 600ms
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed < const Duration(milliseconds: 600)) {
          await Future.delayed(const Duration(milliseconds: 600) - elapsed);
        }
      }
      if (!mounted) return;
      setState(() {
        _timeline = timeline;
        _cover = cover;
        _loading = false;
        _error = null;
      });
      _autoFill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 内容不足一屏时滚动事件永远不触发，这里主动补拉，直到能滚动或到底。
  void _autoFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _loadingMore || !_hasMore) return;
      if (!_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent > 0) return;
      await _loadMore();
      if (mounted) _autoFill();
    });
  }

  Future<void> _loadMore() async {
    final timeline = _timeline;
    if (timeline == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      // 一页拉不到「动态」就继续拉，最多 5 页（点赞/封面事件会占窗口）。
      var before = MomentsService.momentEvents(timeline.events).length;
      for (var i = 0; i < 5; i++) {
        if (!timeline.canRequestHistory) {
          _hasMore = false;
          break;
        }
        await timeline.requestHistory(historyCount: 50);
        final after = MomentsService.momentEvents(timeline.events).length;
        if (after > before) {
          before = after;
          break;
        }
      }
      if (!timeline.canRequestHistory) _hasMore = false;
    } catch (e) {
      debugPrint('[moments] load more failed: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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

  String _timeText(int ts) {
    final l10n = L10n.of(context);
    return formatMomentTime(
      ts,
      justNow: l10n.timeJustNow,
      minutesAgo: l10n.timeMinutesAgo,
      hoursAgo: l10n.timeHoursAgo,
      yesterday: l10n.timeYesterday,
      daysAgo: l10n.timeDaysAgo,
    );
  }

  Future<void> _openComposer() async {
    final created = await context.push<bool>('/moments/compose');
    if (created == true) await _refresh();
  }

  Future<void> _like(MomentViewData moment) async {
    try {
      if (moment.likedByMe) {
        await _service.unLike(moment.moment, _timeline?.events ?? const []);
      } else {
        await _service.like(moment.moment);
      }
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _comment(MomentViewData moment) async {
    final l10n = L10n.of(context);
    final text = await showTextInputDialog(
      context: context,
      title: l10n.momentsComment,
      hintText: l10n.momentsCommentHint,
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await _service.comment(moment.moment, text.trim());
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete(MomentViewData moment) async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.momentsDelete,
      message: l10n.momentsDeleteConfirm,
      okLabel: l10n.remove,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    await _service.delete(moment.moment);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final theme = Theme.of(context);
    final views = buildMomentViews(
      _timeline?.events ?? const [],
      userId: client.userID,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // 透明 AppBar：封面图从顶栏下面开始
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l10n.moments),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        actions: [
          IconButton(
            tooltip: l10n.momentsPublish,
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _openComposer,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: () => _refresh(pull: true),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // 列表是「最新在上、更旧在下」，所以触底才加载更早的动态。
                  final metrics = notification.metrics;
                  if (metrics.axis != Axis.vertical) return false;
                  if (metrics.pixels >= metrics.maxScrollExtent - 400) {
                    _loadMore();
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(child: _buildCover(client)),
                    if (_error != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    if (views.isEmpty && _error == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              l10n.momentsEmpty,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: views.length,
                        itemBuilder: (context, i) => _MomentCard(
                          data: views[i],
                          name: _nameOf,
                          avatar: _avatarOf,
                          timeText: _timeText(views[i].ts),
                          isOwn: views[i].senderId == client.userID,
                          onLike: () => _like(views[i]),
                          onComment: () => _comment(views[i]),
                          onDelete: () => _delete(views[i]),
                        ),
                      ),
                    if (_loadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!_loadingMore && !_hasMore && views.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              l10n.momentsNoMore,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCover(Client client) {
    final theme = Theme.of(context);
    final userId = client.userID ?? '';
    final name = _nameOf(userId);
    final avatar = _avatarOf(userId);
    final cover = _cover;

    return GestureDetector(
      onTap: _changeCover,
      child: SizedBox(
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              // 封面整屏宽，直接要原图（一张几百 KB，可接受）。
              MomentImage(uri: cover, fit: BoxFit.cover, original: true)
            else
              // 默认封面：主题色渐变 + 相机图标，别用纯色块。
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
                    size: 56,
                    // 方形圆角，不是圆形
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点封面换图：选图 → 转 JPEG（HEIC 也不会变灰）→ 上传 → 发一条封面事件。
  Future<void> _changeCover() async {
    final l10n = L10n.of(context);
    final userId = Matrix.of(context).client.userID ?? '';
    final files = await selectFiles(context, type: FileType.image);
    final file = files.isEmpty ? null : files.first;
    if (file == null) return;
    try {
      final bytes = prepareImageBytes(await file.readAsBytes(), maxSide: 1600);
      await _service.setCover(bytes);
      final cover = await _service.coverForAsync(userId);
      if (!mounted) return;
      setState(() => _cover = cover);
    } on UnsupportedAvatarFormat {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.avatarUnsupportedFormat)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _MomentCard extends StatelessWidget {
  final MomentViewData data;
  final String Function(String) name;
  final Uri? Function(String) avatar;
  final String timeText;
  final bool isOwn;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onDelete;

  const _MomentCard({
    required this.data,
    required this.name,
    required this.avatar,
    required this.timeText,
    required this.isOwn,
    required this.onLike,
    required this.onComment,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = name(data.senderId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            mxContent: avatar(data.senderId),
            name: author,
            size: 40,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (data.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(data.text),
                  ),
                if (data.images.length == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _SingleImage(uri: Uri.tryParse(data.images.first)),
                  )
                else if (data.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ImageGrid(images: data.images),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Text(
                        timeText,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (isOwn)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: L10n.of(context).momentsDelete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: onDelete,
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: L10n.of(context).momentsComment,
                        icon: const Icon(Icons.mode_comment_outlined, size: 18),
                        onPressed: onComment,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: L10n.of(context).momentsLike,
                        icon: Icon(
                          data.likedByMe
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 18,
                          color: data.likedByMe
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: onLike,
                      ),
                    ],
                  ),
                ),
                if (data.likers.isNotEmpty || data.comments.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data.likers.isNotEmpty)
                          Text(
                            '❤️ ${data.likers.map(name).join('、')}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                            ),
                          ),
                        for (final comment in data.comments)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${name(comment.senderId)}：',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  TextSpan(text: comment.body),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13),
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

class _SingleImage extends StatelessWidget {
  final Uri? uri;

  const _SingleImage({required this.uri});

  @override
  Widget build(BuildContext context) {
    // 微信单图大约占正文宽度 60%，按 4:3 显示。
    final width = MediaQuery.sizeOf(context).width * 0.6;
    return SizedBox(
      width: width,
      height: width * 0.75,
      child: MomentImage(
        uri: uri,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> images;

  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final shown = images.take(9).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) => MomentImage(
        uri: Uri.tryParse(shown[i]),
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
