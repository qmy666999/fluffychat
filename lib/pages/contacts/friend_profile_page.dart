// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/moments/moment_image.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/utils/voip/call_actions.dart';
import 'package:fluffychat/utils/wechat/remark_service.dart';
import 'package:fluffychat/utils/wechat/wechat_prefs.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 好友资料页：备注、发消息、音视频通话、删除好友。
class FriendProfilePage extends StatefulWidget {
  final String userId;

  const FriendProfilePage({required this.userId, super.key});

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

enum _FriendMenuAction {
  setRemark,
  recommend,
  star,
  blacklist,
  complain,
  delete,
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  FriendsService get _service => FriendsService(Matrix.of(context).client);

  MomentsService get _momentsService =>
      MomentsService(Matrix.of(context).client);

  List<String> _recentMomentImages = const [];
  bool _momentsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMomentsPreview());
  }

  /// 资料页那一行要显示对方最近 3 张动态图。
  Future<void> _loadMomentsPreview() async {
    final images = <String>[];
    try {
      final moments = await _momentsService.momentsBySender(
        widget.userId,
        minCount: 3,
        maxPages: 1,
      );
      for (final moment in moments) {
        images.addAll(MomentsService.images(moment));
        if (images.length >= 3) break;
      }
    } catch (e) {
      debugPrint('[moments] preview failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _recentMomentImages = images.take(3).toList();
      _momentsLoaded = true;
    });
  }

  Future<void> _openMoments() async {
    if (_momentsLoaded && _recentMomentImages.isEmpty) {
      AppToast.show(L10n.of(context).noMomentsForFriend);
      return;
    }
    await context.push(
      '/moments/friend?userId=${Uri.encodeComponent(widget.userId)}',
    );
    if (mounted) await _loadMomentsPreview();
  }

  Future<void> _sendMessage() async {
    try {
      final roomId = await _service.openDirectChat(widget.userId);
      if (!mounted) return;
      context.go('/rooms/$roomId');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(L10n.of(context).openChatFailed(e.toString()));
    }
  }

  Future<void> _startCall(CallType type) async {
    try {
      final roomId = await _service.openDirectChat(widget.userId);
      if (!mounted) return;
      final room = Matrix.of(context).client.getRoomById(roomId);
      if (room == null) return;
      await startChatCall(context, room, type);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(L10n.of(context).callStartFailed);
    }
  }

  Future<void> _setRemark() async {
    final friend = _service.load().friend(widget.userId);
    await showRemarkDialog(
      context,
      widget.userId,
      originalName: friend?.displayName,
    );
    if (mounted) setState(() {});
  }

  Future<void> _remove() async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.removeFriend,
      message: l10n.removeFriendConfirm,
      okLabel: l10n.remove,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    await _service.removeFriendBothWays(widget.userId);
    if (!mounted) return;
    context.pop();
  }

  Future<void> _recommend() async {
    await FluffyShare.share('https://matrix.to/#/${widget.userId}', context);
  }

  Future<void> _toggleStar() async {
    final starred = WechatPrefs.isStarred(widget.userId);
    await WechatPrefs.setStarred(widget.userId, !starred);
    if (mounted) setState(() {});
  }

  Future<void> _block() async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.addToBlacklist,
      okLabel: l10n.ok,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    final client = Matrix.of(context).client;
    try {
      await client.ignoreUser(widget.userId);
    } catch (e) {
      debugPrint('[friends] ignore failed: $e');
    }
    if (!mounted) return;
    AppToast.show(l10n.addToBlacklist);
  }

  void _complain() {
    final l10n = L10n.of(context);
    AppToast.show(l10n.complainThanks);
  }

  Future<void> _pickCall() async {
    final l10n = L10n.of(context);
    final type = await showModalBottomSheet<CallType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: Text(l10n.callVoice),
              onTap: () => Navigator.of(context).pop(CallType.kVoice),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(l10n.callVideo),
              onTap: () => Navigator.of(context).pop(CallType.kVideo),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    await _startCall(type);
  }

  Future<void> _onMenu(_FriendMenuAction action) async {
    switch (action) {
      case _FriendMenuAction.setRemark:
        await _setRemark();
      case _FriendMenuAction.recommend:
        await _recommend();
      case _FriendMenuAction.star:
        await _toggleStar();
      case _FriendMenuAction.blacklist:
        await _block();
      case _FriendMenuAction.complain:
        _complain();
      case _FriendMenuAction.delete:
        await _remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final friend = _service.load().friend(widget.userId);
    final client = Matrix.of(context).client;
    final remark = RemarkService(client).remarkOf(widget.userId);
    final originalName = friend?.title ?? widget.userId;
    final title = remark ?? originalName;
    final starred = WechatPrefs.isStarred(widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.friendProfile),
        actions: [
          PopupMenuButton<_FriendMenuAction>(
            icon: const Icon(Icons.more_horiz),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _FriendMenuAction.setRemark,
                child: Text(l10n.setRemarkAndTag),
              ),
              PopupMenuItem(
                value: _FriendMenuAction.recommend,
                child: Text(l10n.recommendToFriend),
              ),
              PopupMenuItem(
                value: _FriendMenuAction.star,
                child: Text(starred ? l10n.unstarFriend : l10n.starFriend),
              ),
              PopupMenuItem(
                value: _FriendMenuAction.blacklist,
                child: Text(l10n.addToBlacklist),
              ),
              PopupMenuItem(
                value: _FriendMenuAction.complain,
                child: Text(l10n.complain),
              ),
              PopupMenuItem(
                value: _FriendMenuAction.delete,
                child: Text(
                  l10n.deleteFriend,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Avatar(
              mxContent: _uri(friend?.avatarUrl),
              name: title,
              size: Avatar.defaultSize * 2,
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(title, style: theme.textTheme.titleLarge)),
          const SizedBox(height: 4),
          Center(
            child: Text(
              widget.userId,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (remark != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Center(
                child: Text(
                  l10n.nicknameLabel(originalName),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: Text(l10n.moments),
            subtitle: _momentsLoaded && _recentMomentImages.isEmpty
                ? Text(l10n.noMomentsShort)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final image in _recentMomentImages)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: MomentImage(
                        uri: Uri.tryParse(image),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right_outlined),
              ],
            ),
            onTap: _openMoments,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _sendMessage,
                  child: Text(l10n.sendMessage),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _pickCall,
                  child: Text(l10n.audioVideoCall),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Uri? _uri(String? value) =>
    value == null || value.isEmpty ? null : Uri.tryParse(value);
