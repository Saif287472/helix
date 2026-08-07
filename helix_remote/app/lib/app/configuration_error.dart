part of '../main.dart';

class HelixRemoteConfigurationErrorApp extends StatelessWidget {
  const HelixRemoteConfigurationErrorApp({super.key, required this.message});

  final String message;

  /// A page, not an application — the shell is supplied by the caller.
  ///
  /// It wrapped itself in [HelixRemoteAppShell] and then read its own copy
  /// through `HelixLocalizations.of(context)`, which resolves against *this*
  /// build context: the one above the shell it was creating, and so above the
  /// Localizations scope. Same shape, same bug as HelixRemoteApp had.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(HelixLocalizations.of(context).appTitle)),
      body: Center(
        child: Padding(
          padding: HelixInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                HelixLocalizations.of(context).remoteConfigurationRequired,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
