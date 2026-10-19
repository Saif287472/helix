import 'package:flutter/material.dart';

import 'package:orbit_ui/src/brand/orbit_mark.dart';
import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chip_tag.dart';
import 'package:orbit_ui/src/components/codes.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/pages.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/components/state_kit.dart';
import 'package:orbit_ui/src/components/toggles.dart';
import 'package:orbit_ui/src/components/you_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/screens/signin/entry_screens.dart'
    show OrbitButtonRow;
import 'package:orbit_ui/src/screens/you/you_screens.dart'
    show OrbitTileGrid, OrbitTopicTile;
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

void _none() {}

/// `Kit.formCard`: a card that holds fields rather than rows, 14px in and
/// 2px at the foot.
class OrbitFormCard extends StatelessWidget {
  const OrbitFormCard({
    super.key,
    required this.children,
    this.dangerZone = false,
  });

  final List<Widget> children;
  final bool dangerZone;

  @override
  Widget build(BuildContext context) => OrbitCard(
    dangerZone: dangerZone,
    dividers: false,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
    children: children,
  );
}

// ---------------------------------------------------------------- password

enum PasswordStage { editing, saving, done }

class PasswordModel {
  const PasswordModel({
    this.isSet = false,
    this.stage = PasswordStage.editing,
    this.needsPhoneNumber = false,
    this.lastChangedLabel = '',
    this.currentError,
    this.lockout,
    this.initialCurrent = '',
    this.initialNew = '',
    this.initialConfirm = '',
    this.showMismatch = false,
  });

  /// Setting a first password rather than changing one.
  final bool isSet;
  final PasswordStage stage;

  /// A linked device asks for the number once.
  final bool needsPhoneNumber;

  /// "Last changed 3 weeks ago".
  final String lastChangedLabel;

  /// "That is not your current password."
  final String? currentError;

  /// "Too many tries. Try again in 15 minutes."
  final String? lockout;

  /// Preview start values.
  final String initialCurrent;
  final String initialNew;
  final String initialConfirm;

  /// Say so under Confirm when the two differ (`password-error`).
  final bool showMismatch;
}

class PasswordActions {
  const PasswordActions({this.onSave, this.onDone});

  final void Function({
    String? phone,
    String? current,
    required String password,
  })?
  onSave;
  final VoidCallback? onDone;
}

