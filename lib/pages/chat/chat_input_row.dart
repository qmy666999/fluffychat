// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

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

  /// 取消阈值：向上滑超过这个距离、并且往左滑出 [_cancelSideThreshold]，
  /// 才算进入左上角的「取消」区（微信是斜着往左上丢）
  static const double _cancelThreshold = 80;
  static const double _cancelSideThreshold = 60;

  /// 录音上限，到点自动发送
  static const Duration _maxDuration = Duration(seconds: 60);

  int? _pointer;
  Offset? _downPosition;
  Timer? _maxDurationTimer;

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
      return;
    }
    // 录满 60 秒自动发送（微信的上限）
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(_maxDuration, () => _autoSend(recording));
  }

  /// 到 60 秒上限时自动结束并发送，不需要用户松手
  Future<void> _autoSend(RecordingViewModelState recording) async {
    if (_pointer == null || !recording.isRecording) return;
    _pointer = null;
    _downPosition = null;
    setState(() {
      _pressing = false;
      _willCancel = false;
    });
    await recording.stopAndSend(controller.onVoiceMessageSend);
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
    // 用「相对按下位置的偏移」判断，不写死坐标：往上 80dp 且往左 60dp 才算取消
    final dy = start.dy - event.position.dy;
    final dx = start.dx - event.position.dx;
    final willCancel = dy > _cancelThreshold && dx > _cancelSideThreshold;
    if (willCancel != _willCancel) {
      setState(() => _willCancel = willCancel);
    }
  }

  Future<void> _finishHold(RecordingViewModelState recording) async {
    if (_pointer == null) return;
    _pointer = null;
    _downPosition = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(L10n.of(context).voiceRecordingCancelled)),
      );
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
  void dispose() {
    _maxDurationTimer?.cancel();
    super.dispose();
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
                left: 0,
                right: 0,
                // 浮层要出现在屏幕中上部（微信的位置），所以按屏幕高度反推底部距离；
                // Stack 本身只有输入栏那么高，用负/clipBehavior: none 让它画到外面去。
                bottom: MediaQuery.sizeOf(context).height * 0.5,
                child: IgnorePointer(
                  child: Center(
                    child: _RecordingOverlay(
                      recording: recording,
                      willCancel: _willCancel,
                    ),
                  ),
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

/// 微信式录音浮层：胶囊 + 柱状声波 + 时长。
///
/// 不要再做成圆圈向外扩散的波纹——那是录音机 App 的风格，
/// 微信是**横向柱状波**：中间高两边低，随音量起伏，新的从右边进来。
class _RecordingOverlay extends StatefulWidget {
  const _RecordingOverlay({required this.recording, required this.willCancel});

  final RecordingViewModelState recording;
  final bool willCancel;

  @override
  State<_RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<_RecordingOverlay>
    with SingleTickerProviderStateMixin {
  /// 柱子根数（微信大约 30~40 根）
  static const int _barCount = 36;

  /// 从右往左滚动的音量序列，长度固定 _barCount
  final List<double> _levels = <double>[];

  /// 平滑后的当前音量（0..1），避免柱子一跳一跳
  double _smoothed = 0;

  Timer? _ticker;
  late final AnimationController _appear;
  int _elapsedTicks = 0;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
    // 先铺一段静态波形，避免刚按下时是一条直线
    for (var i = 0; i < _barCount; i++) {
      _levels.add(0.2 + 0.6 * math.sin(i / 4).abs());
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _appear.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    _elapsedTicks++;
    final target = _currentLevel;
    // 起音快、回落慢，看起来才像在说话
    final factor = target > _smoothed ? 0.55 : 0.22;
    _smoothed = math.max(
      0.05,
      math.min(1.0, _smoothed + (target - _smoothed) * factor),
    );
    setState(() {
      _levels.add(_smoothed);
      while (_levels.length > _barCount) {
        _levels.removeAt(0);
      }
    });
  }

  /// 当前音量（0..1）。
  ///
  /// record 的 Amplitude.current 是 dBFS（负数），RecordingViewModel 已经
  /// 映射成 1~100，不同机型量级还不一样，所以这里按「最近 40 个采样的峰值」
  /// 归一化，而不是写死上下限；拿不到真实振幅时退化成 sin 伪波形。
  double get _currentLevel {
    final amplitudes = widget.recording.amplitudeTimeline;
    if (amplitudes.isEmpty) return _pseudoLevel;
    if (amplitudes.length >= 6) {
      final tail = amplitudes.sublist(amplitudes.length - 6);
      final flat = tail.every((value) => (value - tail.first).abs() < 0.5);
      if (flat) return _pseudoLevel;
    }
    final recent = amplitudes.length <= 40
        ? amplitudes
        : amplitudes.sublist(amplitudes.length - 40);
    var peak = 0.0;
    for (final value in recent) {
      if (value > peak) peak = value;
    }
    // 全程都是 1 这种恒定值（有些机型拿不到真实音量）→ 伪波形
    if (peak <= 1.5) return _pseudoLevel;
    return math.max(0.05, math.min(1.0, amplitudes.last / peak));
  }

  double get _pseudoLevel {
    final t = _elapsedTicks / 10;
    return 0.2 + 0.6 * math.sin(t * 2.2).abs();
  }

  String get _durationLabel {
    final duration = widget.recording.duration;
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cancelling = widget.willCancel;
    final background = cancelling ? colorScheme.error : colorScheme.primary;
    final foreground = cancelling ? colorScheme.onError : colorScheme.onPrimary;
    final width = math.min(260.0, MediaQuery.sizeOf(context).width * 0.7);

    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.8,
        end: 1,
      ).animate(CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: _appear,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          height: 90,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                  child: CustomPaint(
                    painter: _WavePainter(
                      levels: List<double>.of(_levels),
                      color: foreground,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 8,
                child: Text(
                  _durationLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: foreground.withValues(alpha: 0.85),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 柱状声波：中间高两边低，柱子从右往左滚。
class _WavePainter extends CustomPainter {
  const _WavePainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  static const double _barWidth = 3;
  static const double _gap = 2;
  static const double _minHeight = 4;
  static const double _maxHeight = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final total = levels.length;
    if (total == 0) return;
    const step = _barWidth + _gap;
    final startX = (size.width - (step * total - _gap)) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < total; i++) {
      // 山形包络：中间 1.0，两端 0.45
      final distance = (i - (total - 1) / 2).abs() / ((total - 1) / 2);
      final envelope = 1 - distance * 0.55;
      final height =
          _minHeight + levels[i] * (_maxHeight - _minHeight) * envelope;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(startX + i * step + _barWidth / 2, size.height / 2),
          width: _barWidth,
          height: height,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.levels.length != levels.length) return true;
    for (var i = 0; i < levels.length; i++) {
      if (oldDelegate.levels[i] != levels[i]) return true;
    }
    return false;
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
