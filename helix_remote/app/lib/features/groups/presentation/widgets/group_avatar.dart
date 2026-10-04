import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A group's picture, or its initials on the group's colour while there is none
/// (or while it downloads and decrypts).
class GroupAvatar extends ConsumerWidget {
  const GroupAvatar({
    super.key,
    required this.model,
    required this.pictureKey,
    this.size = HelixAvatarSize.xl,
    this.semanticLabel,
  });

  final HelixAvatarModel model;

  /// The picture pointer, JSON-encoded (`GroupInfoView.pictureKey`); null for
  /// no picture.
  final String? pictureKey;
  final HelixAvatarSize size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = pictureKey;
    final bytes = key == null
        ? null
        : ref.watch(groupPictureProvider(key)).value;
    return HelixAvatar(
      model: HelixAvatarModel(
        name: model.name,
        colorIndex: model.colorIndex,
        isGroup: true,
        image: bytes == null ? null : MemoryImage(bytes),
      ),
      size: size,
      semanticLabel: semanticLabel ?? 'Group picture',
    );
  }
}
