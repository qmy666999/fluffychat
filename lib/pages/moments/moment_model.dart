// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:matrix/matrix.dart';

/// 朋友圈时间显示：刚刚 / N分钟前 / N小时前 / 昨天 / N天前 / MM-DD / YYYY-MM-DD
String formatMomentTime(
  int ts, {
  required String justNow,
  required String Function(int) minutesAgo,
  required String Function(int) hoursAgo,
  required String yesterday,
  required String Function(int) daysAgo,
}) {
  final now = DateTime.now();
  final time = DateTime.fromMillisecondsSinceEpoch(ts);
  final diff = now.difference(time);

  if (diff.inMinutes < 1) return justNow;
  if (diff.inHours < 1) return minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return hoursAgo(diff.inHours);

  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final days = today.difference(day).inDays;
  if (days == 1) return yesterday;
  if (days < 7) return daysAgo(days);
  if (time.year == now.year) {
    return '${_pad(time.month)}-${_pad(time.day)}';
  }
  return '${time.year}-${_pad(time.month)}-${_pad(time.day)}';
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// 把动态事件聚合成页面需要的数据。
class MomentViewData {
  final Event moment;
  final String text;
  final List<String> images;
  final int ts;
  final List<String> likers;
  final List<MomentComment> comments;
  final bool likedByMe;

  const MomentViewData({
    required this.moment,
    required this.text,
    required this.images,
    required this.ts,
    required this.likers,
    required this.comments,
    required this.likedByMe,
  });

  String get id => moment.eventId;
  String get senderId => moment.senderId;
}

List<MomentViewData> buildMomentViews(
  List<Event> events, {
  required String? userId,
}) {
  final moments = MomentsService.momentEvents(events);
  return moments.map((moment) {
    return MomentViewData(
      moment: moment,
      text: moment.content['text'] as String? ?? '',
      images: MomentsService.images(moment),
      ts: MomentsService.momentTs(moment),
      likers: MomentsService.reactions(events, moment),
      comments: MomentsService.comments(events, moment),
      likedByMe: MomentsService.hasLiked(events, moment, userId),
    );
  }).toList();
}
