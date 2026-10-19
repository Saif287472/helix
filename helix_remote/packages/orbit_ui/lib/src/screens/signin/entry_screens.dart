import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/codes.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/you_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

void _none() {}

/// A row of buttons (`.btn-row`): 16px under what is above, inset by the
/// gutter, 10px apart; [column] stacks them full width.
class OrbitButtonRow extends StatelessWidget {
  const OrbitButtonRow({
    super.key,
    required this.children,
    this.column = false,
    this.top = 16,
  });

  final List<Widget> children;
  final bool column;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(OrbitSpace.gutter, top, OrbitSpace.gutter, 0),
    child: column
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in children.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                c,
              ],
            ],
          )
        : Row(
            children: [
              for (final (i, c) in children.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: c),
              ],
            ],
          ),
  );
}

/// One transfer (`.xfer` in `css/pages.css`): history from or to another
/// device. 14px in, corner `--r-lg`, `--surface` with a `--line` edge, 10px
/// under what is above; the title at weight 600 after its filled icon in
/// `--accent`, the status at `--t-caption` in `--ink-3`, an optional
/// progress bar, and 38px buttons 12px under it, 8px apart.
class OrbitTransferCard extends StatelessWidget {
  const OrbitTransferCard({
    super.key,
    required this.title,
    required this.status,
    this.icon = OrbitIcons.deviceMobile,
    this.progress,
    this.actions = const [],
    this.top = 10,
    this.iconWeight = OrbitIconWeight.fill,
  });

  final String title;
  final String status;
  final OrbitGlyph icon;
  final double? progress;
  final List<OrbitButton> actions;
  final double top;

