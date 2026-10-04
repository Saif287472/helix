import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/security/app_settings.dart';

/// Applies the in-app text size (Settings > Chats > Font size) on top of the
/// phone's own.
///
/// It multiplies, never replaces or caps: somebody who needs the system size
/// at 200% and the app at "Large" gets both. Nothing in the app clamps text
/// scaling (a source-scan test keeps it that way).
class AppTextScale extends ConsumerWidget {
  const AppTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(fontScalePercentProvider).value ?? 100;
    if (percent == 100) return child;
    final media = MediaQuery.of(context);
    final system = media.textScaler.scale(100) / 100;
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(system * percent / 100),
      ),
      child: child,
    );
  }
}
