import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/screens/kit_sheet.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `state-kit` (`prototype/js/screens/states.js`): every shared state drawn
/// once, as the prototype's sheet draws them.
class KitStateScreen extends StatefulWidget {
  const KitStateScreen({super.key});

  @override
  State<KitStateScreen> createState() => _KitStateScreenState();
}

class _KitStateScreenState extends State<KitStateScreen> {
  var _retrying = false;

  void _retry() {
    setState(() => _retrying = true);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _retrying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget frame(Widget child) =>
        OrbitKitFrame(padding: EdgeInsets.zero, background: t.bg, child: child);
    Widget buttons(List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        4,
        OrbitSpace.gutter,
        0,
      ),
      child: Row(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: c),
          ],
        ],
      ),
    );
    return OrbitKitPage(
      title: 'State kit',
      intro:
          'How every screen draws loading, failure, empty lists, permissions '
          'and refusals. Screens use these instead of their own.',
      children: [
        const OrbitKitLabel('A list is loading'),
        frame(const OrbitSkeleton(count: 3, label: 'Loading chats')),
        const OrbitKitLabel('Rows and tiles are loading'),
        frame(
          const Column(
            children: [
              OrbitSkeleton(count: 2, kind: OrbitSkeletonKind.row),
              OrbitSkeleton(count: 1, kind: OrbitSkeletonKind.tile),
            ],
          ),
        ),
        const OrbitKitLabel('A page is opening'),
        frame(const OrbitPageLoading(label: 'Opening the conversation…')),
        const OrbitKitLabel('A page could not load'),
        frame(
          _retrying
              ? const OrbitSkeleton(count: 2)
              : OrbitLoadFailed(
                  title: 'Your chats could not be loaded.',
                  onRetry: _retry,
                ),
        ),
        const OrbitKitLabel('A list inside a page could not load'),
        OrbitCard(
          dividers: false,
          children: [
            OrbitLoadFailed(
              title: 'Muted chats could not be loaded.',
              sub: '',
              compact: true,
              onRetry: _retry,
            ),
          ],
        ),
        const OrbitKitLabel('Nothing here yet'),
        frame(
          const OrbitEmptyState(
            icon: OrbitIcons.chatsCircle,
            title: 'No chats yet',
            text: 'Search for a name or a number to start a conversation.',
          ),
        ),
        const OrbitKitLabel('Asking for a permission'),
        OrbitPermissionCard(
          kind: OrbitPermission.contacts,
          text:
              'To show which of your contacts use Orbit. Only scrambled '
              'numbers are checked; your contacts never leave this device.',
          onPressed: () =>
              showOrbitToast(context, 'Opens the system permission prompt'),
        ),
        const OrbitKitLabel('After a refusal'),
        OrbitPermissionCard(
          kind: OrbitPermission.camera,
          denied: true,
          text:
              'Allow camera access in your phone’s settings to take photos '
              'and scan codes.',
          onPressed: () =>
              showOrbitToast(context, 'Opens the system settings for Orbit'),
        ),
        const OrbitKitLabel('A field refusal and a lockout'),
        const OrbitCard(
          dividers: false,
          padding: EdgeInsets.fromLTRB(14, 14, 14, 2),
          children: [
            OrbitTextField(
              label: 'Current password',
              initialValue: 'secret',
              obscure: true,
              error: 'That is not your current password.',
            ),
            OrbitFieldLock('Too many tries. Try again in 15 minutes.'),
          ],
        ),
        const OrbitKitLabel('A notice on the page'),
        const OrbitInlineNotice(
          kind: OrbitNoticeKind.error,
          text: 'That was not saved. Check your connection and try again.',
        ),
        const OrbitInlineNotice(
          kind: OrbitNoticeKind.info,
          text:
              'Saved on this device. Your phone did not let Orbit change your '
              'contacts.',
        ),
        const OrbitKitLabel('Toasts'),
        buttons([
          OrbitButton(
            label: 'Toast',
            kind: OrbitButtonKind.secondary,
            block: true,
            onPressed: () => showOrbitToast(context, 'Chat muted for 8 hours'),
          ),
          OrbitButton(
            label: 'Error toast',
            kind: OrbitButtonKind.secondary,
            block: true,
            onPressed: () => showOrbitToast(
              context,
              'The message could not be sent. Check your connection.',
              error: true,
            ),
          ),
          OrbitButton(
            label: 'With Undo',
            kind: OrbitButtonKind.secondary,
            block: true,
            onPressed: () => showOrbitToast(
              context,
              'Chat archived',
              actionLabel: 'Undo',
              onAction: () {},
            ),
          ),
        ]),
        const OrbitKitLabel('A button at work'),
        buttons([
          OrbitButton(
            label: 'Sending',
            busy: true,
            block: true,
            onPressed: () {},
          ),
          const OrbitButton(
            label: 'Not ready',
            kind: OrbitButtonKind.secondary,
            block: true,
            onPressed: null,
          ),
        ]),
        const OrbitSectionFoot(
          'Placeholder rows shimmer unless the system asks to reduce motion.',
          top: 18,
        ),
      ],
    );
  }
}