  /// Settings' transfers draw a bold up or down arrow.
  final OrbitIconWeight iconWeight;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(OrbitSpace.gutter, top, OrbitSpace.gutter, 0),
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
              OrbitIcon(icon, weight: iconWeight, size: 19, color: t.accent),
              const SizedBox(width: 8),
              Expanded(
                child: OrbitText(
                  title,
                  style: t.font.style(
                    size: OrbitType.body,
                    weight: 600,
                    color: t.ink,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OrbitText(
              status,
              style: t.font.style(
                size: OrbitType.caption,
                color: t.ink3,
                height: 1.45,
              ),
            ),
          ),
          if (progress != null)
            OrbitProgress(
              value: progress,
              margin: const EdgeInsets.only(top: 10),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: actions),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ restore

/// Where a restore is (`contracts/signin.md`).
enum RestoreStatus { idle, running, nothing, locked, failed, done }

/// One history offer from another device.
class RestoreOfferModel {
  const RestoreOfferModel({required this.title, required this.status});

  final String title;
  final String status;
}

/// `RestoreModel` (`contracts/signin.md`).
class RestoreModel {
  const RestoreModel({
    this.afterSignIn = true,
    this.status = RestoreStatus.idle,
    this.step = 0,
    this.addedSoFar,
    this.doneTitle = 'Restored 2,318 messages',
    this.offers = const [],
  });

  final bool afterSignIn;
  final RestoreStatus status;

  /// 0 to 3 while running: looking, downloading, unlocking, adding.
  final int step;

  /// "1,204 messages added so far", on the last step.
  final String? addedSoFar;
  final String doneTitle;
  final List<RestoreOfferModel> offers;
}

/// `RestoreActions` (`contracts/signin.md`).
class RestoreActions {
  const RestoreActions({
    this.onRestore,
    this.onRecoverySecret,
    this.onSkip,
    this.onContinue,
    this.onAcceptOffer,
    this.onDeclineOffer,
    this.onBack,
  });

  final VoidCallback? onRestore;
  final VoidCallback? onRecoverySecret;
  final VoidCallback? onSkip;
  final VoidCallback? onContinue;
  final ValueChanged<int>? onAcceptOffer;
  final ValueChanged<int>? onDeclineOffer;
  final VoidCallback? onBack;
}

/// `restore` (`restorePage` in `js/screens/signin.js`): bring your chats
/// back after signing in, or restore history from You, Backup.
class RestoreScreen extends StatelessWidget {
  const RestoreScreen({
    super.key,
    required this.model,
    this.actions = const RestoreActions(),
  });

  final RestoreModel model;
  final RestoreActions actions;

  static const _phases = [
    'Looking for your backup...',
    'Downloading your backup...',
    'Unlocking it...',
    'Adding messages...',
  ];

  @override
  Widget build(BuildContext context) {
    final m = model;
    final a = actions;
    final after = m.afterSignIn;
    final (Widget art, String title, String sub) = switch (m.status) {
      RestoreStatus.idle => (
        const OrbitStatusRing(state: OrbitRingState.idle),
        after ? 'Bring your chats back' : 'Restore from your backup',
        'Text messages only · files are not in the backup',
      ),
      RestoreStatus.running => (
        OrbitStatusRing(
          state: OrbitRingState.run,
          progress: (m.step + 1) / 4,
          label: '${m.step + 1}/4',
        ),
        _phases[m.step.clamp(0, 3)],
        m.step >= 3 && m.addedSoFar != null
            ? m.addedSoFar!
            : 'Encrypted with a key only your devices have',
      ),
      RestoreStatus.nothing => (
        const OrbitStatusRing(state: OrbitRingState.ok),
        'Nothing new to add',
        'Your backup is already on this phone',
      ),
      RestoreStatus.locked => (
        const OrbitStatusRing(state: OrbitRingState.bad),
        'This backup could not be opened',
        'It needs a key this device does not have. Try your recovery secret.',
      ),
      RestoreStatus.failed => (
        const OrbitStatusRing(state: OrbitRingState.bad),
        'No backup was found',
        'Back up on your other phone first, then try again',
      ),
      RestoreStatus.done => (
        const OrbitStatusRing(state: OrbitRingState.ok),
        m.doneTitle,
        'Messages already here were kept',
      ),
    };
    final finished =
        m.status == RestoreStatus.done || m.status == RestoreStatus.nothing;
    final offers = after || m.offers.isNotEmpty;
    return OrbitYouPage(
      title: after ? 'Restore your chats' : 'Restore history',
      lead: after ? OrbitAppBarLead.none : OrbitAppBarLead.back,
      onBack: a.onBack,
      children: [
        if (after) const OrbitPageIntro(title: 'Welcome back'),
        if (offers) ...[
          const OrbitGroupTitle('From your other devices'),
          for (final (i, o) in m.offers.indexed)
            OrbitTransferCard(
              top: i == 0 ? 0 : 10,
              title: o.title,
              status: o.status,
              actions: [
                OrbitButton(
                  label: 'Accept',
                  height: 38,
                  padding: 14,
                  fontSize: 13,
                  onPressed: () => a.onAcceptOffer?.call(i),
                ),
                OrbitButton(
                  label: 'Decline',
                  kind: OrbitButtonKind.secondary,
                  height: 38,
                  padding: 14,
                  fontSize: 13,
                  onPressed: () => a.onDeclineOffer?.call(i),
                ),
              ],
            ),
          const OrbitGroupTitle('From your backup'),
        ],
        OrbitHeroCard(title: title, sub: sub, art: art),
        if (finished)
          OrbitButtonRow(
            children: [
              OrbitButton(
                label: after ? 'Continue' : 'Done',
                block: true,
                onPressed: a.onContinue ?? _none,
              ),
            ],
          )
        else
          OrbitButtonRow(
            column: true,
            children: [
              OrbitButton(
                label: m.status == RestoreStatus.failed
                    ? 'Try again'
                    : 'Restore from my backup',
                icon: OrbitIcons.cloudArrowDown,
                block: true,
                onPressed: m.status == RestoreStatus.running
                    ? null
                    : a.onRestore ?? _none,
              ),
              OrbitButton(
                label: 'I have a recovery secret',
                icon: OrbitIcons.key,
                kind: OrbitButtonKind.secondary,
                block: true,
                onPressed: a.onRecoverySecret ?? _none,
              ),
              if (after)
                OrbitButton(
                  label: 'Skip for now',
                  kind: OrbitButtonKind.ghost,
                  block: true,
                  onPressed: a.onSkip ?? _none,
                ),
            ],
          ),
        _CentredFoot(
          after
              ? 'You can restore later from You, Backup.'
              : 'Text messages you backed up come back to this device. '
                    'Messages already here are kept.',
        ),
      ],
    );
  }
}

/// `.sec-foot` centred, 16px down.
class _CentredFoot extends StatelessWidget {
  const _CentredFoot(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: OrbitText(
        text,
        textAlign: TextAlign.center,
        style: t.font.style(
          size: OrbitType.caption,
          color: t.ink3,
          height: 1.5,
        ),
      ),
    );
  }
}

// -------------------------------------------------------- link this device

/// Where linking this device is.
enum LinkThisDevicePhase {
  starting,
  waiting,
  expired,
  approved,
  confirm,
  declined,
  failed,
}

/// `LinkThisDeviceModel` (`contracts/signin.md`).
class LinkThisDeviceModel {
  const LinkThisDeviceModel({
    this.phase = LinkThisDevicePhase.waiting,
    this.qrPayload = 'link-this-device',
    this.checkNumber = '72 914',
    this.expiresIn = '9:45',
    this.maskedPhone = '+880 17•• ••0001',
    this.helixName = '~hasan',
    this.keyCode = '4821 9930 1175',
    this.showSimulate = true,
  });

  final LinkThisDevicePhase phase;
  final String qrPayload;
  final String checkNumber;

  /// "9:45", counting down to the code's expiry.
  final String expiresIn;
  final String maskedPhone;
  final String helixName;
  final String keyCode;

  /// The prototype's "Simulate approval" (a demo control; the app has none).
  final bool showSimulate;
}

/// `LinkThisDeviceActions` (`contracts/signin.md`).
class LinkThisDeviceActions {
  const LinkThisDeviceActions({
    this.onNewCode,
    this.onYes,
    this.onNo,
    this.onCancel,
    this.onSimulate,
  });

  final VoidCallback? onNewCode;
  final VoidCallback? onYes;
  final VoidCallback? onNo;
  final VoidCallback? onCancel;
  final VoidCallback? onSimulate;
}

/// `link-device` (`js/screens/signin.js`): link a new phone by scanning its
/// code on a device that is already signed in.
class LinkThisDeviceScreen extends StatelessWidget {
  const LinkThisDeviceScreen({
    super.key,
    required this.model,
    this.actions = const LinkThisDeviceActions(),
  });

  final LinkThisDeviceModel model;
  final LinkThisDeviceActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final phase = m.phase;
    if (phase == LinkThisDevicePhase.confirm) {
      return OrbitPage(
        title: 'Link this device',
        lead: OrbitAppBarLead.close,
        onBack: a.onCancel,
        children: [
          const OrbitPageIntro(
            title: 'Is this your account?',
            text:
                'Your other device approved this one. Check that this is your '
                'account before Orbit gives this phone its keys.',
          ),
          OrbitSection(
            title: 'The account',
            rows: [
              OrbitListRow(
                icon: OrbitIcons.phone,
                iconColor: 0,
                title: m.maskedPhone,
                sub: 'Phone number, shown in part',
              ),
              OrbitListRow(
                icon: OrbitIcons.at,
                iconColor: 1,
                title: m.helixName,
                sub: 'Orbit name',
              ),
            ],
          ),
          OrbitCodeBox(
            label: 'Key code',
            code: m.keyCode,
            note:
                'The same key code is shown on your other device. If it is '
                'different, or the account is not yours, choose No.',
          ),
          const OrbitSectionFoot(
            'Choosing Yes gives this phone your account’s keys. It can then '
            'read your new messages.',
          ),
          OrbitButtonRow(
            column: true,
            children: [
              OrbitButton(
                label: 'Yes, this is my account',
                icon: OrbitIcons.check,
                iconWeight: OrbitIconWeight.bold,
                block: true,
                onPressed: a.onYes ?? _none,
              ),
              OrbitButton(
                label: 'No, this is not my account',
                kind: OrbitButtonKind.secondary,
                block: true,
                onPressed: a.onNo ?? _none,
              ),
            ],
          ),
        ],
      );
    }
    if (phase == LinkThisDevicePhase.declined ||
        phase == LinkThisDevicePhase.failed) {
      final declined = phase == LinkThisDevicePhase.declined;
      return OrbitPage(
        title: 'Link this device',
        onBack: a.onCancel,
        children: [
          OrbitHeroCard(
            art: const OrbitStatusRing(state: OrbitRingState.bad),
            title: declined ? 'Nothing was kept' : 'That did not work',
            sub: declined
                ? 'You said this is not your account, so this device was not '
                      'linked'
                : 'The other device’s approval could not be checked',
          ),
          OrbitSectionFoot(
            declined
                ? 'If that was a mistake, show a new code and approve it again '
                      'on your other device.'
                : 'Check your connection, then show a new code and try again.',
          ),
          OrbitButtonRow(
            children: [
              OrbitButton(
                label: 'Show a new code',
                icon: OrbitIcons.qrCode,
                block: true,
                onPressed: a.onNewCode ?? _none,
              ),
            ],
          ),
        ],
      );
    }
    final note = t.font.style(size: OrbitType.small, color: t.ink3);
    final Widget status = switch (phase) {
      LinkThisDevicePhase.expired => OrbitInlineNotice(
        kind: OrbitNoticeKind.error,
        text: 'This code has expired. Show a new code to try again.',
        action: OrbitNoticeAction('Show a new code', a.onNewCode ?? _none),
      ),
      LinkThisDevicePhase.approved => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: OrbitText.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: OrbitIcon(
                  OrbitIcons.checkCircle,
                  weight: OrbitIconWeight.fill,
                  size: OrbitType.body,
                  color: t.success,
                ),
              ),
              const TextSpan(text: ' Approved. Signing in...'),
            ],
          ),
          textAlign: TextAlign.center,
          style: t.font.style(
            size: OrbitType.body,
            weight: 600,
            color: t.success,
          ),
        ),
      ),
      LinkThisDevicePhase.starting => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: OrbitText(
          'Getting a code…',
          textAlign: TextAlign.center,
          style: note,
        ),
      ),
      _ => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: OrbitText.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: OrbitIcon(
                  OrbitIcons.spinnerGap,
                  size: OrbitType.small,
                  color: t.ink3,
                ),
              ),
              const TextSpan(text: ' Waiting for approval. Code expires in '),
              TextSpan(
                text: m.expiresIn,
                style: t.mono.style(size: OrbitType.small, color: t.ink3),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: note,
        ),
      ),
    };
    return OrbitPage(
      title: 'Link this device',
      onBack: a.onCancel,
      children: [
        const OrbitPageIntro(
          text:
              'On a device that is already signed in to your account, open '
              'Settings, Devices, Link a new device, and scan this code. Show '
              'it only to your own device.',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Center(
            child: Opacity(
              opacity: phase == LinkThisDevicePhase.expired ? 0.25 : 1,
              child: OrbitQrCard(
                child: phase == LinkThisDevicePhase.starting
                    ? Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: t.field,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: OrbitSpinner(size: 30, color: t.accent),
                        ),
                      )
                    : OrbitQr(seed: m.qrPayload, size: 220),
              ),
            ),
          ),
        ),
        OrbitCodeBox(
          label: 'Check number',
          code: m.checkNumber,
          size: OrbitCodeSize.huge,
        ),
        status,
        if (phase == LinkThisDevicePhase.waiting && m.showSimulate)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: OrbitButton(
                label: 'Simulate approval',
                kind: OrbitButtonKind.ghost,
                onPressed: a.onSimulate ?? _none,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- reset

/// Why the reset screen is showing.
enum ResetKind { window, start, fine, keyMissing, cannotDecrypt }

/// `ResetModel` (`contracts/signin.md`).
class ResetModel {
  const ResetModel({
    required this.kind,
    this.typed = '',
    this.busy = false,
    this.failed = false,
  });

  final ResetKind kind;
  final String typed;
  final bool busy;
  final bool failed;
}

/// `ResetActions` (`contracts/signin.md`).
class ResetActions {
  const ResetActions({this.onTyped, this.onReset, this.onTryAgain});

  final ValueChanged<String>? onTyped;
  final VoidCallback? onReset;
  final VoidCallback? onTryAgain;
}

/// `reset` (`js/screens/signin.js`): Orbit is open elsewhere, could not
/// start, or needs a destructive reset (type DELETE).
class ResetScreen extends StatelessWidget {
  const ResetScreen({
    super.key,
    required this.model,
    this.actions = const ResetActions(),
  });

  final ResetModel model;
  final ResetActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    final top = MediaQuery.paddingOf(context).top;
    Widget page(String title, Widget body) => ColoredBox(
      color: t.bg,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrbitAppBar(title: title, lead: OrbitAppBarLead.none),
            Expanded(child: body),
          ],
        ),
      ),
    );
    switch (m.kind) {
      case ResetKind.window:
        return page(
          'Orbit',
          OrbitCenterPage(
            icon: OrbitIcons.appWindow,
            iconColor: t.accent,
            iconBackground: t.accentSoft,
            title: 'Orbit is open elsewhere',
            text:
                'Orbit is already open in another window. Close that one, then '
                'try again.',
            children: [
              OrbitButton(label: 'Try again', onPressed: a.onTryAgain ?? _none),
            ],
          ),
        );
      case ResetKind.start:
        return page(
          'Orbit',
          OrbitCenterPage(
            icon: OrbitIcons.warning,
            iconColor: t.warning,
            iconBackground: t.warningSoft,
            title: 'Orbit could not start',
            text:
                'Something went wrong while opening your data. Nothing was '
                'changed.',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OrbitButton(
                  label: 'Try again',
                  icon: OrbitIcons.arrowsClockwise,
                  onPressed: a.onTryAgain ?? _none,
                ),
              ),
            ],
          ),
        );
      case ResetKind.fine:
        return page(
          'Orbit',
          OrbitCenterPage(
            icon: OrbitIcons.checkCircle,
            iconColor: t.success,
            iconBackground: t.successSoft,
            title: 'Your local data is fine',
            text: 'There is nothing to reset.',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OrbitButton(
                  label: 'Continue',
                  onPressed: a.onTryAgain ?? _none,
                ),
              ),
            ],
          ),
        );
      case ResetKind.keyMissing:
      case ResetKind.cannotDecrypt:
        final ok = m.typed == 'DELETE';
        return page(
          'Reset required',
          SingleChildScrollView(
            child: OrbitCenterPage(
              top: true,
              icon: OrbitIcons.lockKey,
              iconColor: t.danger,
              iconBackground: t.dangerSoft,
              title: 'Reset required',
              text: m.kind == ResetKind.keyMissing
                  ? 'An existing database was found, but its encryption key is '
                        'not available in secure storage. A destructive reset '
                        'is required to continue.'
                  : 'Your local database could not be decrypted. Orbit never '
                        'opens it without its key, so a destructive reset is '
                        'required to continue.',
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OrbitTextField(
                    label: 'Type DELETE to confirm',
                    hint: 'DELETE',
                    initialValue: m.typed,
                    mono: true,
                    onChanged: a.onTyped,
                  ),
                ),
                Opacity(
                  opacity: ok ? 1 : 0.5,
                  child: OrbitButton(
                    label: m.busy ? 'Deleting…' : 'Reset Orbit',
                    kind: ok
                        ? OrbitButtonKind.danger
                        : OrbitButtonKind.secondary,
                    block: true,
                    onPressed: ok ? a.onReset ?? _none : _none,
                  ),
                ),
                if (m.failed && !m.busy)
                  const _InlineError('The reset did not finish. Try again.'),
              ],
            ),
          ),
        );
    }
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: OrbitIcon(
            OrbitIcons.warningCircle,
            weight: OrbitIconWeight.fill,
            size: 18,
            color: t.danger,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: OrbitText(
            text,
            style: t.font.style(
              size: OrbitType.small,
              color: t.danger,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- lock

/// `LockModel` (`contracts/signin.md`).
class LockModel {
  const LockModel({
    this.unlockWith = 'your fingerprint, face or phone PIN',
    this.failed = false,
  });

  /// "your fingerprint, face or phone PIN"; "Windows Hello (your face,
  /// fingerprint or PIN)" on Windows.
  final String unlockWith;
  final bool failed;
}

/// `LockActions` (`contracts/signin.md`).
class LockActions {
  const LockActions({this.onUnlock});

  final VoidCallback? onUnlock;
}

/// `lock` (`js/screens/signin.js`): the app lock over everything.
class LockScreen extends StatelessWidget {
  const LockScreen({
    super.key,
    this.model = const LockModel(),
    this.actions = const LockActions(),
  });

  final LockModel model;
  final LockActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: t.bg,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Center(
          child: OrbitCenterPage(
            icon: OrbitIcons.lockSimple,
            iconColor: t.accent,
            iconBackground: t.surface,
            iconRing: true,
            title: 'Orbit is locked',
            text: 'Unlock with ${model.unlockWith}.',
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OrbitButton(
                  label: 'Unlock',
                  icon: OrbitIcons.fingerprint,
                  onPressed: actions.onUnlock ?? _none,
                ),
              ),
              if (model.failed)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: _InlineError('Not unlocked. Try again.'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
