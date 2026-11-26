// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/friends/friends_service.dart';
import 'package:fluffychat/utils/scan_flow.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 添加朋友：按用户名 / Matrix ID 搜索（Matrix 没有手机号目录）。
class AddFriendPage extends StatefulWidget {
  /// 扫码带过来的查询（会自动搜索）。
  final String? initialQuery;

  const AddFriendPage({this.initialQuery, super.key});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final TextEditingController _controller = TextEditingController();
  List<Profile>? _results;
  bool _searching = false;
  String? _error;

  FriendsService get _service => FriendsService(Matrix.of(context).client);

  Timer? _debounce;

  /// 输入停顿 400ms 自动搜索（长度 ≥2 才搜，避免打一个字就请求）。
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      if (_results != null) setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    if (query != null && query.trim().isNotEmpty) {
      _controller.text = query.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _controller.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.searchUsers(term);
      if (!mounted) return;
      setState(() => _results = results);
    } on MatrixException catch (e) {
      if (!mounted) return;
      setState(() => _error = '${e.errcode}: ${e.errorMessage}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(Profile profile) async {
    final l10n = L10n.of(context);
    final message = await showTextInputDialog(
      context: context,
      title: l10n.requestVerificationMessage,
      initialText: l10n.friendRequestDefaultMessage(
        profile.displayName ?? profile.userId.localpart ?? '',
      ),
      hintText: l10n.requestVerificationMessage,
    );
    if (message == null) return;
    try {
      await _service.sendFriendRequest(profile.userId, message);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.friendRequestSent)));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.friendRequestFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final data = _service.load();
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addToContacts),
        actions: [
          IconButton(
            tooltip: l10n.scan,
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final query = _controller.text.trim();
              await startMatrixScan(context);
              // 扫码回来如果是用户 ID，会跳到本页并带 q；直接扫后手动搜索
              if (query.isEmpty && mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              // 边打边搜：以前只有回车才搜，看起来像「搜不出东西」。
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                hintText: l10n.searchUsersHint,
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: IconButton(
                  tooltip: l10n.search,
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: results == null
                ? const SizedBox.shrink()
                : results.isEmpty
                ? Center(child: Text(l10n.noUserFound))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final profile = results[i];
                      final isFriend = data.isFriend(profile.userId);
                      final title =
                          profile.displayName ??
                          profile.userId.localpart ??
                          profile.userId;
                      return ListTile(
                        leading: Avatar(
                          mxContent: profile.avatarUrl,
                          name: title,
                          size: Avatar.defaultSize * 0.9,
                        ),
                        title: Text(title, maxLines: 1),
                        subtitle: Text(profile.userId, maxLines: 1),
                        trailing: isFriend
                            ? Text(
                                l10n.alreadyFriend,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : TextButton(
                                onPressed: () => _add(profile),
                                child: Text(l10n.addToContacts),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
