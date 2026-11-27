// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:fluffychat/utils/verified_room_extension.dart';
import 'package:fluffychat/utils/wechat/remark_service.dart';
import 'package:fluffychat/utils/wechat/room_kind.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (controller.selectedEvents.isNotEmpty) {
      return Text(
        controller.selectedEvents.length.toString(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      );
    }
    // 两人会话一律显示对方昵称（微信语义），只有真的群聊才显示房间名。
    final isSinglePeer = isSinglePeerChat(room);
    final peer = isSinglePeer ? _peer(room) : null;
    // 备注优先（只对自己生效），没有备注再退回对方昵称。
    final remark = peer == null
        ? null
        : RemarkService(room.client).remarkOf(peer.id);
    final title =
        remark ??
        peer?.calcDisplayname() ??
        room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final avatar = peer?.avatarUrl ?? room.avatar;
    return InkWell(
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: controller.room.membership != .join
          ? null
          : () => FluffyThemes.isThreeColumnMode(context)
                ? controller.toggleDisplayChatDetailsColumn()
                : context.go('/rooms/${room.id}/details'),
      child: Row(
        children: [
          Hero(
            tag: 'content_banner',
            child: Avatar(mxContent: avatar, name: title, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Row(
                  spacing: 4,
                  children: [
                    if (room.allUsersVerified)
                      Icon(
                        Icons.verified,
                        color: Theme.of(context).colorScheme.primary,
                        size: 16,
                      ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                StreamBuilder(
                  stream: room.client.onSyncStatus.stream,
                  builder: (context, snapshot) {
                    final status =
                        room.client.onSyncStatus.value ??
                        const SyncStatusUpdate(SyncStatus.waitingForResponse);
                    final hide =
                        FluffyThemes.isColumnMode(context) ||
                        (room.client.onSync.value != null &&
                            status.status != SyncStatus.error &&
                            room.client.prevBatch != null);
                    final style = TextStyle(fontSize: 11);
                    return AnimatedSize(
                      duration: FluffyThemes.animationDuration,
                      child: hide
                          ? isSinglePeer
                                ? PresenceBuilder(
                                    userId: peer?.id ?? room.directChatMatrixID,
                                    builder: (context, presence) {
                                      final statusMessage = presence?.statusMsg
                                          ?.trim();

                                      final lastActiveTimestamp =
                                          presence?.lastActiveTimestamp;

                                      final texts = [
                                        if (presence?.currentlyActive == true)
                                          L10n.of(context).currentlyActive
                                        else if (lastActiveTimestamp != null)
                                          L10n.of(context).lastActiveAgo(
                                            lastActiveTimestamp
                                                .localizedTimeShort(context),
                                          ),
                                        ?statusMessage,
                                      ];
                                      final text = texts.join(' ◦ ');
                                      if (text.isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      return Text(text, style: style);
                                    },
                                  )
                                : Row(
                                    children: [
                                      if (room.summary.mJoinedMemberCount !=
                                          null)
                                        Text(
                                          L10n.of(context).countParticipants(
                                            (room.summary.mJoinedMemberCount ??
                                                    1) +
                                                (room
                                                        .summary
                                                        .mInvitedMemberCount ??
                                                    0),
                                          ),
                                          maxLines: 1,
                                          style: style,
                                        ),
                                      if (room.topic.isNotEmpty) ...[
                                        Text(' ◦ ', style: style),
                                        Expanded(
                                          child: Text(
                                            room.topic,
                                            style: style,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                          : Row(
                              children: [
                                SizedBox.square(
                                  dimension: 10,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 1,
                                    value: status.progress,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    status.calcLocalizedString(context),
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单聊里对面的那个人（拿不到资料时返回 null，调用方回落到房间名）。
User? _peer(Room room) {
  final peerId = singlePeerUserId(room);
  if (peerId == null) return null;
  for (final user in room.getParticipants()) {
    if (user.id == peerId) return user;
  }
  return null;
}
