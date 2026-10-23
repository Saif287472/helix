import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/screens/home/home_models.dart' show ListStatus;
import 'package:orbit_ui/src/screens/you/theme_packs_screen.dart'
    show ThemePackPlace;
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The id that names no pack: the phone's own ringtone, which is what a call
/// rings with until a person chooses a downloaded pack.
///
/// It is an empty string rather than a slug because the device setting that
/// holds the choice holds *nothing* for it: the phone's ringtone is not
/// something this app downloaded, signed or could delete.
const phoneRingtoneId = '';

/// The words this app uses for the phone's own ringtone. The Ringtones page's
/// first row and the Notifications row that opens it both read them from here,
/// so the two can never say different things about the same choice.
const phoneRingtoneLabel = 'Phone’s ringtone';

/// One ringtone on the page. A sound pack carries no display name - its one
/// file is the pack, and only a theme document has words - so a downloaded one
/// is named by its id, which is the publisher's own signed slug, not a name the
/// server made up in a list.
class RingtoneGalleryItem {
  const RingtoneGalleryItem({
    required this.id,
    required this.name,
    this.place = ThemePackPlace.onTheServer,
    this.detail = '',
    this.phone = false,
    this.inUse = false,
    this.updateAvailable = false,
    this.busy = false,
  });

  /// What the app calls it: [phoneRingtoneId], or a pack's id.
  final String id;

  final String name;

  final ThemePackPlace place;

  /// The line under the name, already in the app's own words and units.
  final String detail;

  /// The phone's own ringtone: this device has it whatever else it has, so it
  /// is never downloaded, never updated and never deleted.
  final bool phone;

  /// What a call rings with right now.
  final bool inUse;

  /// This device holds it, and the server lists a newer revision.
  final bool updateAvailable;

  /// An action for this ringtone is running, so the row waits.
  final bool busy;
}

/// The ringtones this device can ring with, and the ones its server offers.
class RingtoneGalleryModel {
  const RingtoneGalleryModel({
    this.ringtones = const [],
    this.status = ListStatus.ready,
    this.host = '',
    this.error = '',
    this.emptyNote = '',
  });

  /// Every row, in the order the page reads them. The page puts the ones on
  /// this phone first, and [phoneRingtoneId] above all of them.
  final List<RingtoneGalleryItem> ringtones;

  /// Whether the server's list came in.
  final ListStatus status;

  /// Whose server it is; the group title reads "On …" with this in place.
  final String host;

  /// What to say when the list did not come in.
  final String error;

  /// What to say when it came in and listed no sound this app can ring with.
  final String emptyNote;
}

/// The page's verbs, each handing back the sentence to toast (null says
/// nothing). [RingtoneGalleryActions.onUse] takes [phoneRingtoneId] for the
/// phone's own ringtone.
class RingtoneGalleryActions {
  const RingtoneGalleryActions({
    this.onUse,
    this.onGet,
    this.onUpdate,
    this.onDelete,
    this.onRetry,
  });

  /// Rings incoming calls with this from now on.
  final Future<String?> Function(String id)? onUse;

  final Future<String?> Function(String id)? onGet;

  final Future<String?> Function(String id)? onUpdate;

  final Future<String?> Function(String id)? onDelete;

  final VoidCallback? onRetry;
}

/// `Ringtones` (Settings > Notifications > Ringtone): what this phone can ring
/// with, and what its server will hand over. Built in `orbit/PORT_PLAN.md` Part
/// C step 5 from that plan's words, because the prototype has no such screen -
/// its Notifications row opens a two-choice sheet that ends at "More ringtones
/// to download are coming."
///
/// A sound is played by the phone, not by Orbit: it is the sound of the
/// notification channel a call arrives on, which is why there is one row per
/// ringtone and why choosing one takes effect on the next call rather than at
/// once here.
class RingtoneGalleryScreen extends StatelessWidget {
  const RingtoneGalleryScreen({
    super.key,
    required this.model,
    this.actions = const RingtoneGalleryActions(),
  });