/// `password`: change or set your password. The rules tick as you type and
/// the button turns on when they all pass.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({
    super.key,
    required this.model,
    this.actions = const PasswordActions(),
  });

  final PasswordModel model;
  final PasswordActions actions;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  late final _phone = TextEditingController(text: '+880 ');
  late final _pw0 = TextEditingController(text: widget.model.initialCurrent);
  late final _pw1 = TextEditingController(text: widget.model.initialNew);
  late final _pw2 = TextEditingController(text: widget.model.initialConfirm);
  var _show = false;

  @override
  void dispose() {
    for (final c in [_phone, _pw0, _pw1, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  List<OrbitRule> get _rules {
    final set = widget.model.isSet;
    return [
      OrbitRule('At least 8 characters', ok: _pw1.text.length >= 8),
      if (!set)
        OrbitRule(
          'Not the same as your current one',
          ok: _pw1.text.isNotEmpty && _pw1.text != _pw0.text,
        ),
      OrbitRule(
        'Both new passwords match',
        ok: _pw2.text.isNotEmpty && _pw1.text == _pw2.text,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final a = widget.actions;
    final title = m.isSet ? 'Set a password' : 'Change password';
    if (m.stage == PasswordStage.done) {
      return OrbitYouPage(
        title: title,
        children: [
          const OrbitHeroCard(
            art: OrbitStatusRing(state: OrbitRingState.ok),
            title: 'Password saved',
            sub: 'Use it to sign in on a new phone',
          ),
          OrbitButtonRow(
            children: [
              OrbitButton(
                label: 'Done',
                block: true,
                onPressed: a.onDone ?? () => Navigator.maybePop(context),
              ),
            ],
          ),
        ],
      );
    }
    final rules = _rules;
    final ok = rules.every((r) => r.ok);
    final mismatch =
        m.showMismatch && _pw2.text.isNotEmpty && _pw1.text != _pw2.text;
    void changed(String _) => setState(() {});
    return OrbitYouPage(
      title: title,
      children: [
        m.isSet
            ? const OrbitHeroCard(
                icon: OrbitIcons.password,
                title: 'Set a password',
                sub: 'Sign in on a new phone without another device',
                pills: [
                  OrbitHeroPill(
                    icon: OrbitIcons.warningCircle,
                    text: 'Orbit cannot reset it',
                    tone: OrbitPillTone.warn,
                  ),
                ],
              )
            : OrbitHeroCard(
                icon: OrbitIcons.password,
                title: 'Change password',
                sub: m.lastChangedLabel,
                pills: const [
                  OrbitHeroPill(
                    icon: OrbitIcons.deviceMobile,
                    text: 'Checked on this device',
                  ),
                  OrbitHeroPill(
                    icon: OrbitIcons.lockSimple,
                    text: 'Never sent to Orbit',
                  ),
                ],
              ),
        OrbitGroupTitle(m.isSet ? 'Your new password' : 'Passwords'),
        OrbitFormCard(
          children: [
            if (m.needsPhoneNumber)
              OrbitTextField(
                label: 'Your phone number',
                controller: _phone,
                keyboardType: TextInputType.phone,
                helper:
                    'Needed once to check your current password, with its '
                    'country code',
              ),
            if (!m.isSet)
              OrbitTextField(
                label: 'Current password',
                controller: _pw0,
                obscure: !_show,
                error: m.currentError ?? '',
                onChanged: changed,
              ),
            if (m.lockout != null) OrbitFieldLock(m.lockout!),
            OrbitTextField(
              label: 'New password',
              controller: _pw1,
              obscure: !_show,
              onChanged: changed,
            ),
            OrbitTextField(
              label: 'Confirm new password',
              controller: _pw2,
              obscure: !_show,
              error: mismatch ? 'The passwords do not match.' : '',
              onChanged: changed,
            ),
            OrbitRules(rules: rules),
            OrbitCheckbox(
              label: 'Show passwords',
              on: _show,
              top: 0,
              onChanged: (v) => setState(() => _show = v),
            ),
          ],
        ),
        OrbitButtonRow(
          children: [
            OrbitButton(
              label: title,
              block: true,
              busy: m.stage == PasswordStage.saving,
              onPressed: ok
                  ? () => a.onSave?.call(
                      phone: m.needsPhoneNumber ? _phone.text : null,
                      current: m.isSet ? null : _pw0.text,
                      password: _pw1.text,
                    )
                  : null,
            ),
          ],
        ),
        OrbitSectionFoot(
          m.isSet
              ? 'Choose one you will remember: Orbit cannot reset it.'
              : 'Only a key made from your password leaves this device, so '
                    'Orbit cannot reset it.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- delete account

enum DeleteProof { password, sms, key }

class DeleteAccountModel {
  const DeleteAccountModel({
    this.proof = DeleteProof.password,
    this.needsPhoneNumber = false,
    this.codeSent = false,
    this.phoneMasked = '',
    this.deleting = false,
  });

  final DeleteProof proof;
  final bool needsPhoneNumber;
  final bool codeSent;
  final String phoneMasked;
  final bool deleting;
}

class DeleteAccountActions {
  const DeleteAccountActions({
    this.onSendCode,
    this.onResendCode,
    this.onDelete,
    this.onExport,
    this.onCancel,
  });

  final VoidCallback? onSendCode;
  final VoidCallback? onResendCode;

  /// With the proof: the password, the SMS code, or nothing for the key.
  final void Function({String? phone, String? secret})? onDelete;
  final VoidCallback? onExport;
  final VoidCallback? onCancel;
}

/// `delete-account`: what happens, export first, then type DELETE and prove
/// it is you.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.model,
    this.actions = const DeleteAccountActions(),
  });

  final DeleteAccountModel model;
  final DeleteAccountActions actions;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _typed = TextEditingController();
  final _phone = TextEditingController(text: '+880 ');
  final _secret = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    _phone.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _go() {
    final m = widget.model;
    final a = widget.actions;
    if (m.proof == DeleteProof.sms && !m.codeSent) {
      a.onSendCode?.call();
      return;
    }
    if (_typed.text != 'DELETE') {
      showOrbitToast(context, 'Type DELETE to confirm.');
      return;
    }
    a.onDelete?.call(
      phone: m.needsPhoneNumber ? _phone.text : null,
      secret: m.proof == DeleteProof.key ? null : _secret.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = widget.model;
    final a = widget.actions;
    final help = t.font.style(
      size: OrbitType.caption,
      color: t.ink3,
      height: 1.45,
    );
    OrbitListRow what(OrbitGlyph icon, String title) =>
        OrbitListRow(icon: icon, iconColor: 7, title: title);
    final proof = <Widget>[
      if (m.proof == DeleteProof.password) ...[
        if (m.needsPhoneNumber)
          OrbitTextField(
            label: 'Your phone number',
            controller: _phone,
            keyboardType: TextInputType.phone,
            helper: 'Needed once to check your password, with its country code',
          ),
        OrbitTextField(
          label: 'Your password',
          controller: _secret,
          obscure: true,
          eye: true,
          helper: 'It is checked on this phone; Orbit never sees it.',
        ),
      ],
      if (m.proof == DeleteProof.sms && m.codeSent) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: OrbitText(
            'We sent a 6-digit code to ${m.phoneMasked}.',
            style: help,
          ),
        ),
        OrbitTextField(
          label: 'Code',
          controller: _secret,
          keyboardType: TextInputType.number,
          maxLength: 6,
          mono: true,
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: OrbitButton(
                label: 'Send a new code',
                kind: OrbitButtonKind.ghost,
                height: 36,
                padding: 4,
                onPressed: a.onResendCode ?? _none,
              ),
            ),
          ),
        ),
      ],
      if (m.proof == DeleteProof.sms && !m.codeSent)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
          child: OrbitText(
            'Orbit will text a code to your phone number to check that it is '
            'you.',
            style: help,
          ),
        ),
      if (m.proof == DeleteProof.key)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
          child: OrbitText(
            'This phone will prove it is yours with its own key. Nothing else '
            'to enter.',
            style: help,
          ),
        ),
    ];
    final primary = m.proof == DeleteProof.sms && !m.codeSent
        ? 'Send me a code'
        : 'Delete my account';
    return OrbitYouPage(
      title: 'Delete my account',
      children: [
        const OrbitHeroCard(
          icon: OrbitIcons.warning,
          tone: OrbitHeroTone.danger,
          title: 'Delete your account',
          sub: 'Permanent · every device · cannot be undone',
        ),
        OrbitSection(
          title: 'What happens',
          rows: [
            what(
              OrbitIcons.userMinus,
              'Your account and your devices are removed',
            ),
            what(
              OrbitIcons.cloudX,
              'Everything the server holds for you is deleted',
            ),
            what(
              OrbitIcons.devices,
              'Your other devices lose their messages when they are signed '
              'out',
            ),
            what(OrbitIcons.chats, 'People you talked to keep their copies'),
          ],
        ),
        OrbitSection(
          rows: [
            OrbitListRow(
              icon: OrbitIcons.export,
              iconColor: 2,
              title: 'Export my data first',
              sub: 'Account details, devices and settings',
              end: OrbitRowEnd.chevron,
              onTap: a.onExport,
            ),
          ],
        ),
        const OrbitGroupTitle('Confirm it is you', danger: true),
        OrbitFormCard(
          dangerZone: true,
          children: [
            OrbitTextField(
              label: 'Type DELETE to confirm',
              controller: _typed,
              hint: 'DELETE',
              mono: true,
            ),
            ...proof,
          ],
        ),
        if (m.deleting)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              OrbitSpace.gutter,
              14,
              OrbitSpace.gutter,
              0,
            ),
            child: OrbitProgress(margin: EdgeInsets.zero),
          ),
        OrbitButtonRow(
          column: true,
          children: [
            OrbitButton(
              label: primary,
              icon: OrbitIcons.trash,
              kind: OrbitButtonKind.danger,
              block: true,
              onPressed: _go,
            ),
            OrbitButton(
              label: 'Cancel',
              kind: OrbitButtonKind.secondary,
              block: true,
              onPressed: a.onCancel ?? () => Navigator.maybePop(context),
            ),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- blocked

class BlockedPersonItem {
  const BlockedPersonItem({
    required this.account,
    required this.name,
    required this.avatar,
    this.detail = '',
  });

  final String account;
  final String name;
  final HelixAvatarModel avatar;

  /// Their number, in mono.
  final String detail;
}

class BlockedModel {
  const BlockedModel({this.people = const []});

  final List<BlockedPersonItem> people;
}

class BlockedActions {
  const BlockedActions({this.onUnblock});

  final ValueChanged<String>? onUnblock;
}

/// `blocked`: who you blocked, each with Unblock (asks first).
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({
    super.key,
    required this.model,
    this.actions = const BlockedActions(),
  });

  final BlockedModel model;
  final BlockedActions actions;

  @override
  Widget build(BuildContext context) {
    final n = model.people.length;
    return OrbitYouPage(
      title: 'Blocked',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.prohibit,
          title: n == 0
              ? 'Nobody is blocked'
              : '$n blocked ${n == 1 ? 'person' : 'people'}',
          sub: n == 0
              ? 'People you block cannot message or call you'
              : 'They cannot message or call you',
          pills: const [
            OrbitHeroPill(
              icon: OrbitIcons.eye,
              text: 'Orbit tells them they are blocked',
            ),
          ],
        ),
        if (n > 0)
          OrbitSection(
            title: 'Blocked',
            rows: [
              for (final p in model.people)
                OrbitListRow(
                  leading: OrbitAvatar(avatar: p.avatar, size: 40),
                  title: p.name,
                  sub: p.detail,
                  subMono: true,
                  trailing: OrbitButton(
                    label: 'Unblock',
                    kind: OrbitButtonKind.secondary,
                    height: 38,
                    onPressed: () => showOrbitDialog(
                      context,
                      title: 'Unblock ${p.name}?',
                      text: 'They will be able to message and call you again.',
                      actions: [
                        const OrbitDialogAction('Cancel'),
                        OrbitDialogAction(
                          'Unblock',
                          kind: OrbitButtonKind.primary,
                          onPressed: () => actions.onUnblock?.call(p.account),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        OrbitSectionFoot(
          '${n == 0 ? 'Nobody is blocked. ' : ''}To block someone, open their '
          'chat or their contact page.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- about, legal

enum LegalDoc { terms, privacy }

class AboutModel {
  const AboutModel({
    this.versionLabel = '',
    this.serverName = '',
    this.serverHost = '',
    this.termsVersion = '',
    this.privacyVersion = '',
    this.crashReportsAccepted = true,
    this.sendCrashReports = false,
  });

  /// "Version 2.0.0 (412)".
  final String versionLabel;
  final String serverName;
  final String serverHost;
  final String termsVersion;
  final String privacyVersion;
  final bool crashReportsAccepted;
  final bool sendCrashReports;
}

class AboutActions {
  const AboutActions({
    this.onOpenDoc,
    this.onOpenAdvanced,
    this.onOpenLicences,
    this.onSendCrashReports,
  });

  final ValueChanged<LegalDoc>? onOpenDoc;
  final VoidCallback? onOpenAdvanced;
  final VoidCallback? onOpenLicences;
  final ValueChanged<bool>? onSendCrashReports;
}

/// `about`: the app and its server, the legal documents, and diagnostics.
class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    required this.model,
    this.actions = const AboutActions(),
  });

  final AboutModel model;
  final AboutActions actions;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late var _crash = widget.model.sendCrashReports;

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final a = widget.actions;
    return OrbitYouPage(
      title: 'Help and about',
      children: [
        OrbitHeroCard(
          art: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: const OrbitMark(size: 48),
          ),
          title: 'Orbit',
          sub: m.versionLabel,
          pills: [
            OrbitHeroPill(icon: OrbitIcons.globeSimple, text: m.serverName),
            const OrbitHeroPill(
              icon: OrbitIcons.lockSimple,
              text: 'End-to-end encrypted',
            ),
          ],
        ),
        const OrbitGroupTitle('Legal'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
          child: OrbitTileGrid(
            tiles: [
              OrbitTopicTile(
                icon: OrbitIcons.scroll,
                colour: 2,
                title: 'Terms of Service',
                status: 'Version ${m.termsVersion}',
                onTap: () => a.onOpenDoc?.call(LegalDoc.terms),
              ),
              OrbitTopicTile(
                icon: OrbitIcons.shieldCheck,
                colour: 3,
                title: 'Privacy Policy',
                status: 'Version ${m.privacyVersion}',
                onTap: () => a.onOpenDoc?.call(LegalDoc.privacy),
              ),
            ],
          ),
        ),
        OrbitSection(
          title: 'More',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.hardDrives,
              iconColor: 1,
              title: 'Server details',
              sub: '${m.serverName} (${m.serverHost})',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenAdvanced,
            ),
            OrbitListRow(
              icon: OrbitIcons.code,
              iconColor: 7,
              title: 'Open-source licences',
              end: OrbitRowEnd.chevron,
              onTap: a.onOpenLicences,
            ),
          ],
        ),
        if (m.crashReportsAccepted)
          OrbitSection(
            title: 'Diagnostics',
            footer:
                'A crash report never contains messages, names, numbers or '
                'keys.',
            rows: [
              OrbitListRow(
                title: 'Send crash reports',
                sub: 'Only the error’s type, the app version and the platform',
                end: OrbitRowEnd.toggle,
                on: _crash,
                onChanged: (v) {
                  setState(() => _crash = v);
                  a.onSendCrashReports?.call(v);
                },
              ),
            ],
          )
        else
          const OrbitSection(
            title: 'Diagnostics',
            rows: [
              OrbitListRow(
                icon: OrbitIcons.bug,
                iconColor: 7,
                title: 'Crash reports',
                sub: 'This server does not accept crash reports',
              ),
            ],
          ),
      ],
    );
  }
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.version,
    required this.body,
  });

  final String title;
  final String version;
  final String body;
}

class LegalModel {
  const LegalModel({
    required this.terms,
    required this.privacy,
    this.initial = LegalDoc.terms,
  });

  final LegalDocument terms;
  final LegalDocument privacy;
  final LegalDoc initial;
}

/// `legal`: the Terms and the Privacy Policy, one at a time.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.model});

  final LegalModel model;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late var _doc = widget.model.initial;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final d = _doc == LegalDoc.terms
        ? widget.model.terms
        : widget.model.privacy;
    return OrbitYouPage(
      title: 'Terms and Privacy Policy',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OrbitSpace.gutter,
            6,
            OrbitSpace.gutter,
            0,
          ),
          child: OrbitSegmented<LegalDoc>(
            options: const [
              OrbitSegment(LegalDoc.terms, 'Terms', icon: OrbitIcons.fileText),
              OrbitSegment(
                LegalDoc.privacy,
                'Privacy',
                icon: OrbitIcons.shieldCheck,
              ),
            ],
            value: _doc,
            onChanged: (v) => setState(() => _doc = v),
          ),
        ),
        const SizedBox(height: 12),
        OrbitCard(
          dividers: false,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OrbitText(d.title, style: t.display(size: 17)),
                  ),
                  const SizedBox(width: 10),
                  OrbitTag(label: 'Version ${d.version}'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: OrbitText(
                d.body,
                style: t.font.style(size: 13.5, color: t.ink2, height: 1.65),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- advanced

class AdvancedModel {
  const AdvancedModel({
    required this.serverName,
    required this.serverHost,
    this.reachable = true,
    this.serverVersion = '',
    this.openSignUp = true,
    this.maxAttachmentLabel = '',
    this.termsVersion = '',
    this.privacyVersion = '',
    this.features = const [],
    this.syncing = false,
    this.synced = false,
  });

  final String serverName;
  final String serverHost;
  final bool reachable;
  final String serverVersion;
  final bool openSignUp;
  final String maxAttachmentLabel;
  final String termsVersion;
  final String privacyVersion;

  /// What the operator switched on or off.
  final List<({String name, bool on})> features;
  final bool syncing;
  final bool synced;
}

class AdvancedActions {
  const AdvancedActions({this.onSync, this.onRetry});

  final VoidCallback? onSync;
  final VoidCallback? onRetry;
}

/// `advanced`: the server, its limits and features, and Check for messages
/// now.
class AdvancedScreen extends StatelessWidget {
  const AdvancedScreen({
    super.key,
    required this.model,
    this.actions = const AdvancedActions(),
  });

  final AdvancedModel model;
  final AdvancedActions actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = model;
    final a = actions;
    OrbitListRow fact(OrbitGlyph icon, int c, String title, String value) =>
        OrbitListRow(
          icon: icon,
          iconColor: c,
          title: title,
          trailing: Text(
            value,
            style: t.mono.style(size: OrbitType.small, color: t.ink3),
          ),
        );
    return OrbitYouPage(
      title: 'Advanced',
      children: [
        OrbitHeroCard(
          icon: OrbitIcons.hardDrives,
          tone: m.reachable ? OrbitHeroTone.brand : OrbitHeroTone.warn,
          title: m.serverName,
          sub: m.serverHost,
          pills: m.reachable
              ? [
                  const OrbitHeroPill(
                    icon: OrbitIcons.checkCircle,
                    text: 'Connected',
                    tone: OrbitPillTone.ok,
                  ),
                  OrbitHeroPill(
                    icon: OrbitIcons.tag,
                    text: 'Server ${m.serverVersion}',
                  ),
                  if (m.openSignUp)
                    const OrbitHeroPill(
                      icon: OrbitIcons.userPlus,
                      text: 'New accounts can join',
                    ),
                ]
              : const [
                  OrbitHeroPill(
                    icon: OrbitIcons.warningCircle,
                    text: 'Cannot reach it',
                    tone: OrbitPillTone.warn,
                  ),
                ],
        ),
        if (!m.reachable)
          OrbitInlineNotice(
            kind: OrbitNoticeKind.error,
            text:
                'The server could not be reached, so its details are not '
                'available.',
            action: OrbitNoticeAction('Try again', a.onRetry ?? _none),
          )
        else ...[
          OrbitSection(
            title: 'Limits and documents',
            rows: [
              fact(
                OrbitIcons.paperclip,
                2,
                'Largest attachment',
                m.maxAttachmentLabel,
              ),
              fact(OrbitIcons.scroll, 3, 'Terms version', m.termsVersion),
              fact(
                OrbitIcons.shieldCheck,
                1,
                'Privacy policy version',
                m.privacyVersion,
              ),
            ],
          ),
          OrbitSection(
            title: 'Server features',
            footer: 'Switched by the server’s operator.',
            rows: [
              for (final f in m.features)
                OrbitListRow(
                  title: f.name,
                  trailing: OrbitTag(
                    label: f.on ? 'On' : 'Off',
                    tone: f.on ? OrbitTagTone.success : OrbitTagTone.plain,
                  ),
                ),
            ],
          ),
        ],
        OrbitSection(
          title: 'Connection',
          footer:
              'Orbit keeps a live connection to the server while it is open, '
              'so this is rarely needed.',
          rows: [
            OrbitListRow(
              icon: OrbitIcons.arrowsClockwise,
              iconColor: 0,
              title: 'Check for messages now',
              trailing: m.syncing
                  ? OrbitSpinner(size: 18, color: t.ink3)
                  : m.synced
                  ? const OrbitTag(
                      label: 'Up to date',
                      tone: OrbitTagTone.success,
                      icon: OrbitIcons.check,
                    )
                  : null,
              onTap: a.onSync ?? _none,
            ),
          ],
        ),
      ],
    );
  }
}
