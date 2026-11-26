// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'matrix.dart';

enum ChatPopupMenuActions {
  details,
  encryption,
  leave,
  search,
  voiceCall,
  videoCall,
}

class ChatSettingsPopupMenu extends StatefulWidget {
  final Room room;
  final bool displayChatDetails;

  const ChatSettingsPopupMenu(this.room, this.displayChatDetails, {super.key});

  @override
  ChatSettingsPopupMenuState createState() => ChatSettingsPopupMenuState();
}

class ChatSettingsPopupMenuState extends State<ChatSettingsPopupMenu> {
  StreamSubscription? notificationChangeSub;

  @override
  void dispose() {
    notificationChangeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    notificationChangeSub ??= Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.accountData?.any(
                (accountData) => accountData.type == 'm.push_rules',
              ) ??
              false,
        )
        .listen((u) => setState(() {}));
    return Stack(
      alignment: Alignment.center,
      children: [
        const SizedBox.shrink(),
        PopupMenuButton<ChatPopupMenuActions>(
          useRootNavigator: true,
          onSelected: (choice) async {
            switch (choice) {
              case ChatPopupMenuActions.leave:
                final l10n = L10n.of(context);
                final router = GoRouter.of(context);
                final confirmed = await showOkCancelAlertDialog(
                  context: context,
                  title: l10n.areYouSure,
                  message: l10n.archiveRoomDescription,
                  okLabel: l10n.leave,
                  cancelLabel: l10n.cancel,
                  isDestructive: true,
                );
                if (confirmed != OkCancelResult.ok) return;
                if (!context.mounted) return;
                final result = await showFutureLoadingDialog(
                  context: context,
                  future: () => widget.room.leave(),
                );
                if (result.error == null) {
                  router.go('/rooms');
                }

                break;
              case ChatPopupMenuActions.details:
                _showChatDetails();
                break;
              case ChatPopupMenuActions.search:
                context.go('/rooms/${widget.room.id}/search');
                break;
              case ChatPopupMenuActions.encryption:
                context.go('/rooms/${widget.room.id}/encryption');
                break;
              case ChatPopupMenuActions.voiceCall:
                _startCall(CallType.kVoice);
                break;
              case ChatPopupMenuActions.videoCall:
                _startCall(CallType.kVideo);
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            if (_canStartCall)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.voiceCall,
                child: Row(
                  children: [
                    const Icon(Icons.call_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).callVoice),
                  ],
                ),
              ),
            if (_canStartCall)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.videoCall,
                child: Row(
                  children: [
                    const Icon(Icons.videocam_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).callVideo),
                  ],
                ),
              ),
            if (widget.displayChatDetails && widget.room.membership == .join)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.details,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).chatDetails),
                  ],
                ),
              ),
            if (widget.room.membership case .join || .leave)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.search,
                child: Row(
                  children: [
                    const Icon(Icons.search_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).search),
                  ],
                ),
              ),
            if (widget.room.membership case .join || .leave)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.encryption,
                child: Row(
                  children: [
                    const Icon(Icons.lock_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).encryption),
                  ],
                ),
              ),
            PopupMenuItem<ChatPopupMenuActions>(
              value: ChatPopupMenuActions.leave,
              child: Row(
                children: [
                  const Icon(Icons.delete_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).leave),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 只有两个成员的私聊才显示通话入口（这一版不做群组通话）。
  bool get _canStartCall =>
      widget.room.membership == Membership.join &&
      widget.room.summary.mJoinedMemberCount == 2;

  Future<void> _startCall(CallType type) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final voip = MatrixVoip.ensure(widget.room.client);
    if (voip.hasCall) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.callAlreadyInCall)));
      return;
    }
    try {
      await voip.startCall(widget.room, type);
    } catch (e, s) {
      Logs().w('[VoIP] 发起通话失败', e, s);
      messenger?.showSnackBar(SnackBar(content: Text(l10n.callStartFailed)));
    }
  }

  void _showChatDetails() {
    if (GoRouterState.of(context).uri.path.endsWith('/details')) {
      context.go('/rooms/${widget.room.id}');
    } else {
      context.go('/rooms/${widget.room.id}/details');
    }
  }
}
