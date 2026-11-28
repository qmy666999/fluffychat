// SPDX-FileCopyrightText: 2026 FluffyChatX contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 好友备注。
///
/// Matrix 没有原生备注，改对方 displayname / 改房间名都会被对方看到，所以存在
/// **自己的** account data 里（只对自己生效、换设备同步过来）：
///
/// ```json
/// { "@user:server": "小明" }
/// ```
///
/// key 是完整 user id，删除备注 = 把这个 key 去掉（不存空字符串）。
/// 备注也可能用在非好友身上，所以不进 `com.dafeiyu.friends`。
class RemarkService {
  static const String eventType = 'com.dafeiyu.remarks';

  /// 备注最多 32 个字符（按字符数算，emoji 算一个）。
  static const int maxLength = 32;

  /// 备注改动后 +1，界面用它来立刻刷新（不用等下一次 sync）。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Client client;

  const RemarkService(this.client);

  Map<String, String> load() {
    final result = <String, String>{};
    // 兼容老数据：1.18 之前加好友时备注写在 `com.dafeiyu.friends`
    // 的 friends[].remark 里，读的时候两边都查（独立 key 优先）。
    final friendsRaw =
        client.accountData[FriendsService.friendsEventType]?.content['friends'];
    if (friendsRaw is List) {
      for (final item in friendsRaw) {
        if (item is! Map) continue;
        final userId = item['user_id'];
        final remark = item['remark'];
        if (userId is! String || remark is! String) continue;
        final trimmed = remark.trim();
        if (trimmed.isEmpty) continue;
        result[userId] = trimmed;
      }
    }
    final content = client.accountData[eventType]?.content;
    if (content != null) {
      for (final entry in content.entries) {
        final key = entry.key;
        final value = entry.value;
        if (!key.startsWith('@') || value is! String) continue;
        final trimmed = value.trim();
        if (trimmed.isEmpty) continue;
        result[key] = trimmed;
      }
    }
    return result;
  }

  String? remarkOf(String userId) => load()[userId];

  /// 保存备注；[remark] 为 null 或全空白时删除这个 key。
  Future<void> setRemark(String userId, String? remark) async {
    final current = Map<String, String>.from(load());
    final value = remark?.trim();
    if (value == null || value.isEmpty) {
      if (!current.containsKey(userId)) return;
      current.remove(userId);
    } else {
      current[userId] = value.length > maxLength
          ? value.substring(0, maxLength)
          : value;
    }
    final content = <String, Object?>{
      for (final entry in current.entries) entry.key: entry.value,
    };
    // 先镜像到本地缓存，再写服务器：setAccountData 只是 HTTP，不会更新 client.accountData，
    // 不镜像的话界面要等下一次 sync 才变。
    client.accountData[eventType] = BasicEvent(
      type: eventType,
      content: content,
    );
    revision.value++;
    final me = client.userID;
    if (me != null) {
      await client.setAccountData(me, eventType, content);
    }
    // 两套存储保持一致：加好友时会写 friends[].remark（老数据），
    // 这里顺手也写一份，免得通讯录和聊天列表各读一份对不上。
    try {
      final synced = content[userId];
      await FriendsService(
        client,
      ).setRemark(userId, synced is String ? synced : '');
    } catch (error, stackTrace) {
      Logs().w('[remark] 同步到好友列表失败', error, stackTrace);
    }
  }

  /// 全 App 统一的显示名：
  /// ① 备注 ② 房间成员昵称（调用方传进来） ③ user id 的 localpart。
  static String displayNameOf(
    Client client,
    String userId, {
    String? fallback,
  }) {
    final remark = RemarkService(client).remarkOf(userId);
    if (remark != null && remark.trim().isNotEmpty) return remark.trim();
    final name = fallback?.trim();
    if (name != null && name.isNotEmpty) return name;
    return userId.localpart ?? userId;
  }
}

/// 弹出「设置备注」弹窗。
///
/// 返回 true 表示改过了（调用方需要刷新界面）。
Future<bool> showRemarkDialog(
  BuildContext context,
  String userId, {
  String? originalName,
}) async {
  final l10n = L10n.of(context);
  final client = Matrix.of(context).client;
  final service = RemarkService(client);
  final current = service.remarkOf(userId);
  final controller = TextEditingController(text: current ?? '');
  var result = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final hasRemark = service.remarkOf(userId) != null;
          Future<void> apply(String? value) async {
            await service.setRemark(userId, value);
            controller.text = value ?? '';
            result = true;
            if (context.mounted) setState(() {});
          }

          return AlertDialog(
            title: Text(l10n.setRemark),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: RemarkService.maxLength,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: l10n.remarkHint,
                    counterText: '',
                  ),
                  onSubmitted: (value) async {
                    await apply(value);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.remarkOnlyYouCanSee,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (originalName != null && originalName.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.nicknameLabel(originalName),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            actions: [
              if (hasRemark)
                TextButton(
                  onPressed: () async {
                    await apply(null);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(l10n.clear),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  await apply(controller.text);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: Text(l10n.save),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
