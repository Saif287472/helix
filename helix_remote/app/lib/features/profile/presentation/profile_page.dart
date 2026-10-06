import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/profile/application/profile_gateway.dart';
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Your profile: the name and about line people see, your picture, and your
/// `~Helix name`.
///
/// Each field says who can see it, in the words the privacy documents use:
/// the name and about line are encrypted so only people you have messaged can
/// read them; the `~name` is stored on the server so people can find you by it.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _about = TextEditingController();
  final TextEditingController _helixName = TextEditingController();
  var _filled = false;

  @override
  void initState() {
    super.initState();
    // The fields start from what is saved, once, and are never overwritten
    // while somebody is typing in them.
    ref.listenManual(profileProvider, (_, next) => _fill(next.value));
    _fill(ref.read(profileProvider).value);
  }

  void _fill(ProfileData? data) {
    if (_filled || data == null) return;
    _filled = true;
    _name.text = data.name;
    _about.text = data.about;
    _helixName.text = data.helixName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _helixName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final edit = ref.watch(profileEditProvider);
    final editor = ref.read(profileEditProvider.notifier);
    final avatar = ref.watch(profileAvatarBytesProvider).value;
    final canPick = ref.watch(canPickAvatarProvider);
    final data = profile.value ?? const ProfileData();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: switch (profile) {
        AsyncError() => HelixErrorState(
          message: 'Your profile could not be loaded.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        AsyncLoading() when !_filled => const Padding(
          padding: EdgeInsets.all(HelixSpace.lg),
          child: LinearProgressIndicator(),
        ),
        _ => ListView(
          children: [
            if (edit.busy) const LinearProgressIndicator(),
            if (edit.error != null)
              InlineNotice(kind: InlineNoticeKind.error, message: edit.error!),
            if (edit.notice != null)
              InlineNotice(
                kind: InlineNoticeKind.success,
                message: edit.notice!,
              ),
            Padding(
              padding: const EdgeInsets.all(HelixSpace.md),
              child: Center(
                child: HelixAvatar(
                  size: HelixAvatarSize.xl,
                  semanticLabel: 'Your profile picture',
                  model: HelixAvatarModel(
                    name: data.name.isEmpty ? 'Helix' : data.name,
                    image: avatar == null ? null : MemoryImage(avatar),
                    colorIndex: HelixAvatarModel.colorIndexFor(
                      data.accountId.isEmpty ? 'helix' : data.accountId,
                    ),
                  ),
                ),
              ),
            ),
            if (canPick)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: HelixSpace.xs,
                children: [
                  TextButton.icon(
                    onPressed: edit.busy ? null : editor.chooseAvatar,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose a photo'),
                  ),
                  if (avatar != null)
                    TextButton.icon(
                      onPressed: edit.busy ? null : editor.removeAvatar,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo'),
                    ),
                ],
              ),
            const PageIntro(
              text:
                  'Your photo is kept on this phone. Sharing it with your '
                  'contacts is not available yet.',
            ),
            HelixSettingsSection(
              title: 'Name and about',
              footer:
                  'Your name and about line are encrypted. Only people you '
                  'have messaged can read them; Helix servers cannot.',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HelixSpace.md,
                    vertical: HelixSpace.xs,
                  ),
                  child: TextField(
                    controller: _name,
                    maxLength: ProfileRules.maxName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      errorText: edit.nameError,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HelixSpace.md,
                    vertical: HelixSpace.xs,
                  ),
                  child: TextField(
                    controller: _about,
                    maxLength: ProfileRules.maxAbout,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      labelText: 'About',
                      errorText: edit.aboutError,
                    ),
                  ),
                ),
                BusyFilledButton(
                  label: 'Save',
                  busy: edit.busy,
                  onPressed: () =>
                      editor.save(name: _name.text, about: _about.text),
                ),
              ],
            ),
            HelixSettingsSection(
              title: '~Helix name',
              footer:
                  'A ~name lets people find you without your number. It is '
                  'stored on the server, not encrypted, so pick one you are '
                  'happy for anyone to see. 3 to 32 letters, numbers, dots '
                  'or underscores, starting with a letter. Names that could '
                  'be mistaken for Helix staff are never available.',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HelixSpace.md,
                    vertical: HelixSpace.xs,
                  ),
                  child: TextField(
                    controller: _helixName,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 33,
                    decoration: InputDecoration(
                      labelText: 'Your ~name',
                      prefixText: '~',
                      errorText: edit.helixNameError,
                      errorMaxLines: 4,
                    ),
                  ),
                ),
                BusyFilledButton(
                  label: data.helixName == null ? 'Claim ~name' : 'Save ~name',
                  busy: edit.busy,
                  onPressed: () => editor.saveHelixName(_helixName.text),
                ),
                if (data.helixName != null)
                  HelixSettingsTile(
                    icon: Icons.person_remove_outlined,
                    title: 'Remove my ~name',
                    subtitle: 'Currently ~${data.helixName}',
                    destructive: true,
                    onTap: () async {
                      final ok = await showHelixDestructiveDialog(
                        context,
                        title: 'Remove your ~name?',
                        message:
                            'People will no longer be able to find you by '
                            '~${data.helixName}. Someone else may claim it.',
                        action: 'Remove',
                      );
                      if (ok) {
                        _helixName.clear();
                        await editor.clearHelixName();
                      }
                    },
                  ),
              ],
            ),
            HelixSettingsSection(
              title: 'Phone number',
              footer:
                  'Helix never shows your number to people. Those who '
                  'already have it can find you by it unless you turn that '
                  'off in Privacy.',
              children: [
                HelixSettingsTile(
                  icon: Icons.phone_outlined,
                  title: data.phoneMasked ?? 'Not shown on this device',
                  subtitle: 'Your number is hidden here',
                ),
              ],
            ),
            const SizedBox(height: HelixSpace.lg),
          ],
        ),
      },
    );
  }
}
