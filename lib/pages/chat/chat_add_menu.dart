// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/voip/call_actions.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 聊天输入框右侧的「+」按钮，点开是微信式的宫格面板。
class ChatAddMenuButton extends StatelessWidget {
  const ChatAddMenuButton({super.key, required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: const Icon(Icons.add_circle_outline),
      color: theme.colorScheme.onPrimaryContainer,
      onPressed: () => showChatAddMenu(context, controller),
    );
  }
}

/// 打开宫格面板，选中后执行对应动作。
///
/// 1 对 1 房间多出「语音通话 / 视频通话」两项；群聊里不显示。
Future<void> showChatAddMenu(
  BuildContext context,
  ChatController controller,
) async {
  final room = controller.room;
  final canCall =
      room.membership == Membership.join &&
      room.summary.mJoinedMemberCount == 2;
  final entry = await showModalBottomSheet<_AddMenuEntry>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) =>
        _ChatAddMenuSheet(controller: controller, canCall: canCall),
  );
  if (entry == null) return;
  entry.onAction();
}

class _AddMenuEntry {
  const _AddMenuEntry({
    required this.icon,
    required this.label,
    required this.onAction,
  });

  final IconData icon;
  final String label;
  final VoidCallback onAction;
}

class _ChatAddMenuSheet extends StatelessWidget {
  const _ChatAddMenuSheet({required this.controller, required this.canCall});

  final ChatController controller;
  final bool canCall;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final controller = this.controller;

    final entries = <_AddMenuEntry>[
      _AddMenuEntry(
        icon: Icons.image_outlined,
        label: l10n.sendImage,
        onAction: () =>
            controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.image),
      ),
      if (PlatformInfos.isMobile)
        _AddMenuEntry(
          icon: Icons.camera_alt_outlined,
          label: l10n.takeAPhoto,
          onAction: () => controller.onAddPopupMenuButtonSelected(
            AddPopupMenuActions.photoCamera,
          ),
        ),
      if (PlatformInfos.isMobile)
        _AddMenuEntry(
          icon: Icons.gps_fixed_outlined,
          label: l10n.shareLocation,
          onAction: () => controller.onAddPopupMenuButtonSelected(
            AddPopupMenuActions.location,
          ),
        ),
      _AddMenuEntry(
        icon: Icons.attachment_outlined,
        label: l10n.sendFile,
        onAction: () =>
            controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.file),
      ),
      if (PlatformInfos.isMobile)
        _AddMenuEntry(
          icon: Icons.videocam_outlined,
          label: l10n.recordAVideo,
          onAction: () => controller.onAddPopupMenuButtonSelected(
            AddPopupMenuActions.videoCamera,
          ),
        ),
      _AddMenuEntry(
        icon: Icons.movie_outlined,
        label: l10n.sendVideo,
        onAction: () =>
            controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.video),
      ),
      _AddMenuEntry(
        icon: Icons.poll_outlined,
        label: l10n.startPoll,
        onAction: () =>
            controller.onAddPopupMenuButtonSelected(AddPopupMenuActions.poll),
      ),
      if (canCall) ...[
        _AddMenuEntry(
          icon: Icons.call_outlined,
          label: l10n.callVoice,
          onAction: () =>
              startChatCall(context, controller.room, CallType.kVoice),
        ),
        _AddMenuEntry(
          icon: Icons.videocam_outlined,
          label: l10n.callVideo,
          onAction: () =>
              startChatCall(context, controller.room, CallType.kVideo),
        ),
      ],
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 4,
          childAspectRatio: 0.82,
          children: [
            for (final entry in entries)
              _AddMenuTile(
                entry: entry,
                background: theme.colorScheme.surfaceContainerHigh,
                foreground: theme.colorScheme.onSurface,
                onTap: () => Navigator.of(context).pop(entry),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddMenuTile extends StatelessWidget {
  const _AddMenuTile({
    required this.entry,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final _AddMenuEntry entry;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(entry.icon, size: 26, color: foreground),
          ),
          const SizedBox(height: 6),
          Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: foreground),
          ),
        ],
      ),
    );
  }
}
