// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// 聊天页顶部的「正在通话中」横条。
///
/// 通话页被最小化、或者用户滑回了聊天页时出现，点一下就能回到通话页，
/// 右侧按钮可以直接挂断 —— 这是「卡在通话里出不来」的兜底出口。
class ActiveCallBanner extends StatefulWidget {
  const ActiveCallBanner({super.key, required this.roomId});

  final String roomId;

  @override
  State<ActiveCallBanner> createState() => _ActiveCallBannerState();
}

class _ActiveCallBannerState extends State<ActiveCallBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    MatrixVoip.activeSession.addListener(_onChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _visibleCall() != null) setState(() {});
    });
  }

  @override
  void dispose() {
    MatrixVoip.activeSession.removeListener(_onChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  CallSession? _visibleCall() {
    final call = MatrixVoip.activeSession.value;
    if (call == null || call.room.id != widget.roomId) return null;
    return call;
  }

  String _durationText(CallSession call) {
    final startedAt = MatrixVoip.of(call.room.client)?.connectedAt;
    if (call.state != CallState.kConnected || startedAt == null) return '';
    final seconds = DateTime.now().difference(startedAt).inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final call = _visibleCall();
    if (call == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final duration = _durationText(call);
    final label = duration.isEmpty
        ? l10n.callWaiting
        : l10n.callInProgress(duration);

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: MatrixVoip.openCallPage,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: MatrixVoip.openCallPage,
                child: Text(l10n.callBackToCall),
              ),
              IconButton(
                tooltip: l10n.callHangup,
                color: scheme.error,
                icon: const Icon(Icons.call_end),
                onPressed: () async {
                  final voip = MatrixVoip.of(call.room.client);
                  await voip?.hangup();
                  await voip?.clear();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
