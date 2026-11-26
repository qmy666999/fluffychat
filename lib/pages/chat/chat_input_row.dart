// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'chat_add_menu.dart';
import 'input_bar.dart';

/// 微信式输入栏：
///
///   [麦克风/键盘] [输入框 或 按住说话] [表情] [+]
///
/// 语音模式下没有发送按钮，靠「按住说、松开发送、上滑取消」。
class ChatInputRow extends StatefulWidget {
  final ChatController controller;

  static const double height = 56.0;

  const ChatInputRow(this.controller, {super.key});

  @override
  State<ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<ChatInputRow> {
  /// 语音模式（左边图标变键盘，输入框换成「按住 说话」）
  bool _voiceMode = false;

  /// 手指是否按在「按住 说话」上
  bool _pressing = false;

  /// 上滑是否超过取消阈值
  bool _willCancel = false;

  /// 取消阈值，向上滑超过这个距离就丢弃这条语音
  static const double _cancelThreshold = 60;

  int? _pointer;
  Offset? _downPosition;

  ChatController get controller => widget.controller;

  Future<void> _startHold(RecordingViewModelState recording) async {
    if (recording.isRecording) return;
    await recording.startRecording(controller.room);
    if (!mounted) return;
    if (recording.isRecording && !_pressing) {
      // 等权限的时候手指已经松开，别让它一直录下去
      recording.cancel();
      return;
    }
    if (!recording.isRecording) {
      // 没有麦克风权限或者启动失败，恢复按钮文案
      setState(() => _pressing = false);
    }
  }

  void _onPointerDown(
    PointerDownEvent event,
    RecordingViewModelState recording,
  ) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downPosition = event.position;
    setState(() {
      _pressing = true;
      _willCancel = false;
    });
    _startHold(recording);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final start = _downPosition;
    if (start == null) return;
    final willCancel = start.dy - event.position.dy > _cancelThreshold;
    if (willCancel != _willCancel) {
      setState(() => _willCancel = willCancel);
    }
  }