/// The overlays `kit-overlays` opens (`OVERLAYS` in
/// `prototype/js/screens/states.js`), each as a screen opens it.
enum KitOverlay {
  sheet('A sheet with a choice'),
  actions('A sheet of actions'),
  menu('A menu'),
  dialog('A dialog'),
  input('A dialog with a field'),
  toast('A toast'),
  toastError('An error toast'),
  toastUndo('A toast with Undo');

  const KitOverlay(this.label);

  final String label;

  /// The prototype's key for this overlay's entry.
  String get key => switch (this) {
    toastError => 'kit-overlays-toast-error',
    toastUndo => 'kit-overlays-toast-undo',
    _ => 'kit-overlays-$name',
  };

  void open(BuildContext context, {bool stay = false}) => switch (this) {
    sheet => showOrbitSheet(
      context,
      title: 'Disappearing messages',
      text:
          'New messages in this group disappear after this long, for '
          'everyone.',
      items: [
        for (final o in const ['Off', '24 hours', '7 days', '90 days'])
          OrbitMenuItem(icon: OrbitIcons.timer, label: o, on: o == 'Off'),
      ],
    ),
    actions => showOrbitSheet(
      context,
      title: 'Nadia Rahman',
      items: const [
        OrbitMenuItem(icon: OrbitIcons.phone, label: 'Voice call'),
        OrbitMenuItem(icon: OrbitIcons.videoCamera, label: 'Video call'),
        OrbitMenuItem(
          icon: OrbitIcons.trash,
          label: 'Delete from call history',
          danger: true,
        ),
      ],
    ),
    menu => showOrbitMenu(context, const [
      OrbitMenuItem(icon: OrbitIcons.usersThree, label: 'New group'),
      OrbitMenuItem(
        icon: OrbitIcons.linkSimple,
        label: 'Join a group with a link',
      ),
      OrbitMenuItem.divider,
      OrbitMenuItem(icon: OrbitIcons.archive, label: 'Archived chats (3)'),
    ]),
    dialog => showOrbitDialog(
      context,
      title: 'Delete this chat?',
      text:
          'The messages are removed from this device. People you chatted '
          'with keep their copies.',
      actions: const [
        OrbitDialogAction('Cancel'),
        OrbitDialogAction('Delete', kind: OrbitButtonKind.danger),
      ],
    ),
    input => showOrbitInputDialog(
      context,
      title: 'Rename',
      label: 'Name',
      value: 'Nadia Rahman',
    ),
    toast => showOrbitToast(context, 'Chat muted for 8 hours', stay: stay),
    toastError => showOrbitToast(
      context,
      'The message could not be sent. Check your connection.',
      error: true,
      stay: stay,
    ),
    toastUndo => showOrbitToast(
      context,
      'Chat archived',
      actionLabel: 'Undo',
      onAction: () {},
      stay: stay,
    ),
  };
}

/// `kit-overlays`: a page of buttons, each opening one overlay; [open]
/// opens one as the page appears (the prototype's `kit-overlays-*` keys).
class KitOverlaysScreen extends StatefulWidget {
  const KitOverlaysScreen({super.key, this.open});

  final KitOverlay? open;

  @override
  State<KitOverlaysScreen> createState() => _KitOverlaysScreenState();
}

class _KitOverlaysScreenState extends State<KitOverlaysScreen> {
  @override
  void initState() {
    super.initState();
    final open = widget.open;
    if (open != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) open.open(context, stay: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) => OrbitKitPage(
    title: 'Overlays',
    intro:
        'Sheets, menus, dialogs and toasts, each opened as a screen opens it.',
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          OrbitSpace.gutter,
          16,
          OrbitSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, o) in KitOverlay.values.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              OrbitButton(
                label: o.label,
                kind: OrbitButtonKind.secondary,
                block: true,
                onPressed: () => o.open(context),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
