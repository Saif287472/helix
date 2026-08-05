import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BackupTab extends StatelessWidget {
  const BackupTab({
    super.key,
    required this.isLoading,
    required this.onTriggerBackup,
  });

  final bool isLoading;
  final VoidCallback onTriggerBackup;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.settings_backup_restore,
                    size: 64,
                    color: Color(0xFF8A2BE2),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Automated Maintenance & Snapshot Backups',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Creates a clean snapshot of the server database using '
                    'SQLite "VACUUM INTO". File is saved in the backups '
                    'directory.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : onTriggerBackup,
                    icon: const Icon(Icons.backup),
                    label: const Text('TRIGGER SNAPSHOT BACKUP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2BE2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
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
