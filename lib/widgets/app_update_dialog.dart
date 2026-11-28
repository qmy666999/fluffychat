// SPDX-FileCopyrightText: 2026 FluffyChatX
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/updates/app_update_service.dart';
import 'package:fluffychat/widgets/app_toast.dart';
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
  AppToast.show(message);
}

Future<void> showAppUpdateDialog(BuildContext context, AppUpdateInfo info) =>
    showDialog<void>(
      context: context,
      barrierDismissible: !info.force,
      builder: (context) => AppUpdateDialog(info: info),
    );

/// 更新弹窗：状态机驱动按钮与进度区。
///
/// 关键点：下载完成之后按钮必须变成「安装」，不能让用户以为没下完。
/// 状态存在 [AppUpdateService.downloadState] 里，切走 App 再回来还在。
class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({super.key, required this.info});

  final AppUpdateInfo info;

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '—';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _speedLabel(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '';
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
    return '${(kb / 1024).toStringAsFixed(1)} MB/s';
  }

  String? _errorText(L10n l10n, UpdateDownloadState state) {
    // 安装失败时状态会退回「已下载」（文件还在，可以重试），所以这里不能只看
    // failed：只要带 error 就要把原因显示出来，用户才知道该去开哪个权限。
    if (state.error == null) return null;
    if (state.error == AppUpdateError.install) {
      return switch (state.errorDetail) {
        'no_permission' => l10n.updateInstallNoPermission,
        'missing' => l10n.updateInstallFileMissing,
        _ => l10n.updateInstallFailed,
      };
    }
    if (state.status != UpdateDownloadStatus.failed) return null;
    return switch (state.error) {
      AppUpdateError.checksum => l10n.updateChecksumFailed,
      AppUpdateError.rejected => l10n.updateServerRejected,
      _ => l10n.updateFailed(state.errorDetail ?? ''),
    };
  }

  Future<void> _onPrimaryPressed(UpdateDownloadState state) async {
    switch (state.status) {
      case UpdateDownloadStatus.idle:
      case UpdateDownloadStatus.failed:
        await AppUpdateService.startDownload(info);
      case UpdateDownloadStatus.downloading:
        await AppUpdateService.cancelDownload();
      case UpdateDownloadStatus.downloaded:
        await AppUpdateService.installDownloaded();
      case UpdateDownloadStatus.installing:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: !info.force,
      child: ValueListenableBuilder<UpdateDownloadState>(
        valueListenable: AppUpdateService.downloadState,
        builder: (context, state, _) {
          final errorText = _errorText(l10n, state);

          return AlertDialog(
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
                  _InfoRow(
                    label: l10n.updateSize,
                    value: _sizeLabel(
                      state.totalBytes > 0 ? state.totalBytes : info.size,
                    ),
                  ),
                  FutureBuilder<String>(
                    future: AppUpdateService.currentVersionLabel(),
                    builder: (context, snapshot) => _InfoRow(
                      label: l10n.updateCurrentVersion,
                      value: snapshot.data ?? '—',
                    ),
                  ),
                  if (state.status == UpdateDownloadStatus.downloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: state.progress > 0 ? state.progress : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        l10n.updateDownloading(
                          '${(state.progress * 100).round()}',
                        ),
                        if (_speedLabel(state.bytesPerSecond).isNotEmpty)
                          _speedLabel(state.bytesPerSecond),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (state.status == UpdateDownloadStatus.downloaded) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(value: 1),
                    const SizedBox(height: 8),
                    Text(
                      l10n.updateDownloadDone(
                        _sizeLabel(
                          state.receivedBytes > 0
                              ? state.receivedBytes
                              : info.size,
                        ),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (state.status == UpdateDownloadStatus.installing) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      l10n.updateInstalling,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!info.force)
                TextButton(
                  onPressed: () {
                    AppUpdateService.resetIdleIfFailed();
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.updateLater),
                ),
              FilledButton(
                onPressed: state.status == UpdateDownloadStatus.installing
                    ? null
                    : () => _onPrimaryPressed(state),
                child: Text(switch (state.status) {
                  UpdateDownloadStatus.idle => l10n.updateNow,
                  UpdateDownloadStatus.downloading => l10n.updateCancelDownload,
                  UpdateDownloadStatus.downloaded => l10n.updateInstallNow,
                  UpdateDownloadStatus.installing => l10n.updateInstalling,
                  UpdateDownloadStatus.failed => l10n.updateRetry,
                }),
              ),
            ],
          );
        },
      ),
    );
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
