import 'dart:async';
import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// 缓存分组。
///
/// **只清 `getTemporaryDirectory()`**：聊天数据库与登录凭据在
/// `getApplicationSupportDirectory()`，一个字节都不能碰。
enum CacheGroup { apk, images, temp }

class CacheCleanPage extends StatefulWidget {
  const CacheCleanPage({super.key});

  @override
  State<CacheCleanPage> createState() => _CacheCleanPageState();
}

class _CacheCleanPageState extends State<CacheCleanPage> {
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.heic',
  };

  bool _loading = true;
  bool _cleaning = false;
  Map<CacheGroup, int> _sizes = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<Directory> _cacheDir() => getTemporaryDirectory();

  Future<Directory> _updateDir() async {
    final cache = await _cacheDir();
    return Directory('${cache.path}/update');
  }

  Future<void> _scan() async {
    try {
      final cache = await _cacheDir();
      var apk = 0;
      var images = 0;
      var temp = 0;
      if (await cache.exists()) {
        await for (final entity in cache.list(recursive: true)) {
          if (entity is! File) continue;
          int size;
          try {
            size = await entity.length();
          } catch (_) {
            continue;
          }
          final path = entity.path.toLowerCase();
          if (path.endsWith('.apk')) {
            apk += size;
          } else if (_imageExtensions.any(path.endsWith)) {
            images += size;
          } else {
            temp += size;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _sizes = {
          CacheGroup.apk: apk,
          CacheGroup.images: images,
          CacheGroup.temp: temp,
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _total => _sizes.values.fold<int>(0, (sum, size) => sum + size);

  Future<void> _clear(CacheGroup? group) async {
    if (_cleaning) return;
    setState(() => _cleaning = true);
    var cleared = 0;
    try {
      final cache = await _cacheDir();
      if (await cache.exists()) {
        if (group == null) {
          // 一键清理：清整个临时目录，正在用的文件会删失败，跳过即可。
          await for (final entity in cache.list()) {
            if (entity is File) {
              try {
                cleared += await entity.length();
                await entity.delete();
              } catch (_) {}
            } else if (entity is Directory) {
              if (entity.path.endsWith('/update') && group == null) {
                cleared += await _deleteInside(entity);
              } else {
                cleared += await _deleteInside(entity);
                try {
                  await entity.delete(recursive: true);
                } catch (_) {}
              }
            }
          }
        } else if (group == CacheGroup.apk) {
          final dir = await _updateDir();
          cleared += await _deleteInside(dir);
        } else {
          await for (final entity in cache.list(recursive: true)) {
            if (entity is! File) continue;
            if (entity.path.contains('/update/')) continue;
            final path = entity.path.toLowerCase();
            final isImage = _imageExtensions.any(path.endsWith);
            if (group == CacheGroup.images && !isImage) continue;
            if (group == CacheGroup.temp && isImage) continue;
            try {
              cleared += await entity.length();
              await entity.delete();
            } catch (_) {}
          }
        }
      }
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (e, s) {
      Logs().w('[cache] 清理失败', e, s);
    }
    await _scan();
    if (!mounted) return;
    setState(() => _cleaning = false);
    AppToast.show(L10n.of(context).clearedCacheSize(_formatBytes(cleared)));
  }

  Future<int> _deleteInside(Directory dir) async {
    if (!await dir.exists()) return 0;
    var cleared = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      try {
        cleared += await entity.length();
        await entity.delete();
      } catch (_) {}
    }
    return cleared;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.clearCache)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_cleaning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                _CacheTile(
                  icon: Icons.android_outlined,
                  title: l10n.cacheApk,
                  bytes: _sizes[CacheGroup.apk] ?? 0,
                  formatter: _formatBytes,
                  enabled: !_cleaning && (_sizes[CacheGroup.apk] ?? 0) > 0,
                  onClear: () => _clear(CacheGroup.apk),
                ),
                _CacheTile(
                  icon: Icons.image_outlined,
                  title: l10n.cacheImages,
                  bytes: _sizes[CacheGroup.images] ?? 0,
                  formatter: _formatBytes,
                  enabled: !_cleaning && (_sizes[CacheGroup.images] ?? 0) > 0,
                  onClear: () => _clear(CacheGroup.images),
                ),
                _CacheTile(
                  icon: Icons.folder_open_outlined,
                  title: l10n.cacheTemp,
                  bytes: _sizes[CacheGroup.temp] ?? 0,
                  formatter: _formatBytes,
                  enabled: !_cleaning && (_sizes[CacheGroup.temp] ?? 0) > 0,
                  onClear: () => _clear(CacheGroup.temp),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    l10n.cacheTotal(_formatBytes(_total)),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    l10n.cacheKeepNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    onPressed: _cleaning || _total <= 0
                        ? null
                        : () => _clear(null),
                    child: Text(
                      _cleaning ? l10n.clearingCache : l10n.clearCacheNow,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _CacheTile extends StatelessWidget {
  const _CacheTile({
    required this.icon,
    required this.title,
    required this.bytes,
    required this.formatter,
    required this.enabled,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final int bytes;
  final String Function(int bytes) formatter;
  final bool enabled;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(formatter(bytes), style: theme.textTheme.bodySmall),
      trailing: IconButton(
        tooltip: L10n.of(context).clear,
        onPressed: enabled ? onClear : null,
        icon: const Icon(Icons.cleaning_services_outlined),
      ),
    );
  }
}
