import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/backup_screen.dart';
import 'package:helix_remote/screens/device_management_screen.dart';
import 'package:helix_remote/screens/groups_screen.dart';
import 'package:helix_remote/screens/privacy_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.root,
    required this.messagingService,
  });

  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Backup & Restore'),
              subtitle: const Text('Export or restore your data'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BackupScreen(
                    db: root.database,
                    restClient: root.restClient,
                    tempDir: root.devConfig.attachmentCacheDir,
                  ),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('Device Management'),
              subtitle: const Text('View and manage connected devices'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DeviceManagementScreen(restClient: root.restClient),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: const Text('Privacy & Account'),
              subtitle: const Text('Export data or delete your account'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivacyScreen(
                    restClient: root.restClient,
                    messagingService: messagingService,
                  ),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Groups'),
              subtitle: const Text('Manage your group conversations'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupsScreen(
                    groupService: root.groupService,
                    messagingService: messagingService,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
