// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 重发一条发送失败的消息（微信式「点感叹号重发」）。
///
/// 失败时把原因吐到 SnackBar，返回是否重发成功。调用方负责转圈之类的界面状态。
Future<bool> retryFailedMessage(BuildContext context, Event event) async {
  final l10n = L10n.of(context);
  final sender = event.senderId;
  try {
    await event.sendAgain();
    return true;
  } on FileNoLongerInCacheException catch (_) {
    AppToast.show(l10n.messageResendFileMissing);
  } catch (e, s) {
    Logs().w('[message] 重发失败 event=${event.eventId} sender=$sender', e, s);
    AppToast.show(l10n.messageResendFailed);
  }
  return false;
}

/// 丢弃一条发送失败的消息（本地删除，不会发到服务器）。
Future<void> discardFailedMessage(BuildContext context, Event event) async {
  try {
    await event.cancelSend();
  } catch (e, s) {
    Logs().w('[message] 删除失败消息出错 event=${event.eventId}', e, s);
  }
}
