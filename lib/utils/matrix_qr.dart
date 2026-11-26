// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

enum MatrixQrType { user, room, alias, unknown }

class MatrixQrResult {
  final MatrixQrType type;

  /// user → `@a:b`；room → `!a:b`；alias → `#a:b`。
  final String? value;

  const MatrixQrResult(this.type, [this.value]);
}

/// 解析扫描到的内容：兼容 matrix.to 链接、裸 ID、房间别名。
///
/// 支持：
/// ```
/// https://matrix.to/#/@me:qmypc.tail7337aa.ts.net
/// https://matrix.to/#/!abc:server?via=server
/// https://matrix.to/#/#moments:server
/// @me:server        !abc:server        #moments:server
/// ```
MatrixQrResult parseMatrixQr(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const MatrixQrResult(MatrixQrType.unknown);

  final user = RegExp(
    r'@[A-Za-z0-9._=\-/]+:[A-Za-z0-9.\-]+(?::\d+)?',
  ).firstMatch(text);
  if (user != null) {
    return MatrixQrResult(MatrixQrType.user, user.group(0));
  }

  final room = RegExp(
    r'![A-Za-z0-9]+:[A-Za-z0-9.\-]+(?::\d+)?',
  ).firstMatch(text);
  if (room != null) {
    return MatrixQrResult(MatrixQrType.room, room.group(0));
  }

  final alias = RegExp(
    r'#[A-Za-z0-9._=\-/]+:[A-Za-z0-9.\-]+(?::\d+)?',
  ).firstMatch(text);
  if (alias != null) {
    return MatrixQrResult(MatrixQrType.alias, alias.group(0));
  }

  return const MatrixQrResult(MatrixQrType.unknown);
}
