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
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// Where a theme in the gallery is right now (`orbit/PORT_PLAN.md` Part C
/// step 4).
enum ThemePackPlace {
  /// This device can draw with it: it is built in, or a pack that passed its
  /// checks when it was read from the pack folder.
  onThisPhone,

  /// The account's server lists it, and this device has no copy that passes.
  onTheServer,
}

/// One theme on the page. Only a theme that is `onThisPhone` can carry a name
/// or a detail of its own: a pack that has not been downloaded has nothing but
/// the id the server listed, because a name in the list would be unsigned while
/// the one a device shows comes from the signed theme document.
class ThemePackItem {
  const ThemePackItem({
    required this.id,
    required this.name,
    this.place = ThemePackPlace.onTheServer,
    this.detail = '',
    this.builtIn = false,
    this.inUse = false,
    this.updateAvailable = false,
    this.busy = false,
  });

  /// What the app calls this theme: a built-in id, or a pack's.
  final String id;

  /// The name a person reads. The theme's own words when it is on this phone,
  /// the server's id when it is not.
  final String name;

  final ThemePackPlace place;

  /// The line under the name, already in the words and units the app wants
  /// ("Aesthetic · light · 2.0 MB").
  final String detail;

  /// Built into the app, so there is nothing to download and nothing to delete.
  final bool builtIn;

  /// The theme the app is drawing with.
  final bool inUse;

  /// This device holds it, and the server has a newer revision of it.
  final bool updateAvailable;

  /// An action for this theme is running, so the row waits.
  final bool busy;
}

/// The themes on this device, and the ones this account's server offers.
class ThemeGalleryModel {
  const ThemeGalleryModel({
    this.themes = const [],
    this.status = ListStatus.ready,
    this.host = '',
    this.error = '',
    this.emptyNote = '',
  });

  /// Every theme, in the order the app wants them read. The page puts the ones
  /// on this phone first.
  final List<ThemePackItem> themes;

  /// Whether the server's list came in.
  final ListStatus status;

  /// Whose server it is ("Orbit Global", or a personal server's name); the
  /// group title reads "On …" with this in place of the ellipsis.
  final String host;

  /// What to say when the list did not come in.
  final String error;

  /// What to say when it came in and offered nothing this app could use. The
  /// page's own words say "nothing is on offer", which is the wrong sentence
  /// for a server that lists packs nobody signed - so the app puts the right
  /// one here.
  final String emptyNote;
}

/// The page's verbs. Each one hands back the sentence the app wants shown, and
/// the page toasts it; null means "nothing to say", so a row that was already
/// in place does not repeat itself.
class ThemeGalleryActions {
  const ThemeGalleryActions({
    this.onUse,
    this.onGet,
    this.onUpdate,
    this.onDelete,
    this.onRetry,
  });

  /// Draws the app in this theme from now on.
  final Future<String?> Function(String id)? onUse;

  /// Downloads it, and offers its theme to the app.
  final Future<String?> Function(String id)? onGet;

  /// Downloads the newest revision the server lists.
  final Future<String?> Function(String id)? onUpdate;

  /// Deletes it and the bytes it downloaded.
  final Future<String?> Function(String id)? onDelete;

  /// Asks the server again.
  final VoidCallback? onRetry;
}

/// `More themes` (You > Appearance): what this device can draw with, and what
/// this account's server will hand over. Built in `orbit/PORT_PLAN.md` Part C
/// step 4 from that plan's words - download, delete, "get more" - because the
/// prototype has no such screen: its Appearance page ends in "More themes are
/// on the way."
class ThemeGalleryScreen extends StatelessWidget {
  const ThemeGalleryScreen({
    super.key,
    required this.model,
    this.actions = const ThemeGalleryActions(),
  });

  final ThemeGalleryModel model;
  final ThemeGalleryActions actions;

  Future<void> _run(
    BuildContext context,
    Future<String?> Function(String id)? action,
    ThemePackItem item,
  ) async {
    if (action == null) return;
    final said = await action(item.id);
    if (said != null && context.mounted) showOrbitToast(context, said);
  }

  @override
  Widget build(BuildContext context) {
    final onPhone = [
      for (final item in model.themes)
        if (item.place == ThemePackPlace.onThisPhone) item,
    ];
    final onServer = [
      for (final item in model.themes)
        if (item.place == ThemePackPlace.onTheServer) item,
    ];

    return OrbitYouPage(
      title: 'More themes',
      children: [
        const OrbitGroupTitle('On this phone'),
        OrbitCard(
          dividerIndent: 14,
          children: [for (final item in onPhone) _row(context, item)],
        ),
        const OrbitSectionFoot(
          'A theme is drawn with only after this phone has checked it: the '
          'publisher\u2019s signature, the size of every file, and the theme '
          'itself. One that fails is never used.',
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
                  ? 'The themes on offer could not be read.'
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
                          ? 'Nothing is on offer here yet. The themes a '
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
          'A theme you download stays on this phone when the account signs '
          'out, and getting it back costs nothing.',
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ThemePackItem item) {
    final t = OrbitTokens.of(context);
    final use =
        item.place == ThemePackPlace.onThisPhone && !item.inUse && !item.busy
        ? () => _run(context, actions.onUse, item)
        : null;
    return OrbitListRow(
      icon: OrbitIcons.palette,
      title: item.name,
      sub: item.detail,
      subMono: item.place == ThemePackPlace.onTheServer,
      value: item.inUse ? 'In use' : (item.builtIn ? 'Built in' : ''),
      onTap: use,
      trailing: switch (item) {
        _ when item.busy => OrbitSpinner(size: 18, color: t.ink3),
        ThemePackItem(place: ThemePackPlace.onTheServer) => OrbitButton(
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
        _ when item.builtIn => null,
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
