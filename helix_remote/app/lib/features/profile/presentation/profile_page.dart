import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote/shared/you_facts.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Edit profile, your name, about line, photo and `~name` with a
/// live preview of your orbit, drawn by `orbit_ui`'s
/// [orbit.ProfileEditScreen].
///
/// One Save sends the name and about line (one encrypted profile), then the
/// `~name` when it changed; each field keeps its own refusal. Choosing or
/// removing a photo publishes it too, so people you message see it. "Who sees
/// what" follows ADR-030: the operator sees the name and the number.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final edit = ref.watch(profileEditProvider);
    final editor = ref.read(profileEditProvider.notifier);
    final bytes = ref.watch(profileAvatarBytesProvider).value;
    final data = profile.value;

    return orbit.ProfileEditScreen(
      model: orbit.ProfileEditModel(
        status: switch (profile) {
          AsyncData() => orbit.ProfileEditStatus.ready,
          AsyncError() when data == null => orbit.ProfileEditStatus.failed,
          _ when data != null => orbit.ProfileEditStatus.ready,
          _ => orbit.ProfileEditStatus.loading,
        },
        name: data?.name ?? '',
        about: data?.about ?? '',
        helixName: data?.helixName ?? '',
        currentHelixName: data?.helixName,
        photo: bytes == null ? null : MemoryImage(bytes),
        avatarColor: orbit.HelixAvatarModel.colorIndexFor(
          (data?.accountId ?? '').isEmpty ? 'helix' : data!.accountId,
        ),
        canPickPhoto: ref.watch(canPickAvatarProvider),
        nameError: edit.nameError,
        aboutError: edit.aboutError,
        helixNameError: edit.helixNameError,
        findableByName: ref.watch(findableByNameProvider),
        deviceCount: ref.watch(youDeviceCountProvider),
        meta: ref.watch(youMetaLineProvider),
        saving: edit.busy,
      ),
      actions: orbit.ProfileEditActions(
        onSave: (name, about, helixName) async {
          final saved = await editor.saveAll(
            name: name,
            about: about,
            helixName: helixName,
            current: data?.helixName,
          );
          return saved ? null : ref.read(profileEditProvider).error ?? '';
        },
        onChoosePhoto: () async {
          await editor.chooseAvatar();
          final state = ref.read(profileEditProvider);
          return state.error ?? state.notice;
        },
        onRemovePhoto: () async {
          await editor.removeAvatar();
          final state = ref.read(profileEditProvider);
          return state.error ?? state.notice;
        },
        onRemoveHelixName: () async {
          await editor.clearHelixName();
          return ref.read(profileEditProvider).error;
        },
        onRetry: () => ref.invalidate(profileProvider),
      ),
    );
  }
}
