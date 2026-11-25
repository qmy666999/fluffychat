// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'moment_compose.dart';

class MomentComposeView extends StatelessWidget {
  final MomentComposeController controller;

  const MomentComposeView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.momentsNewPost),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: controller.canPublish ? controller.publish : null,
              child: Text(l10n.momentsPublish),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (controller.uploading)
            Column(
              children: [
                LinearProgressIndicator(
                  value: controller.totalImages == 0
                      ? null
                      : controller.uploadedImages / controller.totalImages,
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    controller.totalImages == 0
                        ? l10n.momentsPublishing
                        : l10n.momentsUploading(
                            controller.uploadedImages,
                            controller.totalImages,
                          ),
                  ),
                ),
              ],
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: controller.textController,
                  readOnly: controller.uploading,
                  minLines: 5,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: l10n.momentsComposeHint,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < controller.images.length; i++)
                      _Thumbnail(
                        bytes: controller.images[i].bytes,
                        onRemove: controller.uploading
                            ? null
                            : () => controller.removeImage(i),
                      ),
                    if (controller.images.length <
                            MomentComposeController.maxImages &&
                        !controller.uploading)
                      InkWell(
                        onTap: controller.pickImages,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback? onRemove;

  const _Thumbnail({required this.bytes, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