  final RingtoneGalleryModel model;
  final RingtoneGalleryActions actions;

  Future<void> _run(
    BuildContext context,
    Future<String?> Function(String id)? action,
    RingtoneGalleryItem item,
  ) async {
    if (action == null) return;
    final said = await action(item.id);
    if (said != null && context.mounted) showOrbitToast(context, said);
  }

  @override
  Widget build(BuildContext context) {
    final onPhone = [
      for (final item in model.ringtones)
        if (item.place == ThemePackPlace.onThisPhone) item,
    ];
    final onServer = [
      for (final item in model.ringtones)
        if (item.place == ThemePackPlace.onTheServer) item,
    ];

    return OrbitYouPage(
      title: 'Ringtones',
      children: [
        const OrbitGroupTitle('On this phone'),
        OrbitCard(
          dividerIndent: 14,
          children: [for (final item in onPhone) _row(context, item)],
        ),
        if (onPhone.length > 1)
          const OrbitSectionFoot(
            'A downloaded ringtone is a signed pack: the publisher’s signature, '
            'the size of the file and its own hash. One that fails a check is '
            'never played, and the phone’s own ringtone is always there.',
          ),
        OrbitGroupTitle(
          model.host.isEmpty ? 'On the server' : 'On ${model.host}',
        ),
        ...switch (model.status) {
          ListStatus.loading => const [
            SizedBox(height: 16),
            OrbitPageLoading(label: 'Checking what is on offer'),
            SizedBox(height: 16),
          ],
          ListStatus.failed => [
            OrbitLoadFailed(
              title: model.error.isEmpty
                  ? 'The ringtones on offer could not be read.'
                  : model.error,
              onRetry: actions.onRetry,
              compact: true,
            ),
          ],
          ListStatus.ready =>
            onServer.isEmpty
                ? [
                    OrbitSectionFoot(
                      model.emptyNote.isEmpty
                          ? 'Nothing is on offer here yet. The sounds a '
                                'server publishes appear on this page.'
                          : model.emptyNote,
                      top: 2,
                    ),
                  ]
                : [
                    OrbitCard(
                      dividerIndent: 14,
                      children: [
                        for (final item in onServer) _row(context, item),
                      ],
                    ),
                  ],
        },
        const OrbitSectionFoot(
          'A ringtone you download stays on this phone when the account signs '
          'out, and getting it back costs nothing.',
        ),
      ],
    );
  }

  Widget _row(BuildContext context, RingtoneGalleryItem item) {
    final t = OrbitTokens.of(context);
    final use =
        item.place == ThemePackPlace.onThisPhone && !item.inUse && !item.busy
        ? () => _run(context, actions.onUse, item)
        : null;
    return OrbitListRow(
      icon: OrbitIcons.musicNote,
      title: item.name,
      sub: item.detail,
      subMono: item.place == ThemePackPlace.onTheServer,
      value: item.inUse ? 'In use' : '',
      onTap: use,
      trailing: switch (item) {
        _ when item.busy => OrbitSpinner(size: 18, color: t.ink3),
        RingtoneGalleryItem(place: ThemePackPlace.onTheServer) => OrbitButton(
          label: 'Get',
          kind: OrbitButtonKind.secondary,
          height: 38,
          onPressed: item.busy
              ? null
              : () => _run(context, actions.onGet, item),
        ),
        _ when item.updateAvailable => OrbitButton(
          label: 'Update',
          kind: OrbitButtonKind.secondary,
          height: 38,
          onPressed: () => _run(context, actions.onUpdate, item),
        ),
        _ when item.phone => null,
        _ => OrbitIconButton(
          icon: OrbitIcons.trashSimple,
          tooltip: 'Delete ${item.name}',
          tone: OrbitIconButtonTone.danger,
          onPressed: () => _run(context, actions.onDelete, item),
        ),
      },
    );
  }
}
