import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/people/application/contact_info.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: scans the QR code on the other person's safety-number screen,
/// drawn by `orbit_ui`'s Scan code.
///
/// The code is the same bytes on both phones, so it matches only when both
/// of you computed the number from the same two keys. A match marks the chat
/// verified; a mismatch says so and keeps scanning, because the usual cause
/// is pointing at the wrong code.
class SafetyScanScreen extends ConsumerWidget {
  const SafetyScanScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanner = ref.watch(qrScannerBuilderProvider);
    return orbit.ScanCodeScreen(
      model: orbit.ScanCodeModel(hasCamera: scanner != null),
      actions: orbit.ScanCodeActions(
        onCode: (text) => ref
            .read(contactInfoActionsProvider)
            .checkScannedCode(accountId, text),
      ),
      // The camera's own refusal ("The camera is not available…") is drawn
      // by the scanner, inside the frame.
      camera: scanner == null
          ? null
          : (context, onCode) => scanner(context, onCode),
    );
  }
}
