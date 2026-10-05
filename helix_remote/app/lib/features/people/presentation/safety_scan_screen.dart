import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Scans the QR code on the other person's safety-number screen.
///
/// The code is the same bytes on both phones, so it matches only when both of
/// you computed the number from the same two keys. A match marks the chat
/// verified; a mismatch says so and keeps scanning, because the usual cause is
/// pointing at the wrong code.
class SafetyScanScreen extends ConsumerStatefulWidget {
  const SafetyScanScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<SafetyScanScreen> createState() => _SafetyScanScreenState();
}

class _SafetyScanScreenState extends ConsumerState<SafetyScanScreen> {
  bool _busy = false;

  Future<void> _onText(String text) async {
    if (_busy) return;
    _busy = true;
    try {
      final number = await ref.read(
        safetyNumberProvider(widget.accountId).future,
      );
      if (!mounted) return;
      if (number != null && number.matchesQrText(text)) {
        await ref
            .read(contactInfoActionsProvider)
            .setVerified(widget.accountId, verified: true);
        if (!mounted) return;
        showHelixSnackBar(context, 'Verified. Your chat is private.');
        Navigator.of(context).pop();
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('That code does not match'),
          content: const Text(
            'Make sure you are scanning the code on this person\'s own '
            'safety number screen. If it still does not match, do not trust '
            'this chat until you have compared the numbers another way.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scanner = ref.watch(qrScannerBuilderProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan code')),
      body: ColoredBox(
        color: scheme.inverseSurface,
        child: scanner == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This device has no camera to scan with. Compare the '
                    'numbers on both phones instead.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: HelixScrimColors.onBackdrop),
                  ),
                ),
              )
            : HelixQrScanFrame(
                hint: 'Point the camera at the code on their phone',
                child: scanner(context, _onText),
              ),
      ),
    );
  }
}
