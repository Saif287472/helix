import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The group keys (`prototype/js/screens/groups.js`) on the sample data.

HelixPersonItem _p(String id) => OrbitFakes.people[id]!;

const _candidates = [
  'nadia',
  'arif',
  'sadia',
  'tanvir',
  'ammu',
  'abbu',
  'rumana',
  'karim',
  'rafiq',
];

List<HelixPersonItem> get _people => [for (final id in _candidates) _p(id)];

/// The picker with its own picks, so ticking works in the preview.
class _Picking extends StatefulWidget {
  const _Picking({required this.build, this.start = const []});

  final Widget Function(List<String> picked, ValueChanged<String> toggle) build;
  final List<String> start;

  @override
  State<_Picking> createState() => _PickingState();
}

class _PickingState extends State<_Picking> {
  late final _picked = [...widget.start];

  @override
  Widget build(BuildContext context) => widget.build(
    _picked,
    (id) => setState(
      () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
    ),
  );
}

Widget _newGroup({
  String name = '',
  List<String> sel = const [],
  bool error = false,
}) => _Picking(
  start: sel,
  build: (picked, toggle) => NewGroupScreen(
    model: NewGroupModel(
      name: name,
      nameError: error ? 'Enter a group name of 1 to 100 characters.' : null,
      picker: MemberPickerModel(candidates: _people, selected: picked),
    ),
    actions: NewGroupActions(picker: MemberPickerActions(onToggle: toggle)),
  ),
);

/// `FAMILY.members` seen by someone with [role].
GroupInfoModel _info(
  String role, {
  bool everyone = false,
  String? pendingReason,
}) {
  final admin = role != 'member';
  final open = admin || everyone;
  final members = [
    ('me', role),
    ('ammu', role == 'owner' ? 'admin' : 'owner'),
    ('abbu', 'admin'),
    ('rumana', 'member'),
    ('karim', 'member'),
  ];
  String label(String r) => switch (r) {
    'owner' => 'Owner',
    'admin' => 'Admin',
    _ => '',
  };
  return GroupInfoModel(
    groupId: 'family',
    title: 'Family',
    avatar: const HelixAvatarModel(name: 'Family', isGroup: true),
    memberCountLabel: '5 members',
    description: 'Eid plans, dinners and everything in between.',
    isOwner: role == 'owner',
    canAdminister: admin,
    canEditInfo: open,
    canAddMembers: open,
    disappearing: DisappearAfter.week,
    joinRequestCount: 2,
    members: [
      for (final (id, r) in members)
        GroupMemberView(
          account: id,
          title: id == 'me' ? 'You' : _p(id).names.display,
          avatar: id == 'me'
              ? const HelixAvatarModel(name: OrbitFakes.meName)
              : _p(id).avatar,
          roleLabel: label(r),
          detail: id == 'me' ? '' : _p(id).names.secondary ?? '',
          notConfirmed: id == 'karim',
          isAdmin: r == 'admin',
          canAct:
              id != 'me' &&
              (role == 'owner' || (role == 'admin' && r == 'member')),
        ),
    ],
    pending: [
      PendingMemberItem(
        account: 'karim',
        title: 'Confirm Karim Uncle?',
        explanation:
            '${pendingReason == 'link' ? 'Karim Uncle joined this group through its invite link, and nothing else vouches for them.' : 'Karim Uncle was added by the server roster, but no admin of this group announced it.'}'
            ' Until you confirm, what you send in this group stays '
            'unreadable to them.',
        canRemove: admin,
      ),
    ],
  );
}

PersonEntryView _entry(String id, String when) => PersonEntryView(
  account: id,
  title: _p(id).names.display,
  whenLabel: when,
  avatar: _p(id).avatar,
);

const _link1 = 'https://helix.agiletechbd.com/open#HLX-GRP-8KQ2-ZP4M-W7DX-3RTA';
const _link2 = 'https://helix.agiletechbd.com/open#HLX-GRP-2VNC-HY6Q-5BJE-K9LS';

