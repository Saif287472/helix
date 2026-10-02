import 'package:flutter/material.dart';
import 'package:helix_remote/features/home/application/home_tab.dart';
import 'package:helix_remote/features/home/presentation/home_screen.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Calls: recent calls, and the button that starts one.
///
/// Calls arrive in two later phases - the engine's call state is C4, and the
/// call screen, foreground service and audio routing are A3 - so A1 ships the
/// shell honestly empty rather than a dead button. People can already search
/// for someone from here; that lands with A3 too.
class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeTabScaffold(
      title: 'Calls',
      tab: HomeTab.calls,
      child: HelixEmptyState(
        icon: Icons.call_outlined,
        title: 'No calls yet',
        message: 'Calls you make and receive will show up here.',
      ),
    );
  }
}