  Future<void> _finishHold(RecordingViewModelState recording) async {
    if (_pointer == null) return;
    _pointer = null;
    _downPosition = null;
    final cancel = _willCancel;
    final tooShort = recording.duration < const Duration(seconds: 1);
    final wasRecording = recording.isRecording;
    setState(() {
      _pressing = false;
      _willCancel = false;
    });
    if (!wasRecording) return;
    if (cancel) {
      recording.cancel();
      return;
    }
    if (tooShort) {
      recording.cancel();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(L10n.of(context).voiceRecordingTooShort)),
      );
      return;
    }
    await recording.stopAndSend(controller.onVoiceMessageSend);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMessageOnly =
        controller.sendController.text.isNotEmpty ||
        controller.replyEvent != null ||
        controller.editEvent != null;

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RecordingViewModel(
      builder: (context, recording) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            controller.selectMode
                ? _buildSelectMode(context, theme)
                : _buildComposer(
                    context,
                    theme,
                    recording,
                    textMessageOnly: textMessageOnly,
                  ),
            if (recording.isRecording)
              Positioned(
                left: 12,
                right: 12,
                bottom: ChatInputRow.height + 8,
                child: _RecordingOverlay(
                  recording: recording,
                  willCancel: _willCancel,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildComposer(
    BuildContext context,
    ThemeData theme,
    RecordingViewModelState recording, {
    required bool textMessageOnly,
  }) {
    final canRecord = PlatformInfos.platformCanRecord;
    final l10n = L10n.of(context);
    final showSendButton = !_voiceMode && textMessageOnly;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. 语音 / 键盘切换
          if (canRecord)
            SizedBox(
              height: ChatInputRow.height - 12,
              width: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: _voiceMode ? l10n.keyboardMode : l10n.voiceMessage,
                color: theme.colorScheme.onPrimaryContainer,
                icon: Icon(
                  _voiceMode
                      ? Icons.keyboard_outlined
                      : Icons.mic_none_outlined,
                ),
                onPressed: () {
                  if (recording.isRecording) return;
                  setState(() => _voiceMode = !_voiceMode);
                },
              ),
            ),
          // 2. 中间：输入框 或 按住说话
          Expanded(
            child: _voiceMode
                ? _buildHoldToTalk(context, theme, recording)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: _buildInputBar(context),
                  ),
          ),
          // 3. 表情
          SizedBox(
            height: ChatInputRow.height - 12,
            width: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: l10n.emojis,
              color: theme.colorScheme.onPrimaryContainer,
              icon: Icon(
                controller.showEmojiPicker
                    ? Icons.keyboard
                    : Icons.add_reaction_outlined,
                key: ValueKey(controller.showEmojiPicker),
              ),
              onPressed: controller.emojiPickerAction,
            ),
          ),
          if (!_voiceMode &&
              Matrix.of(context).isMultiAccount &&
              Matrix.of(context).hasComplexBundles &&
              Matrix.of(context).currentBundle!.length > 1)
            SizedBox(
              height: ChatInputRow.height - 12,
              width: 40,
              child: Center(child: _ChatAccountPicker(controller)),
            ),
          // 4. 最右：有文字时是发送，否则是加号
          SizedBox(
            height: ChatInputRow.height - 12,
            width: 48,
            child: Center(
              child: showSendButton
                  ? IconButton(
                      key: const Key('send_button'),
                      tooltip: l10n.send,
                      onPressed: controller.send,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.bubbleColor,
                        foregroundColor: theme.onBubbleColor,
                      ),
                      icon: const Icon(Icons.send_outlined),
                    )
                  : ChatAddMenuButton(controller: controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final l10n = L10n.of(context);
    return InputBar(
      room: controller.room,
      minLines: 1,
      maxLines: 8,
      autofocus: !PlatformInfos.isMobile,
      keyboardType: TextInputType.multiline,
      textInputAction:
          AppSettings.sendOnEnter.value == true && PlatformInfos.isMobile
          ? TextInputAction.send
          : null,
      onSubmitted: controller.onInputBarSubmitted,
      onSubmitImage: controller.sendImageFromClipBoard,
      focusNode: controller.inputFocus,
      controller: controller.sendController,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.only(
          left: 12.0,
          right: 12.0,
          bottom: 10.0,
          top: 10.0,
        ),
        counter: const SizedBox.shrink(),
        hintText: controller.room.encrypted
            ? l10n.encryptedMessage
            : l10n.unencryptedMessage,
        hintMaxLines: 1,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: controller.onInputBarChanged,
      suggestionEmojis: getDefaultEmojiLocale(
        AppSettings.emojiSuggestionLocale.value.isNotEmpty
            ? Locale(AppSettings.emojiSuggestionLocale.value)
            : Localizations.localeOf(context),
      ).fold([], (emojis, category) => emojis..addAll(category.emoji)),
    );
  }

  Widget _buildHoldToTalk(
    BuildContext context,
    ThemeData theme,
    RecordingViewModelState recording,
  ) {
    final l10n = L10n.of(context);
    final colorScheme = theme.colorScheme;
    final active = _pressing || recording.isRecording;
    final color = !active
        ? colorScheme.surfaceContainerHighest
        : _willCancel
        ? colorScheme.error.withValues(alpha: 0.28)
        : colorScheme.primary.withValues(alpha: 0.24);
    final label = !active
        ? l10n.holdToSpeak
        : _willCancel
        ? l10n.releaseToCancel
        : l10n.releaseToSend;

    return Listener(
      onPointerDown: (event) => _onPointerDown(event, recording),
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _finishHold(recording),
      onPointerCancel: (_) => _finishHold(recording),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: _willCancel && active
                ? colorScheme.error
                : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectMode(BuildContext context, ThemeData theme) {
    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );
    final l10n = L10n.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        if (controller.selectedEvents.every(
          (event) => event.status == EventStatus.error,
        ))
          SizedBox(
            height: ChatInputRow.height,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: controller.deleteErrorEventsAction,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.delete_forever_outlined),
                  Text(l10n.delete),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: ChatInputRow.height,
            child: TextButton(
              style: selectedTextButtonStyle,
              onPressed: controller.forwardEventsAction,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.keyboard_arrow_left_outlined),
                  Text(l10n.forward),
                ],
              ),
            ),
          ),
        controller.selectedEvents.length == 1
            ? controller.selectedEvents.first
                      .getDisplayEvent(controller.timeline!)
                      .status
                      .isSent
                  ? SizedBox(
                      height: ChatInputRow.height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.replyAction,
                        child: Row(
                          children: <Widget>[
                            Text(l10n.reply),
                            const Icon(Icons.keyboard_arrow_right),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: ChatInputRow.height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.sendAgainAction,
                        child: Row(
                          children: <Widget>[
                            Text(l10n.tryToSendAgain),
                            const SizedBox(width: 4),
                            const Icon(Icons.send_outlined, size: 16),
                          ],
                        ),
                      ),
                    )
            : const SizedBox.shrink(),
      ],
    );
  }
}

