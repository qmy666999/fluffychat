// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/active_call_indicator.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/utils/wechat/redaction_preview.dart';
import 'package:fluffychat/utils/wechat/room_kind.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

class ChatListItem extends StatelessWidget {
  final Room room;
  final Room? space;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    this.space,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final lastEvent = room.lastEvent;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = isSinglePeerChat(room);
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor = activeChat
        ? theme.colorScheme.secondaryContainer
        : null;
    // 两人会话一律显示对方昵称（微信语义），不要露出房间名。
    final displayname =
        (isDirectChat ? singlePeerDisplayname(room) : null) ??
        room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final space = this.space;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        color: backgroundColor,
        child: FutureBuilder(
          future: room.name.isEmpty ? room.loadHeroUsers() : null,
          builder: (context, _) => HoverBuilder(
            builder: (context, listTileHovered) => ListTile(
              minVerticalPadding: 16,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onLongPress: () => onLongPress?.call(context),
              leading: HoverBuilder(
                builder: (context, hovered) => AnimatedScale(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  scale: hovered ? 1.1 : 1.0,
                  child: SizedBox(
                    width: Avatar.defaultSize,
                    height: Avatar.defaultSize,
                    child: Stack(
                      // 未读角标要贴到头像右上角，允许它探出 40x40 的框。
                      clipBehavior: Clip.none,
                      children: [
                        if (space != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Avatar(
                              shapeBorder: RoundedSuperellipseBorder(
                                side: BorderSide(
                                  width: 2,
                                  color:
                                      backgroundColor ??
                                      theme.colorScheme.surface,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConfig.spaceBorderRadius * 0.75,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.spaceBorderRadius * 0.75,
                              ),
                              mxContent: space.avatar,
                              size: Avatar.defaultSize * 0.75,
                              name: space.getLocalizedDisplayname(),
                              onTap: () => onLongPress?.call(context),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Avatar(
                            shapeBorder: space == null
                                ? room.isSpace
                                      ? RoundedSuperellipseBorder(
                                          side: BorderSide(
                                            width: 1,
                                            color: theme.dividerColor,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.spaceBorderRadius,
                                          ),
                                        )
                                      : null
                                : RoundedRectangleBorder(
                                    side: BorderSide(
                                      width: 2,
                                      color:
                                          backgroundColor ??
                                          theme.colorScheme.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      Avatar.defaultSize,
                                    ),
                                  ),
                            borderRadius: room.isSpace
                                ? BorderRadius.circular(
                                    AppConfig.spaceBorderRadius,
                                  )
                                : null,
                            mxContent: room.avatar,
                            size: space != null
                                ? Avatar.defaultSize * 0.75
                                : Avatar.defaultSize,
                            name: displayname,
                            presenceUserId: directChatMatrixId,
                            presenceBackgroundColor: backgroundColor,
                            onTap: () => onLongPress?.call(context),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: GestureDetector(
                            onTap: () => onLongPress?.call(context),
                            child: AnimatedScale(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              scale: listTileHovered ? 1.0 : 0.0,
                              child: Material(
                                color: backgroundColor,
                                borderRadius: BorderRadius.circular(16),
                                child: const Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 未读角标：从头像右侧挪到头像右上角。
                        Positioned(
                          top: -4,
                          right: -4,
                          child: UnreadBubble(room: room),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  if (room.isLowPriority)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.low_priority,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (room.isFavourite)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (!room.isSpace && room.membership != Membership.invite)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        room.latestEventReceivedTime.localizedTimeShort(
                          context,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: room.hasNewMessages
                              ? FontWeight.bold
                              : null,
                          color: room.highlightCount >= 1
                              ? theme.colorScheme.error
                              : room.hasNewMessages
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                children: [
                  if (room.hasActiveMatrixRtcCall)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: ActiveCallIndicator(room: room),
                    ),
                  if (typingText.isEmpty &&
                      ownMessage &&
                      room.lastEvent?.status.isSending == true) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedSize(
                    clipBehavior: Clip.hardEdge,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: typingText.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: TypingAnimation(size: 4.0),
                          )
                        : room.lastEvent?.relationshipType ==
                              RelationshipTypes.thread
                        ? Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            margin: const EdgeInsets.only(right: 4.0),
                            child: Row(
                              mainAxisSize: .min,
                              children: [
                                Icon(
                                  Icons.message_outlined,
                                  size: 12,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  L10n.of(context).thread,
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: room.isSpace && room.membership == Membership.join
                        ? Text(
                            L10n.of(
                              context,
                            ).countChats(room.spaceChildren.length),
                          )
                        : typingText.isNotEmpty
                        ? Text(
                            typingText,
                            style: TextStyle(color: theme.colorScheme.primary),
                            maxLines: 1,
                            softWrap: false,
                          )
                        : _RoomPreview(
                            room: room,
                            isDirectChat: isDirectChat,
                            directChatMatrixId: directChatMatrixId,
                          ),
                  ),
                  const SizedBox(width: 8),
                  // 静音图标挪到第二行最右；未读角标去了头像右上角。
                  if (isMuted)
                    const Icon(Icons.notifications_off_outlined, size: 16),
                ],
              ),
              onTap: onTap,
              trailing: onForget == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: onForget,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 会话列表里的最后一条消息预览。
///
/// 撤回的消息在聊天里彻底消失，所以预览也要回退到上一条可见消息：
/// [Room.lastEvent] 仍然指向那个被撤回的事件。
class _RoomPreview extends StatefulWidget {
  const _RoomPreview({
    required this.room,
    required this.isDirectChat,
    required this.directChatMatrixId,
  });

  final Room room;
  final bool isDirectChat;
  final String? directChatMatrixId;

  @override
  State<_RoomPreview> createState() => _RoomPreviewState();
}

class _RoomPreviewState extends State<_RoomPreview> {
  Event? _event;
  String? _senderName;
  String _signature = '';
  bool _loading = false;

  String get _currentSignature => _signatureOf(widget.room);

  static String _signatureOf(Room room) {
    final lastEvent = room.lastEvent;
    return '${room.id}|${lastEvent?.eventId}|${lastEvent?.type}|'
        '${lastEvent?.redacted}|${room.membership}';
  }

  @override
  void initState() {
    super.initState();
    _signature = _currentSignature;
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _RoomPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signatureOf(widget.room) != _signatureOf(oldWidget.room)) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final room = widget.room;
    final lastEvent = room.lastEvent;
    _signature = _signatureOf(room);
    if (RedactionPreviewCache.isHiddenPreview(lastEvent)) {
      setState(() {
        _event = null;
        _senderName = null;
        _loading = true;
      });
      RedactionPreviewCache.invalidate(room.id);
      final previous = await RedactionPreviewCache.previous(room);
      if (!mounted || _signature != _currentSignature) return;
      setState(() {
        _event = previous;
        _loading = false;
      });
      await _loadSender(previous);
      return;
    }
    setState(() {
      _event = lastEvent;
      _senderName = null;
      _loading = false;
    });
    await _loadSender(lastEvent);
  }

  Future<void> _loadSender(Event? event) async {
    if (event == null) return;
    if (widget.room.getState(EventTypes.RoomMember, event.senderId) != null) {
      return;
    }
    try {
      final user = await event.fetchSenderUser();
      if (!mounted || _event?.eventId != event.eventId) return;
      setState(() => _senderName = user?.calcDisplayname());
    } catch (_) {
      // 拿不到就用事件里自带的昵称
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final room = widget.room;
    if (room.membership == Membership.invite) {
      final reason = room
          .getState(EventTypes.RoomMember, room.client.userID!)
          ?.content
          .tryGet<String>('reason');
      return Text(
        reason ??
            (widget.isDirectChat ? l10n.newChatRequest : l10n.inviteGroupChat),
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (_loading) return const SizedBox(height: 20);
    final event = _event;
    if (event == null) {
      return Text(
        l10n.noMessagesYet,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    var body = event.calcLocalizedBody(
      MatrixLocals(l10n),
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
    );
    if (!widget.isDirectChat || widget.directChatMatrixId != event.senderId) {
      body = l10n.senderMessage(
        event.senderId == room.client.userID
            ? l10n.you
            : _senderName ?? event.senderFromMemoryOrFallback.calcDisplayname(),
        body,
      );
    }
    return Text(
      body,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