JoinGroupModel _join(
  JoinStage stage, {
  bool approval = false,
  bool member = false,
  bool noName = false,
}) => JoinGroupModel(
  stage: stage,
  initialLink: stage == JoinStage.input ? '' : _link1,
  previewName: noName ? '' : 'Book Club',
  previewMemberCount: 14,
  previewDescription: 'One book a month, coffee every Saturday.',
  previewAvatar: const HelixAvatarModel(
    name: 'Book Club',
    isGroup: true,
    colorIndex: 1,
  ),
  requiresApproval: approval,
  alreadyMember: member,
);

final Map<String, WidgetBuilder> groupPreviews = {
  'group-new': (_) => _newGroup(),
  'group-new-picked': (_) =>
      _newGroup(name: 'Weekend trip', sel: const ['nadia', 'arif', 'sadia']),
  'group-new-error': (_) => _newGroup(sel: const ['nadia'], error: true),
  'group-info': (_) => GroupInfoScreen(model: _info('admin')),
  'group-info-owner': (_) => GroupInfoScreen(model: _info('owner')),
  'group-info-member': (_) => GroupInfoScreen(model: _info('member')),
  'group-info-member-open': (_) =>
      GroupInfoScreen(model: _info('member', everyone: true)),
  'group-info-pending-link': (_) =>
      GroupInfoScreen(model: _info('admin', pendingReason: 'link')),
  'group-info-gone': (_) => const GroupInfoScreen(
    model: GroupInfoModel(
      groupId: 'family',
      title: 'Family',
      avatar: HelixAvatarModel(name: 'Family', isGroup: true),
      status: GroupInfoStatus.gone,
    ),
  ),
  'group-settings': (_) =>
      const GroupSettingsScreen(model: GroupSettingsModel()),
  'group-settings-member': (_) =>
      const GroupSettingsScreen(model: GroupSettingsModel(canChange: false)),
  'group-invite': (_) => const InviteLinksScreen(
    model: InviteLinksModel(
      links: [
        InviteLinkItem(id: '1', url: _link1, approve: true),
        InviteLinkItem(id: '2', url: _link2),
      ],
    ),
  ),
  'group-invite-empty': (_) =>
      const InviteLinksScreen(model: InviteLinksModel()),
  'group-requests': (_) => JoinRequestsScreen(
    model: JoinRequestsModel(
      requests: [
        _entry('sadia', 'Asked today at 09:02'),
        _entry('tanvir', 'Asked yesterday at 21:40'),
      ],
    ),
  ),
  'group-requests-empty': (_) =>
      const JoinRequestsScreen(model: JoinRequestsModel()),
  'group-banned': (_) => BannedPeopleScreen(
    model: BannedPeopleModel(people: [_entry('shuvo', 'Banned 2 October')]),
  ),
  'group-banned-empty': (_) =>
      const BannedPeopleScreen(model: BannedPeopleModel()),
  'group-add': (_) => _Picking(
    build: (picked, toggle) => AddMembersScreen(
      model: AddMembersModel(
        picker: MemberPickerModel(
          candidates: _people,
          selected: picked,
          exclude: const {'ammu', 'abbu', 'rumana', 'karim'},
        ),
      ),
      actions: AddMembersActions(picker: MemberPickerActions(onToggle: toggle)),
    ),
  ),
  'group-join': (_) => JoinGroupScreen(model: _join(JoinStage.input)),
  'group-join-preview': (_) => JoinGroupScreen(model: _join(JoinStage.preview)),
  'group-join-approval': (_) =>
      JoinGroupScreen(model: _join(JoinStage.preview, approval: true)),
  'group-join-member': (_) =>
      JoinGroupScreen(model: _join(JoinStage.preview, member: true)),
  'group-join-noname': (_) =>
      JoinGroupScreen(model: _join(JoinStage.preview, noName: true)),
  'group-join-done': (_) => JoinGroupScreen(model: _join(JoinStage.joined)),
  'group-join-pending': (_) => JoinGroupScreen(model: _join(JoinStage.pending)),
  'group-join-failed': (_) => JoinGroupScreen(model: _join(JoinStage.failed)),
};
