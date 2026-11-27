// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/stickers/sticker_image.dart';
import 'package:fluffychat/utils/stickers/sticker_service.dart';
import 'package:fluffychat/utils/stickers/sticker_store.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// 微信式「我的表情」面板。
///
/// 数据来自 [StickerStore]（分片 account data，没有数量上限）：
/// - 顶部「最近使用」只在本机保存 9 个
/// - 下面是全部表情，按片懒加载，滚动到底继续读
/// - 支持搜索、长按（移到最前 / 删除）、底部四个入口
class StickerPanel extends StatefulWidget {
  const StickerPanel({
    super.key,
    required this.room,
    required this.onSend,
    required this.onManage,
  });

  final Room room;
  final void Function(StickerItem item) onSend;
  final VoidCallback onManage;

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  static const int _pageSize = 240;

  late final StickerStore _store = StickerStore(widget.room.client);
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<StickerItem> _items = const [];
  List<StickerItem> _searchResults = const [];
  List<StickerItem> _recents = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _allLoaded = false;
  bool _adding = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    StickerStore.revision.addListener(_reload);
    _scroll.addListener(_onScroll);
    _loadRecents();
    _loadInitial();
  }

  @override
  void dispose() {
    StickerStore.revision.removeListener(_reload);
    _scroll.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final recents = await StickerRecents.load();
    if (!mounted) return;
    setState(() => _recents = recents);
  }

  void _reload() {
    if (!mounted) return;
    _loadInitial();
    _loadRecents();
  }

  Future<void> _loadInitial() async {
    final total = _store.loadMeta().total;
    final items = await _store.loadRange(count: _pageSize);
    if (!mounted) return;
    setState(() {
      _total = total;
      _items = items;
      _allLoaded = items.length >= total;
      _loading = false;
      _searchResults = _query.isEmpty ? const [] : _filter(items);
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 200) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _allLoaded) return;
    _loadingMore = true;
    final items = await _store.loadRange(
      start: _items.length,
      count: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _items = [..._items, ...items];
      _allLoaded = _items.length >= _total;
      _loadingMore = false;
    });
  }

  List<StickerItem> _filter(List<StickerItem> source) {
    final query = _query.toLowerCase();
    return source
        .where((item) => item.body.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _onQueryChanged(String value) async {
    setState(() => _query = value.trim());
    if (_query.isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    // 搜索要在全部数据里找：先把没加载的片读进来
    if (!_allLoaded) {
      final all = await _store.loadAll();
      if (!mounted) return;
      setState(() {
        _items = all;
        _total = all.length;
        _allLoaded = true;
        _searchResults = _filter(all);
      });
      return;
    }
    setState(() => _searchResults = _filter(_items));
  }

  Future<void> _send(StickerItem item) async {
    widget.onSend(item);
    final recents = await StickerRecents.push(item);
    if (!mounted) return;
    setState(() => _recents = recents);
  }

  Future<void> _addFromGallery() async {
    if (_adding) return;
    _adding = true;
    final l10n = L10n.of(context);
    try {
      final files = await ImagePicker().pickMultiImage();
      if (files.isEmpty) return;
      var added = 0;
      var duplicates = 0;
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          final item = await StickerUploader.upload(
            widget.room.client,
            bytes,
            name: file.name,
            mimetype: file.mimeType ?? _mimeOf(file.name),
          );
          final result = await _store.add(item);
          if (result == StickerAddResult.duplicate) {
            duplicates++;
          } else if (result == StickerAddResult.added) {
            added++;
          }
        } on StickerImageException catch (e) {
          AppToast.show(_errorText(e, l10n), isError: true);
          return;
        } catch (e, s) {
          Logs().w('[sticker] add failed', e, s);
          AppToast.show(l10n.stickerUploadFailed, isError: true);
          return;
        }
      }
      if (!mounted) return;
      if (added > 0) {
        AppToast.show(l10n.stickerAddedCount('$added'));
      } else if (duplicates > 0) {
        AppToast.show(l10n.stickerAlreadyAdded);
      }
      await _loadInitial();
    } finally {
      _adding = false;
    }
  }

  String? _mimeOf(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }

  String _errorText(StickerImageException e, L10n l10n) {
    switch (e.error) {
      case StickerImageError.animatedTooLarge:
        return l10n.stickerAnimatedTooLarge;
      case StickerImageError.animatedTooBig:
        return l10n.stickerAnimatedTooBigDims;
      case StickerImageError.unsupported:
        return l10n.stickerUnsupportedImage;
      case StickerImageError.decodeFailed:
        return l10n.stickerUnsupportedImage;
    }
  }

  Future<void> _showActions(StickerItem item) async {
    final l10n = L10n.of(context);
    final action = await showModalBottomSheet<_StickerAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: Text(l10n.stickerMoveToFront),
              onTap: () =>
                  Navigator.of(context).pop(_StickerAction.moveToFront),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_StickerAction.remove),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _StickerAction.moveToFront:
        await _store.moveToFront(item.url);
        if (!mounted) return;
        AppToast.show(l10n.stickerMovedToFront);
      case _StickerAction.remove:
        await _store.remove(item.url);
        if (!mounted) return;
        AppToast.show(l10n.stickerDeleted);
    }
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final visible = _query.isEmpty ? _items : _searchResults;

    return Material(
      color: theme.colorScheme.onInverseSurface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  hintText: l10n.stickerSearchHint,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.normal,
                  ),
                  prefixIcon: const Icon(Icons.search_outlined, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        if (_query.isEmpty && _recents.isNotEmpty)
                          SliverToBoxAdapter(child: _buildRecents(theme, l10n)),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: [
                                Text(
                                  l10n.myStickers,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  l10n.stickerCount('$_total'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (visible.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _query.isEmpty
                                      ? l10n.stickerEmpty
                                      : l10n.stickerSearchEmpty,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 64,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 6,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              return _StickerCell(
                                key: ValueKey(item.url),
                                item: item,
                                onTap: () => _send(item),
                                onLongPress: () => _showActions(item),
                              );
                            },
                          ),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      ],
                    ),
            ),
            _buildBottomBar(theme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildRecents(ThemeData theme, L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            l10n.recentStickers,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _recents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final item = _recents[index];
              return _StickerCell(
                key: ValueKey('recent_${item.url}'),
                item: item,
                onTap: () => _send(item),
                onLongPress: () => _showActions(item),
                size: 48,
              );
            },
          ),
        ),
        const Divider(height: 16),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme, L10n l10n) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: l10n.recentStickers,
            icon: const Icon(Icons.history, size: 20),
            onPressed: () {
              if (_scroll.hasClients) {
                _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
          IconButton(
            tooltip: l10n.stickerAdd,
            icon: _adding
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 22),
            onPressed: _adding ? null : _addFromGallery,
          ),
          IconButton(
            tooltip: l10n.search,
            icon: const Icon(Icons.search, size: 20),
            onPressed: _searchFocus.requestFocus,
          ),
          IconButton(
            tooltip: l10n.stickerManage,
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: widget.onManage,
          ),
        ],
      ),
    );
  }
}

enum _StickerAction { moveToFront, remove }

class _StickerCell extends StatelessWidget {
  const _StickerCell({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.size = 56,
  });

  final StickerItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Center(
        child: MxcImage(
          uri: Uri.parse(item.url),
          width: size,
          height: size,
          fit: BoxFit.contain,
          isThumbnail: true,
          animated: item.animated,
        ),
      ),
    );
  }
}
