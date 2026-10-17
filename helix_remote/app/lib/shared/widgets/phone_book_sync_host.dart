import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';

/// Keeps the people the phone's contacts know in step with Helix.
///
/// It asks [PhoneBookSyncController.syncIfDue] once the device is signed in
/// (on start, when the engine has opened, and after a fresh sign-in), when the
/// app comes back to the foreground, every hour while it is open, and (after a
/// short pause, so a burst of edits is one sync) when the address book changes. The
/// controller decides whether a sync is actually due: it spends the daily
/// discovery budget, so it will not run more than twice a day by itself, and
/// not at all without the permission (which this never asks for).
class PhoneBookSyncHost extends ConsumerStatefulWidget {
  const PhoneBookSyncHost({super.key, required this.child});

  /// How often an open app checks.
  static const tick = Duration(hours: 1);

  /// How long the address book must be quiet before a change is synced.
  static const settle = Duration(seconds: 30);

  final Widget child;

  @override
  ConsumerState<PhoneBookSyncHost> createState() => _PhoneBookSyncHostState();
}

class _PhoneBookSyncHostState extends ConsumerState<PhoneBookSyncHost>
    with WidgetsBindingObserver {
  Timer? _tick;
  Timer? _settle;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(PhoneBookSyncHost.tick, (_) => _sync());
    _changes = ref.read(contactsAccessProvider).changes.listen((_) {
      _settle?.cancel();
      _settle = Timer(
        PhoneBookSyncHost.settle,
        () => _sync(addressBookChanged: true),
      );
    });
    // On the first frame the engine is usually still opening the database,
    // so the start-up sync is the moment the device becomes signed in (a
    // fresh sign-in or registration is that moment too).
    ref.listenManual(authStateProvider, (previous, next) {
      if (next.value == AppAuthState.ready &&
          previous?.value != AppAuthState.ready) {
        _sync();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _settle?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync({bool addressBookChanged = false}) async {
    if (!mounted) return;
    // Only a signed-in device has anything to match against.
    if (ref.read(authStateProvider).value != AppAuthState.ready) return;
    await ref.read(contactsPermissionProvider.notifier).refresh();
    await ref
        .read(phoneBookSyncProvider.notifier)
        .syncIfDue(addressBookChanged: addressBookChanged);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
