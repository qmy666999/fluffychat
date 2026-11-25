// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/avatar_image.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/refresh_own_profile.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;

  void updateProfile() => setState(() {
    profileUpdated = true;
    profileFuture = null;
  });

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = await profileFuture;
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.editDisplayname,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: profile?.displayName ?? matrix.client.userID!.localpart,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      await _refreshProfile();
      if (!mounted) return;
      updateProfile();
    }
  }

  /// 改完资料必须强刷一次缓存，否则界面读到的还是旧值（见 refresh_own_profile.dart）。
  Future<void> _refreshProfile() async {
    await refreshOwnProfile(Matrix.of(context).client);
  }

  Future<void> logoutAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final consent = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.areYouSureYouWantToLogout,
      message: l10n.noBackupWarning,
      isDestructive: cryptoIdentityConnected == false,
      okLabel: l10n.logout,
      cancelLabel: l10n.cancel,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
    if (!mounted) return;
    context.go('/');
  }

  Future<void> setAvatarAction(AvatarAction action) async {
    final matrix = Matrix.of(context);
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        await _refreshProfile();
        if (!mounted) return;
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (action == AvatarAction.camera) {
      final result = await ImagePicker().pickImage(source: ImageSource.camera);
      if (result == null) return;
      final avatarBytes = await _prepareAvatar(await result.readAsBytes());
      if (avatarBytes == null) return;
      file = MatrixFile(
        bytes: avatarBytes,
        name: 'avatar.jpg',
        mimeType: 'image/jpeg',
      );
    } else {
      if (!mounted) return;
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      final avatarBytes = await _prepareAvatar(
        await pickedFile.readAsBytes(),
      );
      if (avatarBytes == null) return;
      file = MatrixFile(
        bytes: avatarBytes,
        name: 'avatar.jpg',
        mimeType: 'image/jpeg',
      );
    }
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      await _refreshProfile();
      if (!mounted) return;
      updateProfile();
    }
  }

  /// 头像上传前统一转 JPEG（最长边 512）：相册里的 HEIC 直接传会让服务器
  /// 生成不了缩略图，头像变灰。解不开的格式在这里提示，不静默上传坏文件。
  Future<Uint8List?> _prepareAvatar(Uint8List bytes) async {
    try {
      return prepareAvatarBytes(bytes);
    } on UnsupportedAvatarFormat {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).avatarUnsupportedFormat)),
      );
      return null;
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());

    super.initState();
  }

  Future<void> checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    if (!client.isLogged()) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }

    final state = await client.getCryptoIdentityState();
    if (!mounted) return;
    setState(() {
      cryptoIdentityConnected = state.initialized && state.connected;
    });
  }

  bool? cryptoIdentityConnected;

  Future<void> firstRunBootstrapAction([_]) async {
    if (cryptoIdentityConnected == true) {
      final action = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).resetRecoveryKey,
        cancelLabel: L10n.of(context).close,
        isDestructive: true,
      );
      if (action != OkCancelResult.ok) return;
      if (!mounted) return;
      await context.push('/backup?reset=true');
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(client.userID!);
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
