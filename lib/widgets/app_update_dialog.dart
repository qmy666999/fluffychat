// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/updates/app_update_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 检查更新并按需弹窗。
///
/// [automatic] 为 true 表示启动时的自动检查：一天最多提示一次，
/// 已经提示过就安静地返回。手动检查（设置页）总会弹窗。
Future<void> checkAndPromptUpdate(
  BuildContext context, {
  bool automatic = false,
}) async {
  final l10n = L10n.of(context);
  AppUpdateInfo? info;
  try {
    info = await AppUpdateService.checkForUpdate();
  } on AppUpdateException catch (e) {
    Logs().w('[Update] 检查更新失败: ${e.error} ${e.detail}');
    if (automatic) return;
    if (!context.mounted) return;
    _showMessage(context, l10n.updateCheckFailed);
    return;
  }
  if (!context.mounted) return;
  if (info == null) {
    if (!automatic) _showMessage(context, l10n.updateLatest);
    return;
  }
  if (automatic) {
    final shouldPrompt = await AppUpdateService.shouldPromptAutomatically(
      info.force,
    );
    if (!shouldPrompt) return;
    await AppUpdateService.markPrompted();
  }
  if (!context.mounted) return;
  await showAppUpdateDialog(context, info);
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> showAppUpdateDialog(BuildContext context, AppUpdateInfo info) =>
    showDialog<void>(
      context: context,
      barrierDismissible: !info.force,
      builder: (context) => _AppUpdateDialog(info: info),
    );

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.info});

  final AppUpdateInfo info;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  double? _progress;
  AppUpdateError? _error;
  String? _errorDetail;
  bool _installing = false;

  Future<void> _startUpdate() async {
    setState(() {
      _error = null;
      _errorDetail = null;
      _progress = 0;
      _installing = true;
    });
    try {
      await AppUpdateService.downloadAndInstall(
        widget.info,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );
    } on AppUpdateException catch (e) {
      Logs().w('[Update] 更新失败: ${e.error} ${e.detail}');
      if (!mounted) return;
      setState(() {
        _installing = false;
        _progress = null;
        _error = e.error;
        _errorDetail = e.detail;
      });
    }
  }

  String _errorText(L10n l10n) => switch (_error) {
    AppUpdateError.checksum => l10n.updateChecksumFailed,
    AppUpdateError.install => l10n.updateInstallFailed,
    AppUpdateError.rejected => l10n.updateServerRejected,
    _ => l10n.updateFailed(_errorDetail ?? ''),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final info = widget.info;
    final progress = _progress;
    return PopScope(
      canPop: !info.force,
      child: AlertDialog(
        title: Text(l10n.updateAvailable(info.versionName)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.changelog.isNotEmpty) ...[
                Text(info.changelog),
                const SizedBox(height: 16),
              ],
              if (info.force)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.updateForceHint,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              _InfoRow(
                label: l10n.updateNewVersion,
                value: '${info.versionName} (${info.versionCode})',
              ),
              _InfoRow(label: l10n.updateSize, value: _sizeLabel(info.size)),
              FutureBuilder<String>(
                future: AppUpdateService.currentVersionLabel(),
                builder: (context, snapshot) => _InfoRow(
                  label: l10n.updateCurrentVersion,
                  value: snapshot.data ?? '—',
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  _installing && progress >= 1
                      ? l10n.updateVerifying
                      : l10n.updateDownloading('${(progress * 100).round()}'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText(l10n),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!info.force)
            TextButton(
              onPressed: _installing ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.updateLater),
            ),
          FilledButton(
            onPressed: _installing ? null : _startUpdate,
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '—';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
