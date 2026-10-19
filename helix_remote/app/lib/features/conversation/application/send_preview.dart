import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';

/// The send-files page draws each file at 48px: three times that covers the
/// densest screen.
const _previewSide = 144;

/// A picked photo, decoded no larger than its row needs.
ImageProvider photoPreviewOf(AttachmentDraft file) => ResizeImage(
  FileImage(File(file.path)),
  width: _previewSide,
  allowUpscaling: false,
);

/// The first frame of a picked video, for its row on the send-files page;
/// null when the device cannot read one (the row keeps its play mark).
final videoStillProvider = FutureProvider.autoDispose
    .family<ImageProvider?, String>((ref, path) async {
      final bytes = await ref
          .read(videoFramesProvider)
          .frame(path, maxSide: _previewSide);
      return bytes == null ? null : MemoryImage(bytes);
    });
