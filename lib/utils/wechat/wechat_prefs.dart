// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

/// 微信式界面里那些「只在本机记着」的开关。
///
/// 这些开关不影响任何 Matrix 协议行为，所以只放 SharedPreferences，
/// 不上服务器、不在多设备间同步（微信群里的同类开关也是本机设置）。
class WechatPrefs {
  WechatPrefs._();

  static SharedPreferences? _store;

  /// App 启动时由 main() 传入已经初始化好的 store。
  static void init(SharedPreferences store) => _store = store;

  static SharedPreferences? get store => _store;

  static const String _discoverOrderKey = 'wechat_discover_order';
  static const String _discoverHiddenKey = 'wechat_discover_hidden';

  /// 发现页入口的标识，顺序即显示顺序。
  static const List<String> discoverIds = ['moments', 'scan'];

  // ---------------------------------------------------------------- 发现页

  /// 显示顺序（只包含已知入口，老数据里多出来的会被忽略）。
  static List<String> get discoverOrder {
    final raw = _store?.getStringList(_discoverOrderKey);
    if (raw == null || raw.isEmpty) return List<String>.from(discoverIds);
    final known = raw.where(discoverIds.contains).toList();
    for (final id in discoverIds) {
      if (!known.contains(id)) known.add(id);
    }
    return known;
  }

  static Future<void> setDiscoverOrder(List<String> order) async {
    await _store?.setStringList(_discoverOrderKey, order);
  }

  static bool isDiscoverHidden(String id) =>
      _store?.getStringList(_discoverHiddenKey)?.contains(id) ?? false;

  static Future<void> setDiscoverHidden(String id, bool hidden) async {
    final current = (_store?.getStringList(_discoverHiddenKey) ?? <String>[])
        .toSet();
    if (hidden) {
      current.add(id);
    } else {
      current.remove(id);
    }
    await _store?.setStringList(_discoverHiddenKey, current.toList());
  }

  // ------------------------------------------------------------ 图片发送

  static const String _sendOriginalImagesKey = 'wechat_send_original_images';

  /// 发送原图：打开后不再压缩图片，直接上传原始文件（很慢，慎用）。
  static bool get sendOriginalImages =>
      _store?.getBool(_sendOriginalImagesKey) ?? false;

  static Future<void> setSendOriginalImages(bool value) async {
    await _store?.setBool(_sendOriginalImagesKey, value);
  }

  // ------------------------------------------------------------ 消息提醒

  static const String _notifyReceiveKey = 'wechat_notify_receive';
  static const String _notifyDetailKey = 'wechat_notify_detail';
  static const String _notifyCallKey = 'wechat_notify_call';
  static const String _notifySoundKey = 'wechat_notify_sound';
  static const String _notifyRingtoneKey = 'wechat_notify_ringtone';
  static const String _notifyVibrateKey = 'wechat_notify_vibrate';

  /// 接收新消息通知（默认开）。
  static bool get notifyReceive => _store?.getBool(_notifyReceiveKey) ?? true;
  static Future<void> setNotifyReceive(bool value) async =>
      _store?.setBool(_notifyReceiveKey, value);

  /// 通知里显示消息详情（默认关，和微信一致：锁屏只显示「你收到一条消息」）。
  static bool get notifyDetail => _store?.getBool(_notifyDetailKey) ?? false;
  static Future<void> setNotifyDetail(bool value) async =>
      _store?.setBool(_notifyDetailKey, value);

  /// 语音和视频通话邀请提醒（默认开）。
  static bool get notifyCall => _store?.getBool(_notifyCallKey) ?? true;
  static Future<void> setNotifyCall(bool value) async =>
      _store?.setBool(_notifyCallKey, value);

  /// 消息提示音（默认开）。
  static bool get notifySound => _store?.getBool(_notifySoundKey) ?? true;
  static Future<void> setNotifySound(bool value) async =>
      _store?.setBool(_notifySoundKey, value);

  /// 来电铃声（默认开）。
  static bool get notifyRingtone => _store?.getBool(_notifyRingtoneKey) ?? true;
  static Future<void> setNotifyRingtone(bool value) async =>
      _store?.setBool(_notifyRingtoneKey, value);

  /// 震动（默认开）。
  static bool get notifyVibrate => _store?.getBool(_notifyVibrateKey) ?? true;
  static Future<void> setNotifyVibrate(bool value) async =>
      _store?.setBool(_notifyVibrateKey, value);

  // ---------------------------------------------------------------- 聊天

  static const String _chatEarpieceKey = 'wechat_chat_earpiece';
  static const String _chatEnterToSendKey = 'wechat_chat_enter_to_send';

  /// 使用听筒播放语音（默认关，蓝牙/外放优先）。
  static bool get chatEarpiece => _store?.getBool(_chatEarpieceKey) ?? false;
  static Future<void> setChatEarpiece(bool value) async =>
      _store?.setBool(_chatEarpieceKey, value);

  /// 回车键发送消息（桌面端才有意义，默认开）。
  static bool get chatEnterToSend =>
      _store?.getBool(_chatEnterToSendKey) ?? true;
  static Future<void> setChatEnterToSend(bool value) async =>
      _store?.setBool(_chatEnterToSendKey, value);

  // ---------------------------------------------------------------- 通用

  static const String _landscapeKey = 'wechat_landscape_mode';

  /// 横屏模式（默认关）。
  static bool get landscapeMode => _store?.getBool(_landscapeKey) ?? false;
  static Future<void> setLandscapeMode(bool value) async =>
      _store?.setBool(_landscapeKey, value);

  // ------------------------------------------------------------ 星标朋友

  static const String _starredKey = 'wechat_starred_friends';

  /// 是否设为星标朋友（本机标记，不写账号数据）。
  static bool isStarred(String userId) =>
      _store?.getStringList(_starredKey)?.contains(userId) ?? false;

  static Future<void> setStarred(String userId, bool value) async {
    final current = (_store?.getStringList(_starredKey) ?? <String>[]).toSet();
    if (value) {
      current.add(userId);
    } else {
      current.remove(userId);
    }
    await _store?.setStringList(_starredKey, current.toList());
  }

  // ------------------------------------------------------- 单个聊天的设置
  static String _roomKey(String prefix, String roomId) => '$prefix:$roomId';

  /// 这个聊天是否设了「提醒」（强提醒，本机标记）。
  static bool roomReminder(String roomId) =>
      _store?.getBool(_roomKey('wechat_room_reminder', roomId)) ?? false;
  static Future<void> setRoomReminder(String roomId, bool value) async =>
      _store?.setBool(_roomKey('wechat_room_reminder', roomId), value);

  /// 群聊是否「保存到通讯录」。
  static bool roomSavedToContacts(String roomId) =>
      _store?.getBool(_roomKey('wechat_room_saved', roomId)) ?? false;
  static Future<void> setRoomSavedToContacts(String roomId, bool value) async =>
      _store?.setBool(_roomKey('wechat_room_saved', roomId), value);
}
