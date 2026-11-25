// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Opens the comment sheet of a moment.
Future<void> showMomentComments(
  BuildContext context, {
  required Room room,
  required Event post,
  Future<void> Function()? onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => MomentCommentsSheet(
    room: room,
    post: post,
    onChanged: onChanged,
  ),
);

class MomentCommentsSheet extends StatefulWidget {
  final Room room;
  final Event post;
  final Future<void> Function()? onChanged;

  const MomentCommentsSheet({
    required this.room,
    required this.post,
    this.onChanged,
    super.key,
  });

  @override
  State<MomentCommentsSheet> createState() => _MomentCommentsSheetState();
}

class _MomentCommentsSheetState extends State<MomentCommentsSheet> {
  final TextEditingController _textController = TextEditingController();
  Timeline? _timeline;
  List<Event> _comments = const [];
  bool _sending = false;
  bool _loading = true;

  String? get _ownUserId => Matrix.of(context).client.userID;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final timeline = await widget.room.getTimeline(
        limit: 80,
        onUpdate: _refresh,
        onNewEvent: _refresh,
      );
      if (!mounted) return;
      setState(() {
        _timeline = timeline;
        _loading = false;
      });
      _refresh();
    } catch (exception, stackTrace) {
      Logs().w('Unable to load the comments', exception, stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _refresh() {
    final timeline = _timeline;
    if (timeline == null) return;
    final postId = widget.post.eventId;
    final comments = timeline.events
        .where(
          (event) =>
              event.isMomentsComment && event.relationshipEventId == postId,
        )
        .toList()
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    if (!mounted) return;
    setState(() => _comments = comments);
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await MomentsService(Matrix.of(context).client).comment(
        room: widget.room,
        post: widget.post,
        body: text,
      );
      _textController.clear();
      await widget.onChanged?.call();
    } catch (exception, stackTrace) {
      Logs().w('Unable to send the comment', exception, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).momentsFailedToComment)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(Event comment) async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      useRootNavigator: true,
      title: l10n.momentsDeleteTitle,
      message: l10n.momentsDeleteMessage,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    final client = Matrix.of(context).client;
    try {
      await MomentsService(client).delete(room: widget.room, event: comment);
      if (!mounted) return;
      await widget.onChanged?.call();
    } catch (exception, stackTrace) {
      Logs().w('Unable to delete the comment', exception, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.momentsComments,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _comments.isEmpty
                  ? Center(
                      child: Text(
                        l10n.momentsNoComments,
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _comments.length,
                      itemBuilder: (context, i) {
                        final comment = _comments[i];
                        final author = comment.senderFromMemoryOrFallback;
                        final name =
                            author.displayName ??
                            author.id.localpart ??
                            author.id;
                        return GestureDetector(
                          onLongPress: comment.senderId == _ownUserId
                              ? () => _deleteComment(comment)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Avatar(
                                  mxContent: author.avatarUrl,
                                  name: name,
                                  size: 32,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                            ),
                                          ),
                                          Text(
                                            comment.originServerTs
                                                .localizedTimeShort(context),
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        comment.redacted
                                            ? l10n.momentsCommentDeleted
                                            : comment.body,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      readOnly: _sending,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.momentsCommentHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
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
