// SPDX-FileCopyrightText: 2026 Contributors to the QIVchat fork
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/moments/moments_service.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'moment_compose_view.dart';

class PickedMomentImage {
  const PickedMomentImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Composer for a new moment: text plus up to 9 images.
class MomentCompose extends StatefulWidget {
  const MomentCompose({super.key});

  @override
  MomentComposeController createState() => MomentComposeController();
}

class MomentComposeController extends State<MomentCompose> {
  static const int maxImages = 9;

  final TextEditingController textController = TextEditingController();
  final List<PickedMomentImage> images = [];
  bool uploading = false;
  int uploadedImages = 0;
  int totalImages = 0;

  bool get canPublish =>
      !uploading &&
      (textController.text.trim().isNotEmpty || images.isNotEmpty);

  @override
  void initState() {
    super.initState();
    textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    textController.removeListener(_onTextChanged);
    textController.dispose();
    super.dispose();
  }

  Future<void> pickImages() async {
    final l10n = L10n.of(context);
    final remaining = maxImages - images.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.momentsTooManyImages(maxImages))),
      );
      return;
    }

    final List<XFile> picked;
    if (PlatformInfos.isMobile) {
      picked = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } else {
      if (!mounted) return;
      picked = await selectFiles(
        context,
        type: FileType.image,
        allowMultiple: true,
      );
    }
    if (picked.isEmpty) return;

    final selected = picked.take(remaining).toList();
    final added = <PickedMomentImage>[];
    for (final file in selected) {
      try {
        added.add(
          PickedMomentImage(bytes: await file.readAsBytes(), name: file.name),
        );
      } catch (exception, stackTrace) {
        Logs().w('Unable to read ${file.name}', exception, stackTrace);
      }
    }
    if (!mounted) return;
    setState(() => images.addAll(added));
  }

  void removeImage(int index) {
    if (index < 0 || index >= images.length) return;
    setState(() => images.removeAt(index));
  }

  Future<void> publish() async {
    if (!canPublish) return;
    final l10n = L10n.of(context);
    final body = textController.text.trim();
    setState(() {
      uploading = true;
      uploadedImages = 0;
      totalImages = images.length;
    });
    try {
      final client = Matrix.of(context).client;
      final service = MomentsService(client);
      final room = await service.ensureOwnRoom();
      final urls = <Uri>[];
      for (final image in images) {
        final uri = await service.uploadImage(image.bytes, image.name);
        urls.add(uri);
        if (!mounted) return;
        setState(() => uploadedImages++);
      }
      await service.publish(room: room, body: body, images: urls);
      if (!mounted) return;
      context.pop(true);
    } catch (exception, stackTrace) {
      Logs().w('Unable to publish the moment', exception, stackTrace);
      if (!mounted) return;
      setState(() => uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.momentsFailedToPublish)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MomentComposeView(this);
}
