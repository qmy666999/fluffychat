// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';

import 'moment_model.dart';

/// 好友朋友圈按日期分组，返回给页面渲染「左侧大日期 + 右侧动态」。
class MomentDateGroup {
  final String topLine;
  final String? bottomLine;
  final List<MomentViewData> moments;

  const MomentDateGroup({
    required this.topLine,
    this.bottomLine,
    required this.moments,
  });
}

/// 今天 / 昨天 / 23 + 11月 / 2025 + 11月。
List<MomentDateGroup> groupMomentsByDate(
  List<MomentViewData> moments, {
  L10n? l10n,
}) {
  final groups = <String, MomentDateGroup>{};
  final now = DateTime.now();

  for (final moment in moments) {
    final time = DateTime.fromMillisecondsSinceEpoch(moment.ts);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diffDays = today.difference(day).inDays;

    final String key;
    final String topLine;
    final String? bottomLine;
    if (diffDays == 0) {
      key = 'today';
      topLine = l10n?.today ?? '今天';
      bottomLine = null;
    } else if (diffDays == 1) {
      key = 'yesterday';
      topLine = l10n?.timeYesterday ?? '昨天';
      bottomLine = null;
    } else if (time.year == now.year) {
      key = '${time.year}-${time.month}-${time.day}';
      topLine = '${time.day}';
      bottomLine = '${time.month}月';
    } else {
      key = '${time.year}-${time.month}-${time.day}';
      topLine = '${time.year}';
      bottomLine = '${time.month}月';
    }

    final existing = groups[key];
    if (existing == null) {
      groups[key] = MomentDateGroup(
        topLine: topLine,
        bottomLine: bottomLine,
        moments: [moment],
      );
    } else {
      existing.moments.add(moment);
    }
  }
  return groups.values.toList();
}
