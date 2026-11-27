// SPDX-FileCopyrightText: 2026 FluffyChatX
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/stickers/sticker_store.dart';
import 'package:fluffychat/widgets/app_toast.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';

/// 自定义表情管理页：拖动排序、单个删除、多选删除。
///
/// 排序是整体重写分片（只在这一页、用户明确拖动时才发生），
/// 所以不会影响日常添加的性能。
class StickerManagePage extends StatefulWidget {
  const StickerManagePage({super.key});

  @override
  State<StickerManagePage> createState() => _StickerManagePageState();
}

class _StickerManagePageState extends State<StickerManagePage> {
  late final StickerStore _store;
  bool _initialized = false;
  List<StickerItem> _items = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _selecting = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _store = StickerStore(Matrix.of(context).client);
    _load();
  }

  Future<void> _load() async {
    final items = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_selecting) return;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex.clamp(0, _items.length), item);
    });
    await _store.reorder(_items.map((item) => item.url).toList());
  }

  Future<void> _remove(StickerItem item) async {
    if (_busy) return;
    _busy = true;
    try {
      await _store.remove(item.url);
      if (!mounted) return;
      setState(() => _items.removeWhere((entry) => entry.url == item.url));
      AppToast.show(L10n.of(context).stickerDeleted);
    } finally {
      _busy = false;
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _busy) return;
    _busy = true;
    final count = _selected.length;
    try {
      await _store.removeMany(_selected.toList());
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => _selected.contains(item.url));
        _selected.clear();
        _selecting = false;
      });
      AppToast.show(L10n.of(context).stickerDeletedCount('$count'));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stickerManageTitle),
        actions: [
          if (_selecting) ...[
            TextButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => setState(() {
                      if (_selected.length == _items.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(_items.map((item) => item.url));
                      }
                    }),
              child: Text(l10n.stickerSelectAll),
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: Text(
                l10n.stickerDeleteSelected,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ] else
            TextButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => setState(() => _selecting = true),
              child: Text(l10n.edit),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.stickerEmpty, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.stickerDragHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Text(
                        l10n.stickerCount('${_items.length}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _items.length,
                    onReorderItem: _reorder,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final selected = _selected.contains(item.url);
                      return ListTile(
                        key: ValueKey(item.url),
                        leading: SizedBox.square(
                          dimension: 40,
                          child: MxcImage(
                            uri: Uri.parse(item.url),
                            width: 40,
                            height: 40,
                            fit: BoxFit.contain,
                            isThumbnail: true,
                            animated: item.animated,
                          ),
                        ),
                        title: Text(
                          item.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.mimetype == null
                            ? null
                            : Text(
                                [
                                  item.mimetype!,
                                  if (item.width != null && item.height != null)
                                    '${item.width}×${item.height}',
                                  if (item.size != null)
                                    '${(item.size! / 1024).round()} KB',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: _selecting
                            ? () => setState(() {
                                if (selected) {
                                  _selected.remove(item.url);
                                } else {
                                  _selected.add(item.url);
                                }
                              })
                            : null,
                        trailing: _selecting
                            ? Checkbox.adaptive(
                                value: selected,
                                onChanged: (_) => setState(() {
                                  if (selected) {
                                    _selected.remove(item.url);
                                  } else {
                                    _selected.add(item.url);
                                  }
                                }),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: l10n.delete,
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    onPressed: () => _remove(item),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                ],
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
