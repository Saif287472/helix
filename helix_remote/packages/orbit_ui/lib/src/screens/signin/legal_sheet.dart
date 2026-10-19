import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// One legal document: its title, version, date and text.
class LegalDocumentModel {
  const LegalDocumentModel({
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.text,
  });

  final String title;
  final String version;
  final String effectiveDate;
  final String text;
}

/// `LegalDocumentsModel` (`contracts/signin.md`): the Terms and the Privacy
/// Policy. [preview] is the prototype's placeholder text; the app passes its
/// real documents.
class LegalDocumentsModel {
  const LegalDocumentsModel({required this.terms, required this.privacy});

  final LegalDocumentModel terms;
  final LegalDocumentModel privacy;

  static const preview = LegalDocumentsModel(
    terms: LegalDocumentModel(
      title: 'Orbit Terms of Service',
      version: '3',
      effectiveDate: '1 September 2026',
      text:
          'These terms explain how you may use Orbit and what we promise in '
          'return.\n\n1. Your account. You sign up with your phone number. '
          'Keep your password and your devices safe; anyone holding an '
          'unlocked, signed-in device can read your messages.\n\n2. Your '
          'messages. Messages and calls are end-to-end encrypted. The server '
          'stores them only until they are delivered and cannot read them.'
          '\n\n3. Acceptable use. Do not use Orbit to send spam, to harass '
          'people, or to break the law.\n\n4. Changes. We will tell you in '
          'the app before these terms change.',
    ),
    privacy: LegalDocumentModel(
      title: 'Orbit Privacy Policy',
      version: '4',
      effectiveDate: '1 September 2026',
      text:
          'This policy explains what Orbit keeps and why.\n\nWhat the server '
          'keeps: your phone number (to find you), your devices and their '
          'public keys, and encrypted messages until they are delivered.\n\n'
          'What it never sees: the content of your messages, calls, profile '
          'name, about line and pictures.\n\nContacts: numbers are hashed on '
          'your phone before any check; names never leave it.\n\nBackups: '
          'encrypted with a key only your devices hold.',
    ),
  );
}

/// The Terms and Privacy sheet (`legalSheet` in `js/screens/signin.js`):
/// 86% of the screen, the document's title with ×, "Version 3 · Effective
/// …" in mono 11px, the Terms / Privacy segment, and the text at 13.5px in
/// `--ink-2`, line height 1.65.
Future<void> showOrbitLegalSheet(
  BuildContext context, {
  LegalDocumentsModel docs = LegalDocumentsModel.preview,
  bool privacy = false,
}) => showOrbitSheet(
  context,
  // `height: 88%`, held to the sheet's `max-height: 86%`.
  heightFactor: 0.86,
  body: _Legal(docs: docs, privacy: privacy),
);

class _Legal extends StatefulWidget {
  const _Legal({required this.docs, required this.privacy});

  final LegalDocumentsModel docs;
  final bool privacy;

  @override
  State<_Legal> createState() => _LegalState();
}

class _LegalState extends State<_Legal> {
  late var _privacy = widget.privacy;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final d = _privacy ? widget.docs.privacy : widget.docs.terms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: OrbitText(
                  orbitTransform(d.title, t.displayTransform),
                  style: t.display(size: 18),
                ),
              ),
              const SizedBox(width: 8),
              OrbitIconButton(
                icon: OrbitIcons.x,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: OrbitText(
            'Version ${d.version} · Effective ${d.effectiveDate}',
            style: t.mono.style(size: 11, color: t.ink3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: OrbitSegmented(
            options: const [
              OrbitSegment(false, 'Terms', icon: OrbitIcons.fileText),
              OrbitSegment(true, 'Privacy', icon: OrbitIcons.shieldCheck),
            ],
            value: _privacy,
            onChanged: (v) => setState(() => _privacy = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
          child: OrbitText(
            d.text,
            style: t.font.style(
              size: OrbitType.small,
              color: t.ink2,
              height: 1.65,
            ),
          ),
        ),
      ],
    );
  }
}
