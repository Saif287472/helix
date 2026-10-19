import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart' as app;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: everything about one person, who they are, how to reach them,
/// how this chat behaves, whether its keys have been checked, and how to
/// block or report them, drawn by `orbit_ui`'s Contact info
/// (`contracts/people_groups.md`).
///
/// Reached from a long press in people search, from the conversation header
/// and from a group's member list at `PeoplePaths.person(accountId)`.
class ContactInfoScreen extends ConsumerStatefulWidget {
  const ContactInfoScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends ConsumerState<ContactInfoScreen> {
  String get _id => widget.accountId;

  ContactInfoActions get _actions => ref.read(contactInfoActionsProvider);

  @override
  void initState() {
    super.initState();
    // Their profile (name, about) is read once when the screen opens, when
    // this device already has their profile key.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _actions.refreshProfile(_id);
    });
  }

  static orbit.TrustState _trustOf(TrustState t) => switch (t) {
    TrustState.noKey => orbit.TrustState.noKey,
    TrustState.unverified => orbit.TrustState.unverified,
    TrustState.verified => orbit.TrustState.verified,
    TrustState.keyChanged => orbit.TrustState.keyChanged,
  };

  static orbit.DisappearAfter _disappearingOf(DisappearAfter d) => switch (d) {
    DisappearAfter.off => orbit.DisappearAfter.off,
    DisappearAfter.day => orbit.DisappearAfter.day,
    DisappearAfter.week => orbit.DisappearAfter.week,
    DisappearAfter.ninety => orbit.DisappearAfter.days90,
  };

  static DisappearAfter _appDisappearingOf(orbit.DisappearAfter d) =>
      switch (d) {
        orbit.DisappearAfter.off => DisappearAfter.off,
        orbit.DisappearAfter.day => DisappearAfter.day,
        orbit.DisappearAfter.week => DisappearAfter.week,
        orbit.DisappearAfter.days90 => DisappearAfter.ninety,
      };

  static app.MuteFor _muteOf(orbit.MuteFor m) => switch (m) {
    orbit.MuteFor.eightHours => app.MuteFor.eightHours,
    orbit.MuteFor.week => app.MuteFor.oneWeek,
    orbit.MuteFor.always => app.MuteFor.always,
  };

  static ReportReason _reasonOf(orbit.ReportReason r) => switch (r) {
    orbit.ReportReason.spam => ReportReason.spam,
    orbit.ReportReason.abuse => ReportReason.abuse,
    orbit.ReportReason.impersonation => ReportReason.impersonation,
    orbit.ReportReason.other => ReportReason.other,
  };

  static orbit.RenameResult _renamedOf(RenameOutcome r) => switch (r) {
    RenameOutcome.savedEverywhere => orbit.RenameResult.savedEverywhere,
    RenameOutcome.savedInHelix => orbit.RenameResult.saved,
    RenameOutcome.needsPhonePermission =>
      orbit.RenameResult.needsPhonePermission,
    RenameOutcome.phoneRefused => orbit.RenameResult.phoneRefused,
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contactPersonProvider(_id));
    final about = ref.watch(contactAboutProvider(_id)).value;
    final chat = ref.watch(contactChatProvider(_id)).value;
    final groups =
        ref.watch(commonGroupsProvider(_id)).value ?? const <GroupSummary>[];
    final blocksMe = ref.watch(contactBlocksMeProvider(_id)).value ?? false;
    // A person this device has no row for: say what is known.
    final person = async.value ?? ContactPerson.unknown(_id);
    final name = person.name;
    final actions = _actions;
    return orbit.ContactScreen(
      model: orbit.ContactModel(
        accountId: _id,
        name: name.display,
        avatar: name.avatar,
        secondary: person.numberLabel ?? name.names.secondary,
        about: about == null || about.trim().isEmpty ? null : about,
        trust: _trustOf(person.trust),
        blocked: name.blocked,
        blockedByThem: blocksMe,
        nickname: name.names.nickname,
        numberLabel: person.numberLabel,
        helixName: name.helixName,
        muted: chat?.muted ?? false,
        muteLabel: chat?.muteLabel,
        disappearing: _disappearingOf(
          DisappearAfter.of(chat?.disappearingSeconds),
        ),
        commonGroups: [for (final g in groups) (id: g.id, title: g.title)],
        loading: async.isLoading && !async.hasValue,
        loadFailed: async.hasError && !async.hasValue,
      ),
      actions: orbit.ContactActions(
        onMessage: () => actions.openChat(_id),
        onCall: ({required video}) => actions.startCall(_id, video: video),
        onRename: (value) async => _renamedOf(await actions.rename(_id, value)),
        onSaveToPhoneContacts: (value) async =>
            _renamedOf(await actions.savePhoneName(_id, value)),
        onMute: (length) =>
            actions.mute(_id, length == null ? null : _muteOf(length)),
        onSetDisappearing: (after) =>
            actions.setDisappearing(_id, _appDisappearingOf(after)),
        onOpenSharedMedia: () => actions.openSharedMedia(_id),
        onOpenSafetyNumber: () => context.push(PeoplePaths.safetyNumber(_id)),
        onOpenGroup: (groupId) {
          final group = groups.where((g) => g.id == groupId).firstOrNull;
          if (group != null) actions.openGroup(group);
        },
        onBlock: () => actions.block(_id),
        onUnblock: () => actions.unblock(_id),
        onReport: (report) => actions.report(
          _id,
          PersonReport(
            reason: _reasonOf(report.reason),
            note: report.note.isEmpty ? null : report.note,
          ),
        ),
        onRetry: () => ref.invalidate(contactPersonProvider(_id)),
      ),
    );
  }
}
