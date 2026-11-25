// SPDX-FileCopyrightText: 2019-Present Christian Ku脽owski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:async/async.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher_string.dart';

import '../../utils/fluffy_share.dart';
import 'chat_list.dart';

class ClientChooserButton extends StatefulWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  @override
  State<ClientChooserButton> createState() => _ClientChooserButtonState();
}

class _ClientChooserButtonState extends State<ClientChooserButton> {
  /// The own profile shown in the button.
  ///
  /// It is kept in the state instead of being fetched inline by a FutureBuilder
  /// so that [Client.onUserProfileUpdate] can refresh it without a rebuild of
  /// the whole chat list. Without the listener the avatar would keep showing the
  /// old picture (and the display name its fallback) after the user changed the
  /// profile, because the SDK profile cache is not invalidated by the change.
  Profile? _profile;
  Client? _client;
  StreamSubscription<String>? _profileSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = Result(() => Matrix.of(context).client).asValue?.value;
    if (client == _client) return;
    _client = client;
    _profileSubscription?.cancel();
    _profileSubscription = null;
    _profile = null;
    if (client == null) return;
    _profileSubscription = client.onUserProfileUpdate.stream.listen((userId) {
      if (userId == client.userID) _loadProfile();
    });
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final client = _client;
    if (client == null || !client.isLogged()) return;
    final profile = await client.fetchOwnProfile();
    if (!mounted || client != _client) return;
    setState(() => _profile = profile);
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  List<PopupMenuEntry<Object>> _bundleMenuItems(BuildContext context) {
    final matrix = Matrix.of(context);
    final bundles = matrix.accountBundles.keys.toList()
      ..sort(
        (a, b) => a!.isValidMatrixIdStrict() == b!.isValidMatrixIdStrict()
            ? 0
            : a.isValidMatrixIdStrict() && !b.isValidMatrixIdStrict()
            ? -1
            : 1,
      );
    return <PopupMenuEntry<Object>>[
      PopupMenuItem(
        value: SettingsAction.moments,
        child: Row(
          children: [
            const Icon(Icons.photo_camera_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).momentsTitle),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.newGroup,
        child: Row(
          children: [
            const Icon(Icons.group_add_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).createGroup),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.setStatus,
        child: Row(
          children: [
            const Icon(Icons.edit_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).setStatus),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.invite,
        child: Row(
          children: [
            Icon(Icons.adaptive.share_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).inviteContact),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.archive,
        child: Row(
          children: [
            const Icon(Icons.archive_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).archive),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.settings,
        child: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).settings),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.support,
        child: Row(
          children: [
            Icon(Icons.favorite, color: Colors.red),
            const SizedBox(width: 18),
            Text(L10n.of(context).supportFluffyChat),
          ],
        ),
      ),
      const PopupMenuDivider(),
      for (final bundle in bundles) ...[
        if (matrix.accountBundles[bundle]!.length != 1 ||
            matrix.accountBundles[bundle]!.single!.userID != bundle)
          PopupMenuItem(
            value: null,
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  bundle!,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium!.color,
                    fontSize: 14,
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        ...matrix.accountBundles[bundle]!
            .whereType<Client>()
            .where((client) => client.isLogged())
            .map(
              (client) => PopupMenuItem(
                value: client,
                child: FutureBuilder<Profile?>(
                  future: client.fetchOwnProfile(),
                  builder: (context, snapshot) {
                    final displayname =
                        snapshot.data?.displayName ?? client.userID!.localpart!;
                    return Row(
                      key: ValueKey('switch_account_$displayname'),
                      children: [
                        Avatar(
                          mxContent: snapshot.data?.avatarUrl,
                          name: displayname,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            displayname,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => widget.controller.editBundlesForAccount(
                            client.userID,
                            bundle,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
      ],
      PopupMenuItem(
        value: SettingsAction.addAccount,
        child: Row(
          children: [
            const Icon(Icons.person_add_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).addAccount),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = Result(() => matrix.client).asValue?.value;

    return Material(
      clipBehavior: Clip.hardEdge,
      borderRadius: BorderRadius.circular(99),
      color: Colors.transparent,
      child: PopupMenuButton<Object>(
        key: const Key('accounts_and_settings_buttons'),
        tooltip: L10n.of(context).accountsAndSettings,
        onSelected: (o) => _clientSelected(o, context),
        itemBuilder: _bundleMenuItems,
        icon: Avatar(
          mxContent: _profile?.avatarUrl,
          name: _profile?.displayName ?? client?.userID?.localpart,
          size: 32,
        ),
      ),
    );
  }

  Future<void> _clientSelected(Object object, BuildContext context) async {
    if (object is Client) {
      widget.controller.setActiveClient(object);
    } else if (object is String) {
      widget.controller.setActiveBundle(object);
    } else if (object is SettingsAction) {
      switch (object) {
        case SettingsAction.moments:
          if (!context.mounted) return;
          context.push('/moments');
          break;
        case SettingsAction.addAccount:
          if (!context.mounted) return;
          context.go('/rooms/settings/addaccount');
          break;
        case SettingsAction.newGroup:
          context.go('/rooms/newgroup');
          break;
        case SettingsAction.invite:
          FluffyShare.shareInviteLink(context);
          break;
        case SettingsAction.support:
          launchUrlString(
            'https://ko-fi.com/post/How-can-I-support-FluffyChat-J2G325WE6I',
          );
          break;
        case SettingsAction.settings:
          context.go('/rooms/settings');
          break;
        case SettingsAction.archive:
          context.go('/rooms/archive');
          break;
        case SettingsAction.setStatus:
          widget.controller.setStatus();
          break;
      }
    }
  }
}

enum SettingsAction {
  moments,
  addAccount,
  newGroup,
  setStatus,
  invite,
  support,
  settings,
  archive,
}
