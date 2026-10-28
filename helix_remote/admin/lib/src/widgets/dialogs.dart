import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A short confirmation line at the bottom of the screen.
void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// A plain yes/no confirmation. True only when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Asks, then ends the admin session on the server and forgets it on this
/// device. Config's session card and the phone's system drawer both use it, so
/// the operator reads one warning about signing out.
Future<void> confirmAndSignOut(BuildContext context) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Sign out?',
    message:
        'This ends every admin session on the server, on this device and '
        'any other. You will need the admin password to sign in again.',
    action: 'Sign out',
  );
  if (confirmed && context.mounted) {
    await AdminSessionScope.read(context).signOut();
  }
}

/// What [showReasonDialog] returns when the operator confirms: the optional
/// reason (null when left empty), which goes to the audit log.
typedef Reason = ({String? text});

/// Asks to confirm an action with an optional reason. Null when cancelled.
/// With a [phrase], the action also needs it typed in full, as
/// [showTypedConfirmDialog] does (for actions that cannot be undone).
Future<Reason?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
  String? phrase,
}) => showDialog<Reason>(
  context: context,
  builder: (context) => _ReasonDialog(
    title: title,
    message: message,
    action: action,
    destructive: destructive,
    phrase: phrase,
  ),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.destructive,
    required this.phrase,
  });

  final String title;
  final String message;
  final String action;
  final bool destructive;
  final String? phrase;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  final _typed = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phrase = widget.phrase;
    final confirmed = phrase == null || _typed.text.trim() == phrase;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: HelixSpace.md),
          TextField(
            controller: _reason,
            maxLength: AdminActionRequest.maxReasonLength,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (optional, kept in the audit log)',
              border: OutlineInputBorder(),
            ),
          ),
          if (phrase != null) ...[
            const SizedBox(height: HelixSpace.sm),
            TextField(
              controller: _typed,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Type $phrase to confirm',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: confirmed
              ? () {
                  final text = _reason.text.trim();
                  Navigator.pop<Reason>(context, (
                    text: text.isEmpty ? null : text,
                  ));
                }
              : null,
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// A confirmation that needs [phrase] typed in full, for actions that cannot
/// be undone. True only when confirmed.
Future<bool> showTypedConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _TypedConfirmDialog(
        title: title,
        message: message,
        phrase: phrase,
        action: action,
      ),
    ) ??
    false;

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.phrase,
    required this.action,
  });

  final String title;
  final String message;
  final String phrase;
  final String action;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matches = _typed.text.trim() == widget.phrase;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: HelixSpace.md),
          TextField(
            controller: _typed,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Type ${widget.phrase} to confirm',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Shows a secret exactly once (an invite or recovery code). The code lives
/// only in this dialog: it is not stored, not logged and not shown again.
Future<void> showCodeOnceDialog(
  BuildContext context, {
  required String title,
  required String code,
  required DateTime expiresAt,
  required String explanation,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  // Back, the system gesture and Escape pop the route whatever the barrier
  // says: the only way out is a button, so the one copy of the code is never
  // lost to a gesture (AUD-17b-2).
  builder: (context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(explanation),
          const SizedBox(height: HelixSpace.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HelixSpace.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: HelixRadius.card,
            ),
            child: SelectableText(
              code,
              key: const Key('shown-once-code'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.xs),
          Text(
            'Expires ${formatTime(expiresAt)}. It is shown only now.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await copySecret(code);
            if (context.mounted) {
              showMessage(context, 'Code copied. It is cleared in a minute.');
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy code'),
        ),
        TextButton(
          key: const Key('discard-code'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Discard code'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  ),
);

/// Plain information with one button.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  ),
);

/// Puts a secret (a recovery code, good for 48 hours) on the clipboard and takes
/// it back a minute later if the clipboard still holds it: Windows keeps a
/// clipboard history, and any app may read the clipboard.
/// How long [copySecret] leaves a secret on the clipboard (a test shortens it).
@visibleForTesting
Duration secretClipboardLifetime = const Duration(minutes: 1);

Future<void> copySecret(String secret) async {
  await Clipboard.setData(ClipboardData(text: secret));
  // Not tied to the dialog: closing it must not leave the code there.
  Timer(secretClipboardLifetime, () async {
    try {
      final held = await Clipboard.getData(Clipboard.kTextPlain);
      if (held?.text == secret) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } on Object {
      // The platform may refuse a background read; the copy simply stays.
    }
  });
}