/// 录音时浮在输入栏上方的小面板：声波 + 时长 + 松手提示。
class _RecordingOverlay extends StatelessWidget {
  const _RecordingOverlay({required this.recording, required this.willCancel});

  final RecordingViewModelState recording;
  final bool willCancel;

  static const int _bars = 24;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final duration = recording.duration;
    final amplitudes = recording.amplitudeTimeline;
    final recent = amplitudes.length > _bars
        ? amplitudes.sublist(amplitudes.length - _bars)
        : amplitudes;
    final accent = willCancel ? theme.colorScheme.error : Colors.white;

    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < _bars; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 3,
                        height: _barHeight(i, recent),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _durationLabel(duration),
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  willCancel ? l10n.releaseToCancel : l10n.releaseToSend,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _barHeight(int index, List<double> amplitudes) {
    if (index >= amplitudes.length) return 4;
    final value = amplitudes[index].clamp(0, 200) / 200;
    return 4 + value * 32;
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ChatAccountPicker extends StatelessWidget {
  final ChatController controller;

  const _ChatAccountPicker(this.controller);

  void _popupMenuButtonSelected(String mxid, BuildContext context) {
    final client = Matrix.of(
      context,
    ).currentBundle!.firstWhere((cl) => cl!.userID == mxid, orElse: () => null);
    if (client == null) {
      Logs().w('Attempted to switch to a non-existing client $mxid');
      return;
    }
    controller.setSendingClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final clients = controller.currentRoomBundle;
    return FutureBuilder<Profile>(
      future: controller.sendingClient.fetchOwnProfile(),
      builder: (context, snapshot) => PopupMenuButton<String>(
        useRootNavigator: true,
        onSelected: (mxid) => _popupMenuButtonSelected(mxid, context),
        itemBuilder: (BuildContext context) => clients
            .map(
              (client) => PopupMenuItem(
                value: client!.userID,
                child: FutureBuilder<Profile>(
                  future: client.fetchOwnProfile(),
                  builder: (context, snapshot) => ListTile(
                    leading: Avatar(
                      mxContent: snapshot.data?.avatarUrl,
                      name:
                          snapshot.data?.displayName ??
                          client.userID!.localpart,
                      size: 20,
                    ),
                    title: Text(snapshot.data?.displayName ?? client.userID!),
                    contentPadding: const EdgeInsets.all(0),
                  ),
                ),
              ),
            )
            .toList(),
        child: Avatar(
          mxContent: snapshot.data?.avatarUrl,
          name:
              snapshot.data?.displayName ??
              Matrix.of(context).client.userID!.localpart,
          size: 20,
        ),
      ),
    );
  }
}
