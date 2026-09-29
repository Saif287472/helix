import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/account_restriction.dart';
import 'package:url_launcher/url_launcher.dart';

/// Draws account restrictions over every route.
///
/// * Suspended: a banner above the app, and a dialog each time the server
///   refuses an action - the user stays signed in and can keep reading.
/// * Blocked: a full screen with the only three ways forward - contact
///   support, sign in with a different number, or leave.
///
/// Sits in the `MaterialApp.builder`, above the navigator, so [navigatorKey]
/// is what lets it open the refusal dialog over whatever route is showing.
class AccountRestrictionGate extends StatefulWidget {
  const AccountRestrictionGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AccountRestrictionGate> createState() => _AccountRestrictionGateState();
}

class _AccountRestrictionGateState extends State<AccountRestrictionGate> {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    AccountRestrictionState.refusedAttempts.addListener(_onRefused);
  }

  @override
  void dispose() {
    AccountRestrictionState.refusedAttempts.removeListener(_onRefused);
    super.dispose();
  }

  Future<void> _onRefused() async {
    final navContext = widget.navigatorKey.currentContext;
    // One dialog at a time: a failed send can retry, and several background
    // calls can be refused together.
    if (navContext == null || _dialogOpen) return;
    _dialogOpen = true;
    await showDialog<void>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block_outlined),
        title: const Text('Account suspended'),
        content: Text(
          "This isn't available while your account is suspended.\n\n"
          '${_contactLine()}',
        ),
        actions: [
          if (AccountRestrictionState.serverIsGlobal)
            TextButton(
              onPressed: () => _contactSupport(ctx),
              child: const Text('Contact support'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccountRestriction>(
      valueListenable: AccountRestrictionState.restriction,
      builder: (context, restriction, _) {
        switch (restriction) {
          case AccountRestriction.none:
            return widget.child;
          case AccountRestriction.suspended:
            return Column(
              children: [
                const _SuspendedBanner(),
                Expanded(
                  // The banner already consumed the status-bar inset.
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: widget.child,
                  ),
                ),
              ],
            );
          case AccountRestriction.blocked:
            return const _BlockedScreen();
        }
      },
    );
  }
}

String _contactLine() => AccountRestrictionState.serverIsGlobal
    ? 'Contact Helix support to find out why and how to get access back.'
    : 'Contact the admin of this server to find out why and how to get access back.';

/// Opens the mail app addressed to Helix support, or copies the address when
/// no mail app can take it.
Future<void> _contactSupport(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = 'Support email copied';
  final uri = Uri(
    scheme: 'mailto',
    path: kHelixSupportEmail,
    query: 'subject=Helix account access',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  await Clipboard.setData(const ClipboardData(text: kHelixSupportEmail));
  messenger?.showSnackBar(
    SnackBar(content: Text('$copied: $kHelixSupportEmail')),
  );
}

class _SuspendedBanner extends StatelessWidget {
  const _SuspendedBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.block_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Your account is suspended. You can still read messages, but you "
                  "can't send messages, add contacts or make calls. "
                  '${_contactLine()}',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              if (AccountRestrictionState.serverIsGlobal)
                TextButton(
                  onPressed: () => _contactSupport(context),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  child: const Text('Contact support'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.block, size: 56, color: scheme.error),
                  const SizedBox(height: 20),
                  Text(
                    'This number is blocked',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This phone number has been permanently blocked on this server, and '
                    'the account that used it has been removed.\n\n'
                    '${_contactLine()}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (AccountRestrictionState.serverIsGlobal) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.mail_outline),
                      onPressed: () => _contactSupport(context),
                      label: const Text('Contact support'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    icon: const Icon(Icons.phone_iphone),
                    // The session was purged when the block was detected, so
                    // lifting this screen reveals onboarding underneath.
                    onPressed: () => AccountRestrictionState.restriction.value =
                        AccountRestriction.none,
                    label: const Text('Sign in with a different number'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.exit_to_app),
                    onPressed: () => SystemNavigator.pop(),
                    label: const Text('Leave the app'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
