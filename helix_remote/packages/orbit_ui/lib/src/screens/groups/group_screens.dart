import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_bits.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/you_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/chat/chat_screen.dart'
    show PendingMemberItem;
import 'package:orbit_ui/src/screens/people/people_screens.dart'
    show DisappearAfter;
import 'package:orbit_ui/src/screens/signin/entry_screens.dart'
    show OrbitButtonRow;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// A missing action does nothing, rather than drawing its button disabled.
void _none() {}

/// What a group change answered: the sentence to show, or null for none
/// (`GroupResult.message` in the app).
typedef GroupAnswer = Future<String?>;

/// Shows [answer]'s sentence, if any, as a toast.
Future<void> _tell(BuildContext context, GroupAnswer? answer) async {
  final text = await answer;
  if (text != null && text.isNotEmpty && context.mounted) {
    showOrbitToast(context, text);
  }
}

/// A page with an app bar over its own column (the prototype's
/// `UI.appbar(...)` followed by a `.scroll` and a floating button).
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.body, this.fab});

  final String title;
  final Widget body;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(
              title: title,
              onLead: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: body),
                  if (fab != null)
                    Positioned(right: 16, bottom: 34, child: fab!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.xfab`: the labelled floating button (Create, Add). 56px, corner 20,
/// `--accent`, a 21px icon 10px before the label at 14.5px weight 600, and
/// the theme's `--glow` (Orbit has none: the later `.xfab` rule wins over
/// the first's blue shadow).
class OrbitExtendedFab extends StatelessWidget {
  const OrbitExtendedFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final OrbitGlyph icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: t.glow,
        ),
        child: Material(
          color: t.accent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : (onPressed ?? _none),
            splashFactory: NoSplash.splashFactory,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      OrbitSpinner(size: 21, color: t.onAccent)
                    else
                      OrbitIcon(
                        icon,
                        weight: OrbitIconWeight.bold,
                        size: 21,
                        color: t.onAccent,
                      ),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: t.font.style(
                        size: 14.5,
                        weight: 600,
                        color: t.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- member picker

class MemberPickerModel {
  const MemberPickerModel({
    this.candidates = const [],
    this.selected = const [],
    this.exclude = const {},
    this.loading = false,
    this.loadFailed = false,
  });

  final List<HelixPersonItem> candidates;

  /// In pick order.
  final List<String> selected;
  final Set<String> exclude;
  final bool loading;
  final bool loadFailed;
}

class MemberPickerActions {
  const MemberPickerActions({this.onToggle, this.onLookup, this.onRetry});

  final ValueChanged<String>? onToggle;

  /// Looks up a number or ~name ("Find … on Orbit"): the person found, or
  /// the sentence that says why not.
  final Future<({HelixPersonItem? found, String? error})> Function(
    String query,
  )?
  onLookup;
  final VoidCallback? onRetry;
}

/// The member picker of New group and Add members: chips of the people
/// picked, a search, a "Find on Orbit" row for a number or ~name, and the
/// people, each with a round tick.
class MemberPicker extends StatefulWidget {
  const MemberPicker({
    super.key,
    required this.model,
    this.actions = const MemberPickerActions(),
    this.looking = false,
  });

  final MemberPickerModel model;
  final MemberPickerActions actions;

  /// A lookup is running.
  final bool looking;

  @override
  State<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<MemberPicker> {
  final _query = TextEditingController();
  var _q = '';
  var _looking = false;

  /// People found by a look-up, until the candidates catch up with them.
  final Map<String, HelixPersonItem> _found = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The name, number, ~name, nickname or phone-book name has [q] in it.
  static bool _matches(HelixPersonItem p, String q, String digits) {
    if (q.isEmpty) return true;
    final n = p.names;
    return n.display.toLowerCase().contains(q) ||
        (n.number ?? '').contains(q) ||
        (digits.isNotEmpty &&
            (n.number ?? '').replaceAll(RegExp(r'\D'), '').contains(digits)) ||
        (n.helixName ?? '').toLowerCase().contains(q) ||
        (n.nickname ?? '').toLowerCase().contains(q) ||
        (n.phoneBookName ?? '').toLowerCase().contains(q);
  }

  /// A phone number (7 or more of its characters) or a `~name`: worth
  /// looking up.
  bool get _lookable {
    final text = _q.trim();
    if (text.startsWith('~')) return text.length > 1;
    return RegExp(r'^\+?[\d\s\-().]{7,}$').hasMatch(text);
  }

  Future<void> _lookup() async {
    final look = widget.actions.onLookup;
    if (look == null || _looking) return;
    setState(() => _looking = true);
    final result = await look(_q.trim());
    if (!mounted) return;
    setState(() => _looking = false);
    final found = result.found;
    if (found == null) {
      showOrbitToast(
        context,
        result.error ?? 'Nobody matches that.',
        error: true,
      );
      return;
    }
    if (widget.model.exclude.contains(found.id)) {
      showOrbitToast(context, 'That person is already in this group.');
      return;
    }
    setState(() {
      _found[found.id] = found;
      _query.clear();
      _q = '';
    });
    if (!widget.model.selected.contains(found.id)) {
      widget.actions.onToggle?.call(found.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final q = _q.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final all = {..._found, for (final p in m.candidates) p.id: p};
    final people = [
      for (final p in all.values)
        if (!m.exclude.contains(p.id) && _matches(p, q, qDigits)) p,
    ];
    final lookup = _lookable && people.isEmpty;
    final byId = all;
    final children = <Widget>[
      if (m.selected.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            4,
            OrbitSpace.gutter,
            6,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in m.selected)
                if (byId[id] != null) _chip(t, byId[id]!),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          OrbitSpace.gutter,
          6,
          OrbitSpace.gutter,
          6,
        ),
        // The 46px field answers across 48px, from the padding around it.
        child: OrbitTapArea(
          merge: true,
          child: SizedBox(
            height: 46,
            child: OrbitSearchField(
              hint: 'Search name, number or ~name',
              controller: _query,
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ),
      ),
      if (lookup)
        _row(
          t,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(44 * t.avatarR / 100),
            ),
            child: Center(
              child: widget.looking || _looking
                  ? OrbitSpinner(size: 19, color: t.accent)
                  : OrbitIcon(
                      OrbitIcons.userPlus,
                      weight: OrbitIconWeight.bold,
                      size: 19,
                      color: t.accent,
                    ),
            ),
          ),
          title: 'Find “${_q.trim()}” on Orbit',
          height: orbitRowHeight,
          onTap: _lookup,
        ),
      if (m.loading)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: OrbitPageLoading(),
        )
      else if (m.loadFailed)
        OrbitLoadFailed(
          title: 'Your people could not be loaded.',
          onRetry: a.onRetry,
        )
      else if (people.isNotEmpty)
        for (final p in people)
          Semantics(
            selected: m.selected.contains(p.id),
            child: _row(
              t,
              leading: OrbitAvatar(avatar: p.avatar, size: 44),
              title: p.names.display,
              sub: p.names.secondary ?? '',
              trailing: OrbitPick(on: m.selected.contains(p.id)),
              onTap: () => a.onToggle?.call(p.id),
            ),
          )
      else if (!lookup && q.isNotEmpty)
        const OrbitSectionFoot('No results')
      else if (!lookup)
        const OrbitEmptyState(
          icon: OrbitIcons.userCircleDashed,
          title: 'Nobody here yet',
          text: 'Type a phone number or a ~name to find someone on Orbit.',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// `.mchip`: 36px, corner 12, `--accent-soft` with an `--accent-line`
  /// edge, a 28px picture, the first name, and a 28px ×.
  Widget _chip(OrbitTokens t, HelixPersonItem p) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: t.accentSoft,
      border: Border.all(color: t.accentLine),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrbitAvatar(avatar: p.avatar, size: 28),
        const SizedBox(width: 6),
        Text(
          p.names.display.split(' ').first,
          style: t.font.style(size: 13, weight: 560, color: t.accentInk),
        ),
        const SizedBox(width: 6),
        OrbitIconButton(
          icon: OrbitIcons.x,
          tooltip: 'Remove from selection',
          size: 28,
          iconSize: 14,
          color: t.accentInk,
          onPressed: () => widget.actions.onToggle?.call(p.id),
        ),
      ],
    ),
  );

  Widget _row(
    OrbitTokens t, {
    required Widget leading,
    required String title,
    String sub = '',
    Widget? trailing,
    double height = 64,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    hoverColor: t.hover,
    splashFactory: NoSplash.splashFactory,
    // [height], taller only when large text needs it.
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.font.style(
                      size: OrbitType.headline,
                      weight: 600,
                      color: t.ink,
                      letterSpacingEm: -0.01,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    OrbitText(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.mono.style(size: 12, color: t.ink3),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 14), trailing],
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- new group

class NewGroupModel {
  const NewGroupModel({
    this.name = '',
    this.nameError,
    this.error,
    this.hasPicture = false,
    this.picture,
    this.picker = const MemberPickerModel(),
    this.creating = false,
  });

  final String name;

  /// "Enter a group name of 1 to 100 characters."
  final String? nameError;
  final String? error;
  final bool hasPicture;
  final ImageProvider? picture;
  final MemberPickerModel picker;
  final bool creating;
}

class NewGroupActions {
  const NewGroupActions({
    this.onNameChanged,
    this.onChoosePicture,
    this.onRemovePicture,
    this.picker = const MemberPickerActions(),
    this.onCreate,
    this.onOpenGroupChat,
  });

  final ValueChanged<String>? onNameChanged;

  /// Opens the phone's picker; the sentence when the file could not be
  /// used.
  final GroupAnswer Function()? onChoosePicture;
  final VoidCallback? onRemovePicture;
  final MemberPickerActions picker;

  /// Makes the group: null when it failed (the model's error says why),
  /// else the group and the names of anyone who could not be added.
  final Future<
    ({String groupId, String conversationId, List<String> notAddedNames})?
  >
  Function()?
  onCreate;

  /// Replaces this page with the new group's chat.
  final void Function(String groupId, String conversationId)? onOpenGroupChat;
}

/// `group-new`: a picture circle and the name, then Members (the picker),
/// and Create with N floating over it.
class NewGroupScreen extends StatelessWidget {
  const NewGroupScreen({
    super.key,
    required this.model,
    this.actions = const NewGroupActions(),
  });

  final NewGroupModel model;
  final NewGroupActions actions;

  Future<void> _choosePicture(BuildContext context) =>
      _tell(context, actions.onChoosePicture?.call());

  /// Creates the group, explains anyone who could not be added, then opens
  /// the group's chat.
  Future<void> _create(BuildContext context) async {
    final create = actions.onCreate;
    if (create == null || model.creating) return;
    final made = await create();
    if (made == null || !context.mounted) return;
    void open() =>
        actions.onOpenGroupChat?.call(made.groupId, made.conversationId);
    final names = made.notAddedNames;
    if (names.isEmpty) {
      open();
      return;
    }
    final who = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} and '
              '${names.last}';
    await showOrbitDialog(
      context,
      title: 'Some people were not added',
      text:
          '$who could not be added. The group was created; send them an '
          'invite link from the group\u2019s page.',
      actions: const [OrbitDialogAction('OK', kind: OrbitButtonKind.primary)],
    );
    open();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final n = m.picker.selected.length;
    final picture = Tooltip(
      message: 'Add a group picture',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: 'Add a group picture',
        child: GestureDetector(
          onTap: m.hasPicture
              ? () => showOrbitSheet(
                  context,
                  title: 'Group picture',
                  items: [
                    OrbitMenuItem(
                      icon: OrbitIcons.image,
                      label: 'Choose another picture',
                      onTap: () => _choosePicture(context),
                    ),
                    OrbitMenuItem(
                      icon: OrbitIcons.trash,
                      label: 'Remove picture',
                      danger: true,
                      onTap: a.onRemovePicture,
                    ),
                  ],
                )
              : () => _choosePicture(context),
          child: CustomPaint(
            foregroundPainter: _DashedRRect(
              color: t.accentLine,
              radius: 64 * t.avatarR / 100,
            ),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.accentSoft,
                image: m.picture == null
                    ? null
                    : DecorationImage(image: m.picture!, fit: BoxFit.cover),
                borderRadius: BorderRadius.circular(64 * t.avatarR / 100),
              ),
              child: Center(
                child: OrbitIcon(
                  m.hasPicture ? OrbitIcons.check : OrbitIcons.cameraPlus,
                  size: 64 * 0.46,
                  color: t.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return _Frame(
      title: 'New group',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OrbitSpace.gutter,
              16,
              OrbitSpace.gutter,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                picture,
                const SizedBox(width: 14),
                Expanded(
                  child: OrbitTextField(
                    label: 'Group name',
                    initialValue: m.name,
                    error: m.nameError ?? '',
                    maxLength: 100,
                    onChanged: a.onNameChanged,
                  ),
                ),
              ],
            ),
          ),
          if (m.error != null)
            OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.error!),
          const OrbitListLabel('Members'),
          MemberPicker(model: m.picker, actions: a.picker),
        ],
      ),
      fab: OrbitExtendedFab(
        icon: OrbitIcons.check,
        label: n > 0 ? 'Create with $n' : 'Create group',
        busy: m.creating,
        onPressed: () => _create(context),
      ),
    );
  }
}

/// `border: 1.5px dashed`: Chrome's dashes on a rounded box, 4.5px on and
/// 3px off.
class _DashedRRect extends CustomPainter {
  const _DashedRRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius - 0.75),
        ),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7.5) {
        canvas.drawPath(m.extractPath(d, d + 4.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}

// --------------------------------------------------------------- group info

enum GroupInfoStatus { loading, failed, gone, ready }

enum MemberAction { makeAdmin, removeAdmin, makeOwner, remove, ban }

class GroupMemberView {
  const GroupMemberView({
    required this.account,
    required this.title,
    required this.avatar,
    this.roleLabel = '',
    this.detail = '',
    this.notConfirmed = false,
    this.isAdmin = false,
    this.canAct = false,
    this.actions,
  });

  final String account;

  /// "You" for yourself.
  final String title;
  final HelixAvatarModel avatar;

  /// "Owner", "Admin" or empty.
  final String roleLabel;

  /// Their number or ~name.
  final String detail;
  final bool notConfirmed;
  final bool isAdmin;

  /// You may change their role or remove them.
  final bool canAct;

  /// What you may do to them, when the app decides it (an admin may not
  /// make an owner); null is the prototype's whole menu.
  final Set<MemberAction>? actions;
}

class GroupInfoModel {
  const GroupInfoModel({
    required this.groupId,
    required this.title,
    required this.avatar,
    this.status = GroupInfoStatus.ready,
    this.memberCountLabel = '',
    this.description,
    this.isOwner = false,
    this.canAdminister = false,
    this.canEditInfo = false,
    this.canAddMembers = false,
    this.disappearing = DisappearAfter.off,
    this.joinRequestCount = 0,
    this.members = const [],
    this.pending = const [],
    this.hasPicture = true,
    this.note,
    this.disappearingLabel,
  });

  final String groupId;
  final GroupInfoStatus status;
  final String title;
  final HelixAvatarModel avatar;
  final String memberCountLabel;
  final String? description;
  final bool isOwner;
  final bool canAdminister;
  final bool canEditInfo;
  final bool canAddMembers;
  final DisappearAfter disappearing;
  final int joinRequestCount;
  final List<GroupMemberView> members;
  final List<PendingMemberItem> pending;

  /// The group has a picture to remove.
  final bool hasPicture;

  /// A line under the name ("The group's name is still arriving.").
  final String? note;

  /// The timer's name when it is none of the four choices ("3 days").
  final String? disappearingLabel;
}

class GroupInfoActions {
  const GroupInfoActions({
    this.onChoosePicture,
    this.onRemovePicture,
    this.onSaveInfo,
    this.onSetDisappearing,
    this.onMemberAction,
    this.onConfirmPending,
    this.onRemovePending,
    this.onOpenSettings,
    this.onOpenInviteLinks,
    this.onOpenJoinRequests,
    this.onOpenBanned,
    this.onAddMembers,
    this.onLeave,
    this.onDelete,
    this.onRetry,
    this.onBack,
  });

  // Each change answers with the sentence to show (`GroupAnswer`).
  final GroupAnswer Function()? onChoosePicture;
  final GroupAnswer Function()? onRemovePicture;
  final GroupAnswer Function(String name, String description)? onSaveInfo;
  final GroupAnswer Function(DisappearAfter after)? onSetDisappearing;
  final GroupAnswer Function(String account, MemberAction action)?
  onMemberAction;
  final GroupAnswer Function(String account)? onConfirmPending;
  final GroupAnswer Function(String account)? onRemovePending;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenInviteLinks;
  final VoidCallback? onOpenJoinRequests;
  final VoidCallback? onOpenBanned;
  final VoidCallback? onAddMembers;

  /// Leaving and deleting go back to Chats when they work; the app does
  /// that and says so.
  final GroupAnswer Function()? onLeave;
  final GroupAnswer Function()? onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
}

/// `group-info`: the group's picture, name and description; unconfirmed
/// members to confirm; the Group section (admin pages); the members; and
/// Leave (and Delete for the owner).
class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({
    super.key,
    required this.model,
    this.actions = const GroupInfoActions(),
  });

  final GroupInfoModel model;
  final GroupInfoActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final List<Widget> body;
    switch (m.status) {
      case GroupInfoStatus.loading:
        body = const [SizedBox(height: 120), OrbitPageLoading()];
      case GroupInfoStatus.failed:
        body = [
          OrbitLoadFailed(
            title: 'This group could not be loaded.',
            onRetry: a.onRetry,
          ),
        ];
      case GroupInfoStatus.gone:
        body = [
          OrbitEmptyState(
            icon: OrbitIcons.usersThree,
            title: 'You are not in this group',
            text:
                'You left it, were removed, or it was deleted. Its messages '
                'stay in your chats.',
            action: OrbitButton(
              label: 'Go back',
              kind: OrbitButtonKind.secondary,
              onPressed: a.onBack ?? () => Navigator.maybePop(context),
            ),
          ),
        ];
      case GroupInfoStatus.ready:
        body = _ready(context, t);
    }
    return OrbitPage(title: 'Group info', children: body);
  }

  List<Widget> _ready(BuildContext context, OrbitTokens t) {
    final m = model;
    final a = actions;
    final title = m.title;
    void confirm(String head, String text, String yes, VoidCallback? run) =>
        showOrbitDialog(
          context,
          title: head,
          text: text,
          actions: [
            const OrbitDialogAction('Cancel'),
            OrbitDialogAction(
              yes,
              kind: OrbitButtonKind.danger,
              onPressed: run,
            ),
          ],
        );
    final hero = Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
      child: Column(
        children: [
          Semantics(
            container: true,
            button: m.canEditInfo,
            label: m.canEditInfo ? 'Change group picture' : 'Group picture',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: m.canEditInfo
                  ? () => showOrbitSheet(
                      context,
                      title: 'Group picture',
                      items: [
                        OrbitMenuItem(
                          icon: OrbitIcons.image,
                          label: 'Choose a picture',
                          onTap: () =>
                              _tell(context, a.onChoosePicture?.call()),
                        ),
                        if (m.hasPicture)
                          OrbitMenuItem(
                            icon: OrbitIcons.trash,
                            label: 'Remove picture',
                            danger: true,
                            onTap: () =>
                                _tell(context, a.onRemovePicture?.call()),
                          ),
                      ],
                    )
                  : null,
              child: OrbitAvatar(avatar: m.avatar, size: 112),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            container: true,
            header: true,
            child: OrbitText(
              title,
              textAlign: TextAlign.center,
              style: t.display(size: 24),
            ),
          ),
          const SizedBox(height: 4),
          OrbitText(
            m.memberCountLabel,
            style: t.mono.style(size: 12.5, color: t.ink3),
          ),
          if (m.note != null) ...[
            const SizedBox(height: 8),
            OrbitText(
              m.note!,
              textAlign: TextAlign.center,
              style: t.font.style(size: OrbitType.caption, color: t.ink3),
            ),
          ],
          if ((m.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: OrbitText(
                m.description!,
                textAlign: TextAlign.center,
                style: t.font.style(
                  size: OrbitType.small,
                  color: t.ink2,
                  height: 1.45,
                ),
              ),
            ),
          ],
          if (m.canEditInfo) ...[
            const SizedBox(height: 16),
            OrbitButton(
              label: 'Edit group info',
              icon: OrbitIcons.pencilSimple,
              kind: OrbitButtonKind.secondary,
              height: 40,
              onPressed: () => _edit(context),
            ),
          ],
        ],
      ),
    );
    return [
      hero,
      for (final p in m.pending) _pending(context, t, p, confirm),
      OrbitSection(
        title: 'Group',
        rows: [
          OrbitListRow(
            icon: OrbitIcons.timer,
            iconColor: 5,
            title: 'Disappearing messages',
            value: m.disappearingLabel ?? m.disappearing.label,
            end: m.canAdminister ? OrbitRowEnd.chevron : OrbitRowEnd.none,
            onTap: m.canAdminister
                ? () => showOrbitSheet(
                    context,
                    title: 'Disappearing messages',
                    text:
                        'New messages in this group disappear after this '
                        'long, for everyone.',
                    items: [
                      for (final d in DisappearAfter.values)
                        OrbitMenuItem(
                          icon: OrbitIcons.timer,
                          label: d.label,
                          on: d == m.disappearing,
                          onTap: () =>
                              _tell(context, a.onSetDisappearing?.call(d)),
                        ),
                    ],
                  )
                : null,
          ),
          if (m.canAdminister) ...[
            OrbitListRow(
              icon: OrbitIcons.slidersHorizontal,
              iconColor: 0,
              title: 'Group settings',
              sub: 'Who can edit, add people and send',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenSettings,
            ),
            OrbitListRow(
              icon: OrbitIcons.linkSimple,
              iconColor: 1,
              title: 'Invite with a link',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenInviteLinks,
            ),
            OrbitListRow(
              icon: OrbitIcons.userCirclePlus,
              iconColor: 3,
              title: 'Join requests',
              sub: m.joinRequestCount == 0
                  ? ''
                  : m.joinRequestCount == 1
                  ? '1 person is waiting'
                  : '${m.joinRequestCount} people are waiting',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenJoinRequests,
            ),
            OrbitListRow(
              icon: OrbitIcons.prohibit,
              iconColor: 7,
              title: 'Banned people',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenBanned,
            ),
          ],
        ],
      ),
      OrbitGroupTitle(m.memberCountLabel),
      OrbitCard(
        children: [
          if (m.canAddMembers)
            OrbitListRow(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: OrbitIcon(
                    OrbitIcons.userPlus,
                    weight: OrbitIconWeight.bold,
                    size: 19,
                    color: t.onAccent,
                  ),
                ),
              ),
              title: 'Add members',
              accent: true,
              onTap: a.onAddMembers,
            ),
          for (final mem in m.members) _member(context, t, mem, confirm),
        ],
      ),
      OrbitSection(
        rows: [
          OrbitListRow(
            icon: OrbitIcons.signOut,
            title: 'Leave group',
            danger: true,
            onTap: () => confirm(
              'Leave “$title”?',
              'You will stop getting its messages. Its history stays in '
                  'your chats. You can only come back if someone adds you or '
                  'sends a link.',
              'Leave',
              () => _tell(context, a.onLeave?.call()),
            ),
          ),
          if (m.isOwner)
            OrbitListRow(
              icon: OrbitIcons.trash,
              title: 'Delete group',
              danger: true,
              onTap: () => confirm(
                'Delete “$title”?',
                'The group is deleted for everyone and nobody can send to it '
                    'any more. This cannot be undone.',
                'Delete group',
                () => _tell(context, a.onDelete?.call()),
              ),
            ),
        ],
      ),
    ];
  }

  Widget _pending(
    BuildContext context,
    OrbitTokens t,
    PendingMemberItem p,
    void Function(String, String, String, VoidCallback?) confirm,
  ) {
    final text = t.font.style(
      size: OrbitType.small,
      color: t.ink2,
      height: 1.45,
    );
    final name = p.title.replaceFirst('Confirm ', '').replaceFirst('?', '');
    // The 38px buttons take 5px above and below as their touch area (48px),
    // from the card's own spacing, so nothing moves.
    Widget target(Widget button) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: OrbitTapArea(child: button),
    );
    return Container(
      key: ValueKey('pending-${p.account}'),
      margin: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        14,
        OrbitSpace.gutter,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 7),
      decoration: BoxDecoration(
        color: t.warningSoft,
        border: Border.all(color: t.warningLine),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: OrbitIcon(
              OrbitIcons.shieldWarning,
              weight: OrbitIconWeight.fill,
              size: 22,
              color: t.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrbitText(
                  p.title,
                  style: t.font.style(
                    size: OrbitType.small,
                    weight: 640,
                    color: t.ink,
                    height: 1.45,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: OrbitText(p.explanation, style: text),
                ),
                if (!p.canRemove)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OrbitText(
                      'Only an admin can remove someone. If you do not know '
                      'them, you can leave the group.',
                      style: text.copyWith(color: t.ink3),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      target(
                        OrbitButton(
                          label: 'Confirm',
                          height: 38,
                          padding: 16,
                          fontSize: 13,
                          onPressed: () => _tell(
                            context,
                            actions.onConfirmPending?.call(p.account),
                          ),
                        ),
                      ),
                      if (p.canRemove)
                        target(
                          OrbitButton(
                            label: 'Remove',
                            kind: OrbitButtonKind.secondary,
                            height: 38,
                            padding: 16,
                            fontSize: 13,
                            onPressed: () => confirm(
                              'Remove $name?',
                              '$name will be taken out of the group. The group '
                                  'key changes, so they cannot read anything '
                                  'new.',
                              'Remove',
                              () => _tell(
                                context,
                                actions.onRemovePending?.call(p.account),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _member(
    BuildContext context,
    OrbitTokens t,
    GroupMemberView mem,
    void Function(String, String, String, VoidCallback?) confirm,
  ) {
    final a = actions;
    final n = mem.title;
    final parts = [
      if (mem.roleLabel.isNotEmpty) mem.roleLabel,
      if (mem.detail.isNotEmpty) mem.detail,
    ];
    final sub = parts.join(' · ');
    void act(MemberAction x) =>
        _tell(context, a.onMemberAction?.call(mem.account, x));
    final allowed = mem.actions;
    bool may(MemberAction x) => allowed == null || allowed.contains(x);
    return OrbitListRow(
      leading: OrbitAvatar(avatar: mem.avatar, size: 40),
      title: n,
      subWidget: mem.notConfirmed || sub.isNotEmpty
          ? OrbitText.rich(
              TextSpan(
                children: [
                  if (mem.notConfirmed)
                    TextSpan(
                      text: 'Not confirmed',
                      style: TextStyle(color: t.warning),
                    ),
                  if (mem.notConfirmed && sub.isNotEmpty)
                    const TextSpan(text: ' · '),
                  TextSpan(text: sub),
                ],
              ),
              style: t.font.style(
                size: OrbitType.caption,
                color: t.ink3,
                height: 1.35,
              ),
            )
          : null,
      trailing: mem.canAct
          ? OrbitIconButton(
              icon: OrbitIcons.dotsThreeVertical,
              tooltip: 'Actions for $n',
              onPressed: () => showOrbitSheet(
                context,
                title: n,
                items: [
                  if (may(
                    mem.isAdmin
                        ? MemberAction.removeAdmin
                        : MemberAction.makeAdmin,
                  ))
                    OrbitMenuItem(
                      icon: OrbitIcons.shieldStar,
                      label: mem.isAdmin ? 'Remove admin' : 'Make admin',
                      onTap: () => act(
                        mem.isAdmin
                            ? MemberAction.removeAdmin
                            : MemberAction.makeAdmin,
                      ),
                    ),
                  if (model.isOwner && may(MemberAction.makeOwner))
                    OrbitMenuItem(
                      icon: OrbitIcons.crownSimple,
                      label: 'Make owner',
                      onTap: () => showOrbitDialog(
                        context,
                        title: 'Make $n the owner?',
                        text:
                            'They will own the group. You become an admin and '
                            'cannot undo this yourself.',
                        actions: [
                          const OrbitDialogAction('Cancel'),
                          OrbitDialogAction(
                            'Make owner',
                            kind: OrbitButtonKind.primary,
                            onPressed: () => act(MemberAction.makeOwner),
                          ),
                        ],
                      ),
                    ),
                  if (may(MemberAction.remove))
                    OrbitMenuItem(
                      icon: OrbitIcons.userMinus,
                      label: 'Remove from group',
                      danger: true,
                      onTap: () => confirm(
                        'Remove $n?',
                        '$n will be taken out of the group. The group key '
                            'changes, so they cannot read anything new.',
                        'Remove',
                        () => act(MemberAction.remove),
                      ),
                    ),
                  if (may(MemberAction.ban))
                    OrbitMenuItem(
                      icon: OrbitIcons.prohibit,
                      label: 'Remove and ban',
                      danger: true,
                      onTap: () => confirm(
                        'Remove and ban $n?',
                        '$n will be removed and cannot join again through a '
                            'link until you unban them.',
                        'Ban',
                        () => act(MemberAction.ban),
                      ),
                    ),
                ],
              ),
            )
          : null,
    );
  }

  void _edit(BuildContext context) {
    final m = model;
    final name = TextEditingController(text: m.title);
    final about = TextEditingController(text: m.description ?? '');
    showOrbitSheet(
      context,
      title: 'Edit group info',
      body: Builder(
        builder: (sheet) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrbitTextField(
                label: 'Group name',
                controller: name,
                maxLength: 100,
              ),
              OrbitTextField(
                label: 'Description',
                controller: about,
                maxLength: 500,
                rows: 3,
              ),
              OrbitButtonRow(
                top: 4,
                children: [
                  OrbitButton(
                    label: 'Cancel',
                    kind: OrbitButtonKind.secondary,
                    onPressed: () => Navigator.maybePop(sheet),
                  ),
                  OrbitButton(
                    label: 'Save',
                    onPressed: () {
                      Navigator.maybePop(sheet);
                      _tell(
                        context,
                        actions.onSaveInfo?.call(
                          name.text.trim(),
                          about.text.trim(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- group settings

enum GroupWho { admins, everyone }

class GroupSettingsModel {
  const GroupSettingsModel({
    this.canChange = true,
    this.editInfo = GroupWho.admins,
    this.addMembers = GroupWho.everyone,
    this.sendMessages = GroupWho.everyone,
    this.status = GroupInfoStatus.ready,
  });

  final GroupInfoStatus status;
  final bool canChange;
  final GroupWho editInfo;
  final GroupWho addMembers;
  final GroupWho sendMessages;
}

class GroupSettingsActions {
  const GroupSettingsActions({
    this.onEditInfo,
    this.onAddMembers,
    this.onSendMessages,
    this.onRetry,
  });

  final GroupAnswer Function(GroupWho who)? onEditInfo;
  final GroupAnswer Function(GroupWho who)? onAddMembers;
  final GroupAnswer Function(GroupWho who)? onSendMessages;
  final VoidCallback? onRetry;
}

/// `group-settings`: who can edit the group, add people and send.
class GroupSettingsScreen extends StatelessWidget {
  const GroupSettingsScreen({
    super.key,
    required this.model,
    this.actions = const GroupSettingsActions(),
  });

  final GroupSettingsModel model;
  final GroupSettingsActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    String label(GroupWho w) =>
        w == GroupWho.admins ? 'Only admins' : 'Everyone';
    if (m.status != GroupInfoStatus.ready) {
      return OrbitPage(
        title: 'Group settings',
        children: switch (m.status) {
          GroupInfoStatus.loading => const [
            SizedBox(height: 120),
            OrbitPageLoading(),
          ],
          GroupInfoStatus.failed => [
            OrbitLoadFailed(
              title: 'This group could not be loaded.',
              onRetry: actions.onRetry,
            ),
          ],
          _ => const [
            OrbitEmptyState(
              icon: OrbitIcons.usersThree,
              title: 'You are not in this group',
            ),
          ],
        },
      );
    }
    OrbitListRow row(
      String title,
      String sheet,
      GroupWho value,
      GroupAnswer Function(GroupWho who)? set,
    ) => OrbitListRow(
      title: title,
      value: label(value),
      end: m.canChange ? OrbitRowEnd.chevron : OrbitRowEnd.none,
      onTap: m.canChange
          ? () => showOrbitSheet(
              context,
              title: sheet,
              items: [
                for (final w in const [GroupWho.everyone, GroupWho.admins])
                  OrbitMenuItem(
                    icon: w == GroupWho.everyone
                        ? OrbitIcons.usersThree
                        : OrbitIcons.shieldStar,
                    label: label(w),
                    on: w == value,
                    onTap: () {
                      if (w != value) _tell(context, set?.call(w));
                    },
                  ),
              ],
            )
          : null,
    );
    return OrbitPage(
      title: 'Group settings',
      children: [
        if (!m.canChange)
          const OrbitInlineNotice(
            kind: OrbitNoticeKind.info,
            text: 'Only admins can change these settings.',
          ),
        OrbitSection(
          title: 'Members can',
          footer: 'Admins can always do all of these.',
          rows: [
            row(
              'Edit group info',
              'Who can edit group info',
              m.editInfo,
              actions.onEditInfo,
            ),
            row(
              'Add members',
              'Who can add members',
              m.addMembers,
              actions.onAddMembers,
            ),
            row(
              'Send messages',
              'Who can send messages',
              m.sendMessages,
              actions.onSendMessages,
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- invite links

class InviteLinkItem {
  const InviteLinkItem({
    required this.id,
    this.url,
    this.approve = false,
    this.made,
  });

  final String id;

  /// The link to share. Null for a live link made on another device (or
  /// before the app last started): the server keeps only a hash of it, so
  /// the card says when it was made and offers only Revoke.
  final String? url;

  /// New members wait for an admin.
  final bool approve;

  /// When a link without a [url] was made ("today, 14:05"), after "Made".
  final String? made;
}

class InviteLinksModel {
  const InviteLinksModel({
    this.approveNew = false,
    this.links = const [],
    this.loading = false,
    this.creating = false,
    this.error,
  });

  final bool approveNew;
  final List<InviteLinkItem> links;

  /// The live links are still being read: no "links appear here" yet.
  final bool loading;

  /// A link is being made (or revoked): Create spins, Revoke waits.
  final bool creating;

  /// Why the last change did not work (not allowed, offline).
  final String? error;
}

class InviteLinksActions {
  const InviteLinksActions({
    this.onSetApprove,
    this.onCreate,
    this.onShare,
    this.onCopy,
    this.onRevoke,
  });

  final ValueChanged<bool>? onSetApprove;
  final VoidCallback? onCreate;
  final ValueChanged<String>? onShare;

  /// Copies the link; the page says "Link copied.".
  final Future<void> Function(String linkId)? onCopy;
  final ValueChanged<String>? onRevoke;
}

/// `group-invite`: whether links need approval, Create link, and a card per
/// link with Share, Copy and Revoke (only Revoke for a link without its URL).
class InviteLinksScreen extends StatelessWidget {
  const InviteLinksScreen({
    super.key,
    required this.model,
    this.actions = const InviteLinksActions(),
  });

  final InviteLinksModel model;
  final InviteLinksActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    return OrbitPage(
      title: 'Invite with a link',
      children: [
        const OrbitPageIntro(
          text:
              'Anyone with a link can ask to join this group. Share it only '
              'with people you want in.',
        ),
        OrbitSection(
          rows: [
            OrbitListRow(
              title: 'Admins approve new members',
              sub: m.approveNew
                  ? 'People who use the link wait for an admin to let them in.'
                  : 'People who use the link join straight away.',
              end: OrbitRowEnd.toggle,
              on: m.approveNew,
              onChanged: a.onSetApprove,
            ),
          ],
        ),
        OrbitButtonRow(
          children: [
            OrbitButton(
              label: 'Create link',
              icon: OrbitIcons.linkSimpleHorizontal,
              busy: m.creating,
              block: true,
              onPressed: m.creating ? null : (a.onCreate ?? _none),
            ),
          ],
        ),
        if (m.error != null)
          OrbitInlineNotice(kind: OrbitNoticeKind.error, text: m.error!),
        if (m.links.isEmpty && !m.loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: OrbitText(
              'Links you make appear here so you can share or revoke them.',
              textAlign: TextAlign.center,
              style: t.font.style(
                size: OrbitType.caption,
                color: t.ink3,
                height: 1.5,
              ),
            ),
          ),
        for (final l in m.links) _card(context, t, l),
      ],
    );
  }

  /// `.linkc`: the link's kind, the URL in a mono well, and its buttons. A
  /// link without its URL says when it was made instead, and can only be
  /// revoked.
  Widget _card(BuildContext context, OrbitTokens t, InviteLinkItem l) {
    final a = actions;
    final url = l.url;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        10,
        OrbitSpace.gutter,
        0,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(t.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OrbitIcon(
                l.approve ? OrbitIcons.shieldCheck : OrbitIcons.lightning,
                weight: OrbitIconWeight.fill,
                size: 18,
                color: t.accent,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: OrbitText(
                  l.approve
                      ? 'Admins approve new members'
                      : 'Joins straight away',
                  style: t.font.style(size: 13, weight: 600, color: t.ink2),
                ),
              ),
            ],
          ),
          if (url == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: OrbitText(
                '${l.made == null ? '' : 'Made ${l.made}. '}'
                'It cannot be shown again, but it can be revoked.',
                style: t.font.style(
                  size: OrbitType.caption,
                  color: t.ink3,
                  height: 1.5,
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.field,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                url,
                style: t.mono.style(size: 12, color: t.ink, height: 1.4),
              ),
            ),
          // `.lk-actions`: one row, 8px apart; it wraps rather than
          // overflowing when the text is large.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (url != null) ...[
                OrbitButton(
                  label: 'Share',
                  icon: OrbitIcons.shareNetwork,
                  height: 40,
                  padding: 14,
                  fontSize: 13,
                  onPressed: () => a.onShare?.call(l.id),
                ),
                OrbitButton(
                  label: 'Copy',
                  icon: OrbitIcons.copy,
                  kind: OrbitButtonKind.secondary,
                  height: 40,
                  padding: 14,
                  fontSize: 13,
                  onPressed: () async {
                    final copy = a.onCopy;
                    if (copy == null) return;
                    await copy(l.id);
                    if (context.mounted) {
                      showOrbitToast(context, 'Link copied.');
                    }
                  },
                ),
              ],
              OrbitButton(
                label: 'Revoke',
                kind: OrbitButtonKind.ghost,
                tint: t.danger,
                height: 40,
                padding: 14,
                fontSize: 13,
                onPressed: model.creating
                    ? null
                    : () => showOrbitDialog(
                        context,
                        title: 'Revoke this link?',
                        text:
                            'It stops working at once. People who already joined '
                            'stay in the group.',
                        actions: [
                          const OrbitDialogAction('Cancel'),
                          OrbitDialogAction(
                            'Revoke',
                            kind: OrbitButtonKind.danger,
                            onPressed: () => a.onRevoke?.call(l.id),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------- join requests and banned

/// One person waiting to join, or banned.
class PersonEntryView {
  const PersonEntryView({
    required this.account,
    required this.title,
    required this.whenLabel,
    required this.avatar,
  });

  final String account;
  final String title;

  /// "Asked today at 09:02" / "Banned 2 October".
  final String whenLabel;
  final HelixAvatarModel avatar;
}

class JoinRequestsModel {
  const JoinRequestsModel({
    this.requests = const [],
    this.loading = false,
    this.loadFailed = false,
  });

  final List<PersonEntryView> requests;
  final bool loading;
  final bool loadFailed;
}

class JoinRequestsActions {
  const JoinRequestsActions({this.onApprove, this.onReject, this.onRetry});

  /// Each answers with the sentence to show ("Sadia joined the group.").
  final GroupAnswer Function(String account)? onApprove;
  final GroupAnswer Function(String account)? onReject;
  final VoidCallback? onRetry;
}

/// `group-requests`: people asking to join, each with Reject and Approve.
class JoinRequestsScreen extends StatelessWidget {
  const JoinRequestsScreen({
    super.key,
    required this.model,
    this.actions = const JoinRequestsActions(),
  });

  final JoinRequestsModel model;
  final JoinRequestsActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    if (m.loading || m.loadFailed) {
      return OrbitPage(
        title: 'Join requests',
        children: [
          if (m.loading) ...[
            const SizedBox(height: 120),
            const OrbitPageLoading(),
          ] else
            OrbitLoadFailed(
              title:
                  'The requests could not be loaded. Only admins can see '
                  'them.',
              onRetry: actions.onRetry,
            ),
        ],
      );
    }
    if (m.requests.isEmpty) {
      return const OrbitPage(
        title: 'Join requests',
        children: [
          OrbitEmptyState(
            icon: OrbitIcons.userCirclePlus,
            title: 'No one is waiting',
            text:
                'When someone uses an approval link, they show up here for '
                'you to let in.',
          ),
        ],
      );
    }
    return OrbitPage(
      title: 'Join requests',
      children: [
        const SizedBox(height: 12),
        OrbitCard(
          children: [
            for (final r in m.requests)
              OrbitListRow(
                leading: OrbitAvatar(avatar: r.avatar, size: 40),
                title: r.title,
                sub: r.whenLabel,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrbitIconButton(
                      icon: OrbitIcons.x,
                      tooltip: 'Reject ${r.title}',
                      tone: OrbitIconButtonTone.danger,
                      onPressed: () =>
                          _tell(context, actions.onReject?.call(r.account)),
                    ),
                    OrbitIconButton(
                      icon: OrbitIcons.check,
                      weight: OrbitIconWeight.bold,
                      tooltip: 'Approve ${r.title}',
                      tone: OrbitIconButtonTone.accent,
                      onPressed: () =>
                          _tell(context, actions.onApprove?.call(r.account)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class BannedPeopleModel {
  const BannedPeopleModel({
    this.people = const [],
    this.loading = false,
    this.loadFailed = false,
  });

  final List<PersonEntryView> people;
  final bool loading;
  final bool loadFailed;
}

class BannedPeopleActions {
  const BannedPeopleActions({this.onUnban, this.onRetry});

  /// Answers with the sentence to show ("Shuvo can join again.").
  final GroupAnswer Function(String account)? onUnban;
  final VoidCallback? onRetry;
}

/// `group-banned`: people banned from this phone, each with Unban.
class BannedPeopleScreen extends StatelessWidget {
  const BannedPeopleScreen({
    super.key,
    required this.model,
    this.actions = const BannedPeopleActions(),
  });

  final BannedPeopleModel model;
  final BannedPeopleActions actions;

  @override
  Widget build(BuildContext context) {
    final m = model;
    if (m.loading || m.loadFailed) {
      return OrbitPage(
        title: 'Banned people',
        children: [
          if (m.loading) ...[
            const SizedBox(height: 120),
            const OrbitPageLoading(),
          ] else
            OrbitLoadFailed(
              title: 'The list could not be loaded.',
              onRetry: actions.onRetry,
            ),
        ],
      );
    }
    if (m.people.isEmpty) {
      return const OrbitPage(
        title: 'Banned people',
        children: [
          OrbitEmptyState(
            icon: OrbitIcons.prohibit,
            title: 'No one is banned',
            text:
                'People you remove and ban from this phone are listed here. '
                'Bans made on another device are not shown.',
          ),
        ],
      );
    }
    return OrbitPage(
      title: 'Banned people',
      children: [
        const OrbitPageIntro(
          text:
              'Banned people cannot join through a link. Bans made on other '
              'devices are not listed here.',
        ),
        const SizedBox(height: 10),
        OrbitCard(
          children: [
            for (final p in m.people)
              OrbitListRow(
                leading: OrbitAvatar(avatar: p.avatar, size: 40),
                title: p.title,
                sub: p.whenLabel,
                trailing: OrbitButton(
                  label: 'Unban',
                  kind: OrbitButtonKind.ghost,
                  onPressed: () =>
                      _tell(context, actions.onUnban?.call(p.account)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- add members

class AddMembersModel {
  const AddMembersModel({
    this.picker = const MemberPickerModel(),
    this.adding = false,
  });

  final MemberPickerModel picker;
  final bool adding;
}

class AddMembersActions {
  const AddMembersActions({
    this.picker = const MemberPickerActions(),
    this.onAdd,
  });

  final MemberPickerActions picker;

  /// Adds the people picked. Ok: its sentence ("Added 2 people.") and back;
  /// not ok: "No one was added", and why.
  final Future<({bool ok, String? message})> Function()? onAdd;
}

/// `group-add`: the member picker without the people already in, and Add N.
class AddMembersScreen extends StatelessWidget {
  const AddMembersScreen({
    super.key,
    required this.model,
    this.actions = const AddMembersActions(),
  });

  final AddMembersModel model;
  final AddMembersActions actions;

  Future<void> _add(BuildContext context) async {
    final add = actions.onAdd;
    if (add == null || model.adding) return;
    final result = await add();
    if (!context.mounted) return;
    final message = result.message;
    if (result.ok) {
      if (message != null) showOrbitToast(context, message);
      await Navigator.maybePop(context);
      return;
    }
    // Nobody was added: stay, say why, and let the person choose again.
    if (message != null) {
      await showOrbitDialog(
        context,
        title: 'No one was added',
        text: message,
        actions: const [OrbitDialogAction('OK', kind: OrbitButtonKind.primary)],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = model.picker.selected.length;
    return _Frame(
      title: 'Add members',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [MemberPicker(model: model.picker, actions: actions.picker)],
      ),
      fab: n == 0
          ? null
          : OrbitExtendedFab(
              icon: OrbitIcons.userPlus,
              label: 'Add $n',
              busy: model.adding,
              onPressed: () => _add(context),
            ),
    );
  }
}

// ------------------------------------------------------------ join a group

enum JoinStage { input, loading, preview, joining, joined, pending, failed }

class JoinGroupModel {
  const JoinGroupModel({
    this.stage = JoinStage.input,
    this.initialLink = '',
    this.previewName = '',
    this.previewMemberCount = 0,
    this.previewDescription,
    this.previewAvatar = const HelixAvatarModel(name: 'Group', isGroup: true),
    this.requiresApproval = false,
    this.alreadyMember = false,
    this.error,
  });

  final JoinStage stage;
  final String initialLink;

  /// Empty when the link did not open the name.
  final String previewName;
  final int previewMemberCount;
  final String? previewDescription;
  final HelixAvatarModel previewAvatar;
  final bool requiresApproval;
  final bool alreadyMember;
  final String? error;
}

class JoinGroupActions {
  const JoinGroupActions({
    this.onContinue,
    this.linkLooksRight,
    this.onPaste,
    this.onJoin,
    this.onOpenGroup,
    this.onRetry,
    this.onCancel,
  });

  final ValueChanged<String>? onContinue;

  /// Whether the text is a group link at all; a wrong one stays on the
  /// field with a toast. Null takes every text.
  final bool Function(String link)? linkLooksRight;

  /// Null pastes the clipboard into the field.
  final VoidCallback? onPaste;
  final VoidCallback? onJoin;
  final VoidCallback? onOpenGroup;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
}

/// `group-join`: paste a group link, see the group, and join it (or ask to).
class JoinGroupScreen extends StatelessWidget {
  const JoinGroupScreen({
    super.key,
    required this.model,
    this.actions = const JoinGroupActions(),
  });

  final JoinGroupModel model;
  final JoinGroupActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final cancel = a.onCancel ?? () => Navigator.maybePop(context);
    final name = m.previewName.isEmpty ? 'Group' : m.previewName;
    // `.center-page` with a 34px `--accent` spinner and one line.
    Widget spinner(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitSpinner(size: 34, color: t.accent),
          const SizedBox(height: 10),
          OrbitText(
            text,
            style: t.font.style(
              size: OrbitType.small,
              color: t.ink3,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
    final List<Widget> body;
    switch (m.stage) {
      case JoinStage.input:
        body = [_JoinInput(link: m.initialLink, actions: a)];
      case JoinStage.loading:
        body = [spinner('Opening the link…')];
      case JoinStage.joining:
        body = [spinner('Joining…')];
      case JoinStage.preview:
        final missing = m.previewName.isEmpty;
        body = [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OrbitProfileHero(
              avatar: missing
                  ? const HelixAvatarModel(name: '?', colorIndex: 7)
                  : m.previewAvatar,
              size: 112,
              name: missing ? 'A group on Orbit' : m.previewName,
              sub: missing ? '' : '${m.previewMemberCount} members',
              about: missing
                  ? 'This link did not open the group’s name. It may be cut '
                        'off; you can still ask to join.'
                  : m.previewDescription ?? '',
            ),
          ),
          if (m.alreadyMember)
            const OrbitInlineNotice(
              kind: OrbitNoticeKind.info,
              text: 'You are already in this group.',
            )
          else if (m.requiresApproval)
            const OrbitInlineNotice(
              kind: OrbitNoticeKind.info,
              text: 'An admin has to approve you before you are in.',
            ),
          OrbitButtonRow(
            column: true,
            children: [
              if (m.alreadyMember)
                OrbitButton(
                  label: 'Open group',
                  block: true,
                  onPressed: a.onOpenGroup ?? _none,
                )
              else
                OrbitButton(
                  label: m.requiresApproval ? 'Ask to join' : 'Join group',
                  block: true,
                  onPressed: a.onJoin ?? _none,
                ),
              OrbitButton(
                label: 'Cancel',
                kind: OrbitButtonKind.secondary,
                block: true,
                onPressed: cancel,
              ),
            ],
          ),
        ];
      case JoinStage.joined:
        body = [
          OrbitCenterPage(
            icon: OrbitIcons.checkCircle,
            iconColor: t.success,
            iconBackground: t.successSoft,
            title: 'You joined “$name”',
            text: 'You are in the group now.',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OrbitButton(
                  label: 'Open group',
                  onPressed: a.onOpenGroup ?? _none,
                ),
              ),
            ],
          ),
        ];
      case JoinStage.pending:
        body = [
          OrbitCenterPage(
            icon: OrbitIcons.hourglassMedium,
            iconColor: t.accent,
            iconBackground: t.accentSoft,
            title: 'Request sent',
            text:
                'An admin of “$name” has to approve you. You will see the '
                'group when they do.',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OrbitButton(label: 'Done', onPressed: cancel),
              ),
            ],
          ),
        ];
      case JoinStage.failed:
        body = [
          OrbitCenterPage(
            icon: OrbitIcons.linkBreak,
            iconColor: t.danger,
            iconBackground: t.dangerSoft,
            title: 'Something went wrong',
            text: m.error ?? 'This invite link has expired. Ask for a new one.',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OrbitButton(
                  label: 'Retry',
                  kind: OrbitButtonKind.secondary,
                  onPressed: a.onRetry ?? _none,
                ),
              ),
            ],
          ),
        ];
    }
    // `Kit.page`'s scroll does not stretch `.center-page`, so these sit at
    // the top of the page.
    return OrbitPage(title: 'Join a group', onBack: cancel, children: body);
  }
}

class _JoinInput extends StatefulWidget {
  const _JoinInput({required this.link, required this.actions});

  final String link;
  final JoinGroupActions actions;

  @override
  State<_JoinInput> createState() => _JoinInputState();
}

class _JoinInputState extends State<_JoinInput> {
  late final _link = TextEditingController(text: widget.link);

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) {
      setState(() => _link.text = text);
    }
  }

  void _continue() {
    final text = _link.text.trim();
    final looks = widget.actions.linkLooksRight;
    if (looks != null && !looks(text)) {
      showOrbitToast(
        context,
        'That is not an Orbit group link. Check that you copied all of it.',
      );
      return;
    }
    widget.actions.onContinue?.call(text);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const OrbitPageIntro(
        text:
            'Paste the group link you were sent. It starts with https:// or '
            'helix:// and ends with HLX-GRP-…',
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          OrbitSpace.gutter,
          14,
          OrbitSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitTextField(
              label: 'Group link',
              controller: _link,
              hint: 'https://…/open#HLX-GRP-…',
              mono: true,
              onPaste: widget.actions.onPaste ?? _paste,
            ),
            OrbitButton(label: 'Continue', block: true, onPressed: _continue),
          ],
        ),
      ),
    ],
  );
}
