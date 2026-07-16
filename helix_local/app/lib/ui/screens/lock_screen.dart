// lib/ui/screens/lock_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:helix/ui/widgets/app_logo.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    // Delay slightly to ensure layout is complete before invoking the auth dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _authenticate() async {
    setState(() => _isAuthenticating = true);
    try {
      final authenticated = await auth.authenticate(
        localizedReason: 'Unlock Helix',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (authenticated && mounted) {
        Navigator.of(context).pop();
      }
    } on PlatformException catch (e) {
      debugPrint('Authentication error: $e');
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back gesture from dismissing the lock screen
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 72),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isAuthenticating ? null : _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock with biometrics'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
