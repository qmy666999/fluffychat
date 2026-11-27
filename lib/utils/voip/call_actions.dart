// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/voip/matrix_voip.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// 发起 1 对 1 通话，并把全屏通话页打开。
///
/// 聊天页右上角菜单、「+」面板、好友资料页都走这里，保证行为一致：
/// 已经有通话时给出「返回通话」的出口，失败时给出提示。
Future<void> startChatCall(
  BuildContext context,
  Room room,
  CallType type,
) async {
  final l10n = L10n.of(context);
  void showAlreadyInCall() {
    AppToast.show(
      l10n.callAlreadyInCall,
      action: AppToastAction(
        label: l10n.callBackToCall,
        onPressed: MatrixVoip.openCallPage,
      ),
    );
  }

  final voip = MatrixVoip.ensure(room.client);
  if (voip.hasCall) {
    showAlreadyInCall();
    return;
  }
  try {
    Logs().i('[VoIP] 点击通话 type=${type.name} room=${room.id}');
    final call = await voip.startCall(room, type);
    Logs().i('[VoIP] invite 完成 call=${call?.callId}');
    if (call == null) {
      showAlreadyInCall();
      return;
    }
    MatrixVoip.openCallPage();
  } catch (e, s) {
    Logs().w('[VoIP] 发起通话失败', e, s);
    AppToast.show(l10n.callStartFailed);
  }
}
