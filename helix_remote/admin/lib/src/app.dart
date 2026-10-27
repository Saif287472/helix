import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/auth/lock_screen.dart';
import 'package:helix_admin/src/features/auth/sign_in_screen.dart';
import 'package:helix_admin/src/features/shell/admin_shell.dart';
import 'package:helix_admin/src/services/admin_services.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The operator console. Light theme only: there is no dark theme to ask
/// for, so `themeMode` is pinned and no `darkTheme` is registered.
class HelixAdminApp extends StatefulWidget {
  const HelixAdminApp({super.key, required this.services});

  final AdminServices services;

  @override
  State<HelixAdminApp> createState() => _HelixAdminAppState();
}

class _HelixAdminAppState extends State<HelixAdminApp>
    with WidgetsBindingObserver {
  late final AdminSessionController _session;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _session = AdminSessionController(widget.services)
      ..addListener(_closeRoutesWhenSignedOut)
      ..start();
    WidgetsBinding.instance.addObserver(this);
  }

  /// App lock asks again after time in the background
  /// ([AdminSessionController.relockAfter]).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _session.backgrounded();
      case AppLifecycleState.resumed:
        _session.resumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Account pages and dialogs sit above the shell, not inside it: when the
  /// session ends they must not stay on screen over the sign-in form.
  void _closeRoutesWhenSignedOut() {
    if (_session.phase != SessionPhase.signedIn) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session
      ..removeListener(_closeRoutesWhenSignedOut)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminSessionScope(
      controller: _session,
      child: MaterialApp(
        navigatorKey: _navigator,
        title: 'Orbit Console',
        debugShowCheckedModeBanner: false,
        theme: HelixThemes.console(),
        themeMode: ThemeMode.light,
        builder: (context, child) => Semantics(
          container: true,
          label: 'Orbit Console',
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: child!,
          ),
        ),
        home: const _Gate(),
      ),
    );
  }
}

/// Chooses what to show for the session's phase.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = AdminSessionScope.of(context);
    return switch (session.phase) {
      SessionPhase.starting => const _Launching(),
      SessionPhase.locked => const LockScreen(),
      SessionPhase.signedOut => const SignInScreen(),
      // A new key per sign-in: nothing from an earlier session survives.
      SessionPhase.signedIn => AdminShell(
        key: ObjectKey(session.api),
        adminContext: session.context!,
      ),
    };
  }
}

/// What shows while the console reads its saved session: the mark and a
/// skeleton line, so the first frame is already the console's own.
class _Launching extends StatelessWidget {
  const _Launching();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Semantics(
        label: 'Starting Orbit Console',
        liveRegion: true,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 44,
              color: HelixConsoleColors.accent,
            ),
            SizedBox(height: 16),
            Text(
              'Orbit Console',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: HelixConsoleColors.text,
              ),
            ),
            SizedBox(height: 16),
            HelixSkeleton(width: 160, height: 14),
          ],
        ),
      ),
    ),
  );
}
