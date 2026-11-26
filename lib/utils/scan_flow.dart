// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/utils/matrix_qr.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 扫一扫：用户码 → 去加好友；房间码/别名 → 直接进群。
///
/// 相机权限被拒、扫到无效码都会给一句人话提示，不会静默失败。
Future<void> startMatrixScan(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => QrScannerModal(onScan: (_) {})),
  );
  if (!context.mounted || raw == null || raw.isEmpty) return;

  final l10n = L10n.of(context);
  final client = Matrix.of(context).client;
  final parsed = parseMatrixQr(raw);

  switch (parsed.type) {
    case MatrixQrType.user:
      // 直接带到「添加朋友」页并自动搜索
      context.push('/contacts/add?q=${Uri.encodeComponent(parsed.value!)}');
      break;
    case MatrixQrType.room:
      try {
        final roomId = parsed.value!;
        await client.joinRoomById(roomId);
        if (!context.mounted) return;
        context.go('/rooms/$roomId');
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.scanJoinFailed(e.toString()))),
        );
      }
      break;
    case MatrixQrType.alias:
      try {
        final resolved = await client.getRoomIdByAlias(parsed.value!);
        final roomId = resolved.roomId;
        if (roomId == null) throw Exception(parsed.value);
        await client.joinRoomById(roomId);
        if (!context.mounted) return;
        context.go('/rooms/$roomId');
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.scanJoinFailed(e.toString()))),
        );
      }
      break;
    case MatrixQrType.unknown:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.scanInvalidQr)));
      break;
  }
}
