import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/presentation/widgets/key_changed_banner.dart';
import 'package:helix_remote/features/people/presentation/widgets/person_sheets.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Everything about one person: who they are, how to reach them, how this chat
/// behaves, whether its keys have been checked, and how to block or report
/// them.
///
/// Reached from a long press in people search, from the conversation header
/// (A2a) and from a group's member list (A3a) at
/// `PeoplePaths.person(accountId)`.
class ContactInfoScreen extends ConsumerStatefulWidget {
  const ContactInfoScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends ConsumerState<ContactInfoScreen> {
  String get _id => widget.accountId;

  @override
  void initState() {
    super.initState();
    // Their profile (name, about) is read once when the screen opens, when
    // this device already has their profile key.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(contactInfoActionsProvider).refreshProfile(_id);
    });
  }

  void _say(String message) {
    if (mounted) showHelixSnackBar(context, message);
  }

  Future<void> _rename(ContactPerson person) async {
    final actions = ref.read(contactInfoActionsProvider);
    final entered = await showHelixTextInputDialog(
      context,
      title: 'Rename',
      label: 'Name',
      initialValue: person.name.names.nickname ?? '',
      maxLength: 60,
    );
    if (entered == null || !mounted) return;
    var outcome = await actions.rename(_id, entered);
    if (!mounted) return;
    if (outcome == RenameOutcome.needsPhonePermission) {
      final allow = await showHelixConfirmDialog(
        context,
        title: 'Save in your phone contacts too?',
        message:
            'Helix can also save this name in your phone\'s contacts, so it '
            'shows up the same everywhere. This needs permission to change '
            'your contacts.',
        confirmLabel: 'Allow',
        cancelLabel: 'Not now',
      );
      if (!mounted) return;
      if (allow) {
        outcome = await actions.savePhoneName(_id, entered);
        if (!mounted) return;
      }
    }
    _say(switch (outcome) {
      RenameOutcome.savedEverywhere => 'Saved, and updated in your contacts.',
      RenameOutcome.phoneRefused =>
        'Saved in Helix. Your phone did not let Helix change your contacts.',
      RenameOutcome.savedInHelix ||
      RenameOutcome.needsPhonePermission => 'Saved.',
    });
  }

  Future<void> _mute(bool on) async {
    final actions = ref.read(contactInfoActionsProvider);
    if (!on) return actions.mute(_id, null);
    final choice = await showMuteSheet(context);
    if (choice != null) await actions.mute(_id, choice);
  }

  Future<void> _disappearing(int? current) async {
    final choice = await showDisappearingSheet(
      context,
      selected: DisappearAfter.of(current),
    );
    if (choice == null) return;
    await ref.read(contactInfoActionsProvider).setDisappearing(_id, choice);
  }

  Future<void> _block(ContactPerson person) async {
    final actions = ref.read(contactInfoActionsProvider);
    if (person.name.blocked) {
      await actions.unblock(_id);
      _say('Unblocked.');
      return;
    }
    final confirmed = await showHelixConfirmDialog(
      context,
      title: 'Block ${person.name.display}?',
      message:
          'They will not be able to message or call you, and will not be told '
          'that you blocked them.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;
    await actions.block(_id);
    _say('Blocked.');
  }

  Future<void> _report(ContactPerson person) async {
    final report = await showReportSheet(context, name: person.name.display);
    if (report == null || !mounted) return;
    try {
      await ref.read(contactInfoActionsProvider).report(_id, report);
      _say('Reported. No messages were sent with the report.');
    } on Object {
      _say('The report could not be sent. Try again in a moment.');
    }
  }

  Future<void> _call({required bool video}) async {
    final failure = await ref
        .read(contactInfoActionsProvider)
        .startCall(_id, video: video);
    if (failure != null) _say(failure);
  }

  Future<void> _sharedMedia() async {
    final opened = await ref
        .read(contactInfoActionsProvider)
        .openSharedMedia(_id);
    if (!opened) _say('Shared media could not be opened.');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contactPersonProvider(_id));
    final about = ref.watch(contactAboutProvider(_id)).value;
    final chat = ref.watch(contactChatProvider(_id)).value;
    final groups =
        ref.watch(commonGroupsProvider(_id)).value ?? const <GroupSummary>[];
    final person = async.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Contact info')),
      body: async.when(
        loading: () => const HelixAsyncPanel(loading: true, child: SizedBox()),
        error: (_, _) => const HelixErrorState(
          message: 'This person could not be loaded. Go back and try again.',
        ),
        data: (_) => _content(
          person ??
              // A person this device has no row for: say what is known.
              ContactPerson.unknown(_id),
          about,
          chat,
          groups,
        ),
      ),
    );
  }

  Widget _content(
    ContactPerson person,
    String? about,
    ContactChatSettings? chat,
    List<GroupSummary> groups,
  ) {
    final name = person.name;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = person.numberLabel ?? name.names.secondary;

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(HelixSpace.lg),
          child: Column(
            children: [
              HelixAvatar(
                model: name.avatar,
                size: HelixAvatarSize.xl,
                semanticLabel: 'Picture of ${name.display}',
              ),
              const SizedBox(height: HelixSpace.sm),
              Semantics(
                header: true,
                child: Text(
                  name.display,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (secondary != null)
                Text(
                  secondary,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              if (name.blocked)
                Padding(
                  padding: const EdgeInsets.only(top: HelixSpace.xxs),
                  child: Text('Blocked', style: TextStyle(color: scheme.error)),
                ),
              if (about != null && about.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: HelixSpace.xs),
                  child: Text(about, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
          child: Row(
            children: [
              _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Message',
                onTap: () => ref.read(contactInfoActionsProvider).openChat(_id),
              ),
              _ActionButton(
                icon: Icons.call_outlined,
                label: 'Voice call',
                onTap: () => _call(video: false),
              ),
              _ActionButton(
                icon: Icons.videocam_outlined,
                label: 'Video call',
                onTap: () => _call(video: true),
              ),
            ],
          ),
        ),
        if (person.trust == TrustState.keyChanged)
          KeyChangedBanner(
            name: name.display,
            onReview: () => context.push(PeoplePaths.safetyNumber(_id)),
          ),
        HelixSettingsSection(
          title: 'Name',
          footer: person.hasNumber
              ? 'Renaming also saves the name in your phone\'s contacts.'
              : null,
          children: [
            HelixSettingsTile(
              icon: Icons.edit_outlined,
              title: 'Rename',
              subtitle: name.names.nickname ?? 'Choose a name only you see',
              showChevron: true,
              onTap: () => _rename(person),
            ),
            if (person.numberLabel != null)
              HelixSettingsTile(
                icon: Icons.phone_outlined,
                title: person.numberLabel!,
                subtitle: 'Phone number',
              ),
            if (name.helixName != null)
              HelixSettingsTile(
                icon: Icons.alternate_email,
                title: '~${name.helixName}',
                subtitle: 'Helix name',
              ),
          ],
        ),
        HelixSettingsSection(
          title: 'Chat',
          children: [
            HelixSettingsTile(
              icon: Icons.photo_library_outlined,
              title: 'Media, links and docs',
              showChevron: true,
              onTap: _sharedMedia,
            ),
            HelixSettingsSwitchTile(
              icon: Icons.notifications_off_outlined,
              title: 'Mute notifications',
              subtitle: chat?.muteLabel,
              value: chat?.muted ?? false,
              onChanged: _mute,
            ),
            HelixSettingsTile(
              icon: Icons.timer_outlined,
              title: 'Disappearing messages',
              subtitle: DisappearAfter.of(chat?.disappearingSeconds).label,
              showChevron: true,
              onTap: () => _disappearing(chat?.disappearingSeconds),
            ),
          ],
        ),
        HelixSettingsSection(
          title: 'Encryption',
          footer:
              'Messages and calls with ${name.display} are end-to-end '
              'encrypted. Only the two of you can read them.',
          children: [
            HelixSettingsTile(
              icon: switch (person.trust) {
                TrustState.verified => Icons.verified_user,
                TrustState.keyChanged => Icons.warning_amber_rounded,
                _ => Icons.verified_user_outlined,
              },
              title: 'Verify safety number',
              subtitle: switch (person.trust) {
                TrustState.verified => 'Verified',
                TrustState.keyChanged => 'Safety number changed',
                TrustState.unverified => 'Not verified',
                TrustState.noKey => 'Available after your first message',
              },
              showChevron: true,
              onTap: person.trust == TrustState.noKey
                  ? () => _say(
                      'Send a message first. A safety number needs both of '
                      'your keys.',
                    )
                  : () => context.push(PeoplePaths.safetyNumber(_id)),
            ),
          ],
        ),
        if (groups.isNotEmpty)
          HelixSettingsSection(
            title: groups.length == 1
                ? '1 group in common'
                : '${groups.length} groups in common',
            children: [
              for (final group in groups)
                HelixSettingsTile(
                  icon: Icons.group_outlined,
                  title: group.title,
                  showChevron: true,
                  onTap: () =>
                      ref.read(contactInfoActionsProvider).openGroup(group),
                ),
            ],
          ),
        HelixSettingsSection(
          children: [
            HelixSettingsTile(
              icon: name.blocked ? Icons.lock_open : Icons.block,
              title: name.blocked
                  ? 'Unblock ${name.display}'
                  : 'Block ${name.display}',
              destructive: !name.blocked,
              onTap: () => _block(person),
            ),
            HelixSettingsTile(
              icon: Icons.flag_outlined,
              title: 'Report ${name.display}',
              destructive: true,
              onTap: () => _report(person),
            ),
          ],
        ),
        const SizedBox(height: HelixSpace.lg),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: HelixRadius.card,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(height: HelixSpace.xxs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
