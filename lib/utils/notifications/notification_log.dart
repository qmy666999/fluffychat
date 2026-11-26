// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// 一条通知诊断日志。
class NotificationLogEntry {
  const NotificationLogEntry(this.time, this.message);

  /// `HH:mm:ss`。
  final String time;
  final String message;

  @override
  String toString() => '$time  $message';
}

/// 「收消息 → 发通知」这条链路的环形日志。
///
/// 手机上没有 adb，出问题时无法抓 logcat，所以这里把关键节点同时存进内存，
/// 在「设置 → 新消息通知 → 通知诊断」里直接显示出来：用户复现一次，截图就
/// 能看出是没收到事件、被某个条件跳过，还是 `show()` 抛了异常。
class NotificationLog {
  NotificationLog._();

  /// 最多保留多少条（最新的在最前面）。
  static const int capacity = 60;

  static final List<NotificationLogEntry> _entries = <NotificationLogEntry>[];

  /// 供界面监听刷新用。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 最新的在最前面。
  static List<NotificationLogEntry> get entries =>
      List<NotificationLogEntry>.unmodifiable(_entries);

  static bool get isEmpty => _entries.isEmpty;

  static void add(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _entries.insert(0, NotificationLogEntry(time, message));
    if (_entries.length > capacity) _entries.removeLast();
    revision.value++;
    Logs().i('[notif] $message');
  }

  static void clear() {
    _entries.clear();
    revision.value++;
  }
}
