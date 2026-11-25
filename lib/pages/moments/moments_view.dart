// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'moments.dart';

class MomentsView extends StatelessWidget {
  final MomentsController controller;

  const MomentsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.momentsTitle),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms')),
        ),
        actions: [
          IconButton(
            tooltip: l10n.momentsInviteFriends,
            onPressed: controller.inviteFriends,
            icon: const Icon(Icons.person_add_alt_outlined),
          ),
          IconButton(
            tooltip: l10n.momentsNewPost,
            onPressed: controller.openCompose,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.openCompose,
        tooltip: l10n.momentsNewPost,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: controller.reload,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = L10n.of(context);
    final entries = controller.entries;
    final invites = controller.invites;

    if (controller.loading && entries.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (controller.error != null && entries.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(l10n.momentsFailedToLoad)),
        ],
      );
    }

    if (entries.isEmpty && invites.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Icon(
              Icons.photo_camera_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.momentsEmpty, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            l10n.momentsEmptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: controller.inviteFriends,
              icon: const Icon(Icons.person_add_alt_outlined),
              label: Text(l10n.momentsInviteFriends),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: invites.length + entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i < invites.length) return _InviteCard(controller, invites[i]);
        return _MomentCard(controller, entries[i - invites.length]);
      },
    );
  }
}

class _InviteCard extends StatelessWidget {
  final MomentsController controller;
  final Room room;

  const _InviteCard(this.controller, this.room);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name =
        room.getState(EventTypes.RoomName)?.content['name'] as String? ?? '';
    return Card(
      child: ListTile(
        leading: Avatar(mxContent: room.avatar, name: name, size: 40),
        title: Text(l10n.momentsInvitedYou(name.isEmpty ? room.id : name)),
        trailing: FilledButton(
          onPressed: () => controller.joinInvite(room),
          child: Text(l10n.momentsAccept),
        ),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  final MomentsController controller;
  final MomentEntry entry;

  const _MomentCard(this.controller, this.entry);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final author = entry.post.senderFromMemoryOrFallback;
    final displayname =
        author.displayName ?? author.id.localpart ?? author.id;
    final liked = entry.likedBy(controller.ownUserId);
    final canDelete = entry.post.senderId == controller.ownUserId;

    return Card(
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  mxContent: author.avatarUrl,
                  name: displayname,
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        entry.timestamp.localizedTimeShort(context),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (canDelete)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') controller.deleteMoment(entry);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.delete),
                      ),
                    ],
                  ),
              ],
            ),
            if (entry.body.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(entry.body, style: theme.textTheme.bodyMedium),
            ],
            if (entry.images.isNotEmpty) ...[
              const SizedBox(height: 10),
              _MomentImages(entry.images),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => controller.toggleLike(entry),
                  style: TextButton.styleFrom(
                    foregroundColor: liked
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  label: Text(
                    entry.likeCount > 0
                        ? '${entry.likeCount}'
                        : l10n.momentsLike,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => controller.openComments(entry),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.mode_comment_outlined, size: 18),
                  label: Text(
                    entry.comments.isNotEmpty
                        ? '${entry.comments.length}'
                        : l10n.momentsComment,
                  ),
                ),
                const Spacer(),
                if (entry.comments.isNotEmpty)
                  TextButton(
                    onPressed: () => controller.openComments(entry),
                    child: Text(l10n.momentsViewAllComments),
                  ),
              ],
            ),
            if (entry.comments.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final comment in entry.comments.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${comment.senderFromMemoryOrFallback.displayName ?? comment.senderId.localpart}: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              TextSpan(text: comment.body),
                            ],
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (entry.comments.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l10n.momentsMoreComments(
                            entry.comments.length - 3,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MomentImages extends StatelessWidget {
  final List<String> images;

  const _MomentImages(this.images);

  @override
  Widget build(BuildContext context) {
    final uris = images.map(Uri.parse).toList();
    final columns = uris.length == 1
        ? 1
        : uris.length == 2 || uris.length == 4
        ? 2
        : 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = columns == 1
            ? constraints.maxWidth * 0.7
            : constraints.maxWidth;
        return SizedBox(
          width: width,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: uris.length,
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => MxcImageViewer(uris[i]),
              ),
              child: MxcImage(
                uri: uris[i],
                fit: BoxFit.cover,
                isThumbnail: true,
                animated: PlatformInfos.isMobile,
              ),
            ),
          ),
        );
      },
    );
  }
}
