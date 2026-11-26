// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;
  const UnreadBubble({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNotifications = room.notificationCount > 0;
    // 微信行为：免打扰的会话只显示红点，不显示数字。
    final isMuted = room.pushRuleState != PushRuleState.notify;
    final showNumber = hasNotifications && !isMuted;
    final showDot =
        !showNumber &&
        (room.isUnread || room.hasNewMessages || room.markedUnread);
    final unreadBubbleSize = showNumber ? 20.0 : 14.0;
    final visible = showNumber || showDot;
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: showNumber ? 7 : 0),
      height: visible ? unreadBubbleSize : 0,
      width: !visible
          ? 0
          : showNumber
          ? (unreadBubbleSize - 9) * room.notificationCount.toString().length +
                9
          : unreadBubbleSize,
      decoration: BoxDecoration(
        color: room.highlightCount > 0
            ? theme.colorScheme.error
            : showNumber
            ? theme.colorScheme.primary
            : theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(unreadBubbleSize),
      ),
      child: showNumber
          ? Text(
              room.notificationCount.toString(),
              style: TextStyle(
                color: room.highlightCount > 0
                    ? theme.colorScheme.onError
                    : theme.colorScheme.onPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: .center,
            )
          : const SizedBox.shrink(),
    );
  }
}
