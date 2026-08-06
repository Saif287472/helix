part of '../main.dart';

class HelixRemoteConfigurationErrorApp extends StatelessWidget {
  const HelixRemoteConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return HelixRemoteAppShell(
      home: Scaffold(
        appBar: AppBar(title: const Text('Helix Remote')),
        body: Center(
          child: Padding(
            padding: HelixInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_outlined, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Remote configuration required',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
