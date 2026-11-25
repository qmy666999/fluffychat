// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// 发动态：文字 + 最多 9 张图，发布后回列表。
class MomentComposerPage extends StatefulWidget {
  const MomentComposerPage({super.key});

  @override
  State<MomentComposerPage> createState() => _MomentComposerPageState();
}

class _MomentComposerPageState extends State<MomentComposerPage> {
  final TextEditingController _text = TextEditingController();
  final List<Uint8List> _images = [];
  bool _publishing = false;

  MomentsService get _service => MomentsService(Matrix.of(context).client);

  bool get _canPublish =>
      !_publishing && (_text.text.trim().isNotEmpty || _images.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_images.length >= 9) return;
    final files = await selectFiles(
      context,
      type: FileType.image,
      allowMultiple: true,
    );
    for (final file in files) {
      if (_images.length >= 9) break;
      _images.add(await file.readAsBytes());
    }
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() => _publishing = true);
    try {
      await _service.post(
        text: _text.text.trim(),
        images: _images,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n.momentsPublish),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: _canPublish ? _publish : null,
              child: _publishing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : Text(l10n.momentsPublish),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            autocorrect: false,
            minLines: 4,
            maxLines: 10,
            enabled: !_publishing,
            decoration: InputDecoration(
              hintText: l10n.momentsComposerHint,
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: _images.length + (_images.length >= 9 ? 0 : 1),
            itemBuilder: (context, i) {
              if (i >= _images.length) {
                return InkWell(
                  onTap: _publishing ? null : _pickImages,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.add_a_photo_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_images[i], fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: _publishing
                          ? null
                          : () => setState(() => _images.removeAt(i)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(200),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close, size: 14),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
