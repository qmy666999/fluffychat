// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// 改完自己的昵称/头像后，强制把本地 profile 缓存刷成服务器上的值。
///
/// 为什么需要：matrix-dart-sdk 的 `setProfileField()` 只发 PUT，**不会**改动本地
/// profile 缓存。而设置页、顶栏头像、账号切换菜单读的都是
/// `getUserProfile()/fetchOwnProfile()` 这条缓存路径（默认 `maxCacheAge` 是 1 天），
/// 所以改完必然还显示旧值，只有退出重登才刷新。
///
/// `maxCacheAge: Duration.zero` 会让缓存判定直接失败，从而真的去请求
/// `/_matrix/client/v3/profile/{userId}` 并写回本地缓存。
Future<void> refreshOwnProfile(Client client) async {
  final userId = client.userID;
  if (userId == null) return;
  try {
    await client.getUserProfile(userId, maxCacheAge: Duration.zero);
    // 让订阅了 onUserProfileUpdate 的界面也能拿到通知（当前主要靠 setState 重建）。
    client.onUserProfileUpdate.add(userId);
  } catch (e, s) {
    Logs().w('[Profile] Could not refresh own profile after edit', e, s);
  }
}
