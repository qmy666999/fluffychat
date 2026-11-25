// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/profile_refresh.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
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
  /// The last known own profile.
  ///
  /// It is kept as a value instead of a `Future` so that reloading it after an
  /// edit does not make the screen fall back to the localpart for a frame.
  Profile? profile;
  bool profileUpdated = false;

  /// Re-reads the own profile from the server after it has been changed.
  ///
  /// The SDK caches profiles for a day and does not invalidate the cache on a
  /// profile change, so a plain refetch would still return the old values.
  /// [OwnProfileRefresh.refreshOwnProfile] forces a server round trip first,
  /// then the value is stored so the whole page (and the account button in the
  /// chat list) renders the new display name and avatar.
  Future<void> updateProfile() async {
    final client = Matrix.of(context).client;
    await client.refreshOwnProfile();
    final fresh = await client.getProfileFromUserId(client.userID!);
    if (!mounted) return;
    setState(() {
      profile = fresh;
      profileUpdated = true;
    });
  }

  Future<void> _loadProfile() async {
    final userId = Matrix.of(context).client.userID;
    if (userId == null) return;
    final loaded = await Matrix.of(context).client.getProfileFromUserId(userId);
    if (!mounted) return;
    setState(() => profile = loaded);
  }

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final profile = this.profile;
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
      await updateProfile();
    }
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
        await updateProfile();
      }
      return;
    }
    final file = await _pickAvatar(action);
    if (file == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      await updateProfile();
    }
  }

  /// Picks an avatar and converts it to a small JPEG.
  ///
  /// Synapse can not generate thumbnails for HEIC (and plenty of other
  /// formats), which turns the avatar into a grey box. On mobile the image
  /// picker re-encodes the picked file through the platform decoder (which does
  /// understand HEIC), and [_encodeAvatar] resizes/compresses it again so the
  /// upload stays small.
  Future<MatrixFile?> _pickAvatar(AvatarAction action) async {
    Uint8List bytes;
    String name;
    if (action == AvatarAction.camera) {
      final result = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (result == null) return null;
      bytes = await result.readAsBytes();
      name = result.path;
    } else if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (result == null) return null;
      bytes = await result.readAsBytes();
      name = result.name;
    } else {
      if (!mounted) return null;
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return null;
      bytes = await pickedFile.readAsBytes();
      name = pickedFile.name;
    }

    final converted = await compute(_encodeAvatar, bytes);
    if (converted == null) {
      Logs().w('Unable to convert avatar to JPEG, uploading the original bytes');
      return MatrixFile(bytes: bytes, name: name);
    }
    return MatrixFile(bytes: converted, name: 'avatar.jpg');
  }

  /// Decodes, downsizes to 512px and re-encodes the avatar as JPEG.
  ///
  /// Runs in an isolate because decoding a full resolution camera picture takes
  /// a moment. Returns null for formats the pure Dart `image` package can not
  /// decode.
  static Uint8List? _encodeAvatar(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      const maxSize = 512;
      final resized = image.width <= maxSize && image.height <= maxSize
          ? image
          : image.width >= image.height
          ? img.copyResize(
              image,
              width: maxSize,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxSize,
              interpolation: img.Interpolation.average,
            );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    } catch (exception, stackTrace) {
      Logs().w('Unable to encode the avatar', exception, stackTrace);
      return null;
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkBootstrap();
      _loadProfile();
    });

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
  Widget build(BuildContext context) => SettingsView(this);
}

enum AvatarAction { camera, file, remove }
