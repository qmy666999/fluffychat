// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/server_endpoints.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/server_probe.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// 「设置 → 关于」里的服务器线路指示，顺便提供「重新检测」。
///
/// 以后排查「为什么又慢了」一眼就知道走的是局域网还是公网。
class ServerEndpointTile extends StatefulWidget {
  const ServerEndpointTile({super.key});

  @override
  State<ServerEndpointTile> createState() => ServerEndpointTileState();
}

class ServerEndpointTileState extends State<ServerEndpointTile> {
  bool _busy = false;

  Future<void> _recheck() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final clients = Matrix.of(context).widget.clients;
    try {
      await pickFastestServer();
      // 已登录的客户端同步换地址，发图立刻走新的线路（不用重启 App）。
      for (final client in clients) {
        ServerEndpoints.applyTo(client);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final host = ServerEndpoints.uri.host;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ServerEndpoints.reachable
              ? ServerEndpoints.isLan
                    ? l10n.serverEndpointLan(host)
                    : l10n.serverEndpointWan(host)
              : l10n.serverEndpointOffline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final host = ServerEndpoints.uri.host;
    final isLan = ServerEndpoints.isLan;
    final reachable = ServerEndpoints.reachable;
    final subtitle = !reachable
        ? l10n.serverEndpointOffline
        : isLan
        ? l10n.serverEndpointLanHint
        : l10n.serverEndpointWanHint;

    return ListTile(
      leading: Icon(
        isLan ? Icons.lan_outlined : Icons.public_outlined,
        color: reachable ? null : Theme.of(context).colorScheme.error,
      ),
      title: Text(
        isLan ? l10n.serverEndpointLan(host) : l10n.serverEndpointWan(host),
      ),
      subtitle: Text(subtitle),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: l10n.serverEndpointRecheck,
              onPressed: _recheck,
            ),
      onTap: _busy ? null : _recheck,
    );
  }
}
