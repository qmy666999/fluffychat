// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/moments/moment_comments.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'moments_view.dart';

/// The moments (朋友圈) feed of the current account.
class Moments extends StatefulWidget {
  const Moments({super.key});

  @override
  MomentsController createState() => MomentsController();
}

class MomentsController extends State<Moments> {
  final List<Timeline> _timelines = [];
  List<MomentEntry> entries = const [];
  List<Room> invites = const [];
  bool loading = true;
  Object? error;

  MomentsService get service => MomentsService(Matrix.of(context).client);

  String? get ownUserId => Matrix.of(context).client.userID;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final service = this.service;
      final timelines = await service.loadTimelines(onUpdate: _onTimelineUpdate);
      if (!mounted) return;
      setState(() {
        _timelines
          ..clear()
          ..addAll(timelines);
        invites = service.pendingInvites;
        entries = buildMomentsFeed(_timelines);
        loading = false;
      });
    } catch (exception, stackTrace) {
      Logs().w('Unable to load the moments feed', exception, stackTrace);
      if (!mounted) return;
      setState(() {
        error = exception;
        loading = false;
      });
    }
  }

  void _onTimelineUpdate() {
    if (!mounted) return;
    setState(() => entries = buildMomentsFeed(_timelines));
  }

  Future<void> openCompose() async {
    final published = await context.push<bool>('/moments/compose');
    if (published == true) await reload();
  }

  /// Invites friends to the own moments room, creating it on first use.
  Future<void> inviteFriends() async {
    try {
      final room = await service.ensureOwnRoom();
      if (!mounted) return;
      await context.push('/rooms/${room.id}/invite');
      if (mounted) await reload();
    } catch (exception, stackTrace) {
      Logs().w('Unable to open the own moments room', exception, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).momentsFailedToOpenFeed)),
      );
    }
  }

  Future<void> joinInvite(Room room) async {
    try {
      await room.join();
    } catch (exception, stackTrace) {
      Logs().w('Unable to join the moments room ${room.id}', exception, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).momentsFailedToOpenFeed)),
      );
      return;
    }
    await reload();
  }

  Future<void> toggleLike(MomentEntry entry) async {
    try {
      await service.setLiked(
        room: entry.room,
        post: entry.post,
        currentReactions: entry.reactions,
        liked: entry.likedBy(ownUserId),
      );
    } catch (exception, stackTrace) {
      Logs().w('Unable to change the like', exception, stackTrace);
    }
  }

  void openComments(MomentEntry entry) {
    showMomentComments(
      context,
      room: entry.room,
      post: entry.post,
      onChanged: reload,
    );
  }

  Future<void> deleteMoment(MomentEntry entry) async {
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      useRootNavigator: false,
      title: l10n.momentsDeleteTitle,
      message: l10n.momentsDeleteMessage,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    try {
      await service.delete(room: entry.room, event: entry.post);
    } catch (exception, stackTrace) {
      Logs().w('Unable to delete the moment', exception, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.momentsFailedToDelete)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MomentsView(this);
}
