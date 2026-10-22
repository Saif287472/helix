import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: scans the share code from the other person's You page and opens
/// the chat it names.
///
/// The code carries the same link they would send you as text, so scanning it
/// is a shortcut for tapping the link: the `~name` inside it is looked up with
/// this account's session, which is what honours "Find me by ~name" and
/// blocking. Anything else in the frame is refused without a request.
class ScanChatScreen extends ConsumerWidget {
  const ScanChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanner = ref.watch(qrScannerBuilderProvider);
    return orbit.ScanCodeScreen(
      model: orbit.ScanCodeModel(
        mode: orbit.ScanMode.contact,
        hasCamera: scanner != null,
      ),
      actions: orbit.ScanCodeActions(
        onCode: (text) => ref.read(peopleActionsProvider).openScannedCode(text),
      ),
      // The camera's own refusal is drawn by the scanner, inside the frame.
      camera: scanner == null
          ? null
          : (context, onCode) => scanner(context, onCode),
    );
  }
}
