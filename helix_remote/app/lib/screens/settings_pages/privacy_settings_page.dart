import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/settings_pages/settings_page_kit.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Who can see what about you, read receipts, disappearing messages and
/// blocked contacts.
///
/// Every control here is saved (see RemoteMessagingService.updatePrivacy and
/// setReadReceiptsEnabled) and presence visibility is synced to the server,
/// which enforces it for other people.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key, required this.messagingService});

  final RemoteMessagingService messagingService;

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  RemoteMessagingService get _ms => widget.messagingService;

  static const _visibilityOptions = [
    SettingsOption('EVERYONE', 'Everyone'),
    SettingsOption('CONTACTS', 'My contacts'),
    SettingsOption('NOBODY', 'Nobody'),
  ];

  static String _visibilityLabel(String value) => _visibilityOptions
      .firstWhere((o) => o.value == value, orElse: () => _visibilityOptions[1])
      .label;

  static const _disappearingOptions = [
    SettingsOption(0, 'Off'),
    SettingsOption(86400, '24 hours'),
    SettingsOption(604800, '7 days'),
    SettingsOption(7776000, '90 days'),
  ];

  static String disappearingLabel(int seconds) => _disappearingOptions
      .firstWhere(
        (o) => o.value == seconds,
        orElse: () =>
            SettingsOption(seconds, '${(seconds / 86400).round()} days'),
      )
      .label;

  void _updatePrivacy({
    bool? discoverable,
    String? presence,
    String? lastSeen,
  }) {
    final current = _ms.privacySettings;
    _ms.updatePrivacy(
      RemotePrivacySettings(
        searchDiscoverable: discoverable ?? current.searchDiscoverable,
        presenceVisibility: presence ?? current.presenceVisibility,
        lastSeenVisibility: lastSeen ?? current.lastSeenVisibility,
      ),
    );
    setState(() {});
  }

  Future<void> _pickVisibility({
    required String title,
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final picked = await pickSettingsOption(
      context,
      title: title,
      current: current,
      options: _visibilityOptions,
    );
    if (picked != null && picked != current) onPicked(picked);
  }

  Future<void> _pickDisappearing() async {
    final current = _ms.db.getAccountDefaultDisappearingSeconds();
    final picked = await pickSettingsOption(
      context,
      title: 'Default timer for new chats',
      current: current,
      options: _disappearingOptions,
    );
    if (picked == null || picked == current) return;
    _ms.db.setAccountDefaultDisappearingSeconds(picked);
    setState(() {});
  }

  Future<void> _applyStrictPreset() async {
    final preview = _ms.db.strictAccountSettingsPreview();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Strict account settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in preview.entries)
              Padding(
                padding: HelixInsets.symmetric(vertical: 2),
                child: Text('${entry.key}: ${entry.value}'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _ms.db.applyStrictAccountSettingsPreset();
    _updatePrivacy(discoverable: false, presence: 'NOBODY', lastSeen: 'NOBODY');
    _ms.setReadReceiptsEnabled(false);
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Strict account settings')));
  }

  @override
  Widget build(BuildContext context) {
    final privacy = _ms.privacySettings;
    final blocked = _ms.db
        .getContacts()
        .where((c) => c.status == 'Blocked')
        .length;
    return SettingsPage(
      title: 'Privacy',
      children: [
        SettingsSection(
          title: 'Who can see',
          footer:
              'If you hide your online status or last seen, you can\'t see '
              'other people\'s either.',
          children: [
            SettingsTile(
              icon: Icons.circle_outlined,
              color: HelixColorTokens.cFF2FA84F,
              title: 'Online status',
              value: _visibilityLabel(privacy.presenceVisibility),
              onTap: () => _pickVisibility(
                title: 'Who can see when you\'re online',
                current: privacy.presenceVisibility,
                onPicked: (v) => _updatePrivacy(presence: v),
              ),
            ),
            SettingsTile(
              icon: Icons.schedule,
              color: HelixColorTokens.cFF0EA5E9,
              title: 'Last seen',
              value: _visibilityLabel(privacy.lastSeenVisibility),
              onTap: () => _pickVisibility(
                title: 'Who can see your last seen',
                current: privacy.lastSeenVisibility,
                onPicked: (v) => _updatePrivacy(lastSeen: v),
              ),
            ),
            SettingsSwitchTile(
              icon: Icons.person_search_outlined,
              color: HelixColorTokens.cFF5B6EE1,
              title: 'Findable by phone number',
              subtitle: 'People who have your number can find you on Helix',
              value: privacy.searchDiscoverable,
              onChanged: (v) => _updatePrivacy(discoverable: v),
            ),
          ],
        ),
        SettingsSection(
          title: 'Messages',
          children: [
            SettingsSwitchTile(
              icon: Icons.done_all,
              color: HelixColorTokens.cFF3B82F6,
              title: 'Read receipts',
              subtitle:
                  'Let people know when you\'ve read their messages. When off, '
                  'you won\'t see theirs either.',
              value: _ms.readReceiptsEnabled,
              onChanged: (v) {
                _ms.setReadReceiptsEnabled(v);
                setState(() {});
              },
            ),
            SettingsTile(
              icon: Icons.timer_outlined,
              color: HelixColorTokens.cFF7C3AED,
              title: 'Disappearing messages',
              subtitle: 'Default timer for new chats',
              value: disappearingLabel(
                _ms.db.getAccountDefaultDisappearingSeconds(),
              ),
              onTap: _pickDisappearing,
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsTile(
              icon: Icons.block,
              color: HelixColorTokens.cFFDC2626,
              title: 'Blocked contacts',
              value: '$blocked',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlockedContactsPage(messagingService: _ms),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        SettingsSection(
          title: 'Strict privacy',
          footer:
              'The strict preset hides your online status and last seen from '
              'everyone, stops read receipts and makes you unfindable by '
              'number. You can change each setting back afterwards.',
          children: [
            SettingsTile(
              icon: Icons.shield_outlined,
              color: HelixColorTokens.cFF4F46E5,
              title: 'Apply strict privacy',
              onTap: _applyStrictPreset,
            ),
          ],
        ),
      ],
    );
  }
}

/// Everyone you've blocked, with a way to unblock them.
class BlockedContactsPage extends StatefulWidget {
  const BlockedContactsPage({super.key, required this.messagingService});

  final RemoteMessagingService messagingService;

  @override
  State<BlockedContactsPage> createState() => _BlockedContactsPageState();
}

class _BlockedContactsPageState extends State<BlockedContactsPage> {
  @override
  Widget build(BuildContext context) {
    final blocked = widget.messagingService.db
        .getContacts()
        .where((c) => c.status == 'Blocked')
        .toList();
    return SettingsPage(
      title: 'Blocked contacts',
      children: [
        SettingsSection(
          footer:
              'Blocked people can\'t message or call you, and won\'t see your '
              'online status or profile updates.',
          children: [
            if (blocked.isEmpty)
              const SettingsTile(
                icon: Icons.check,
                color: HelixColorTokens.cFF2FA84F,
                title: 'No one is blocked',
              )
            else
              for (final contact in blocked)
                SettingsTile(
                  icon: Icons.person_off_outlined,
                  color: HelixColorTokens.cFFDC2626,
                  title: contact.nickname.isEmpty
                      ? contact.peerAccountId
                      : contact.nickname,
                  trailing: TextButton(
                    onPressed: () {
                      widget.messagingService.unblockContact(
                        contact.peerAccountId,
                      );
                      setState(() {});
                    },
                    child: const Text('Unblock'),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
