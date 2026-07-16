import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    super.key,
    required this.conversationId,
    required this.messagingService,
    this.groupService,
    this.callsAvailable = false,
    this.onStartAudioCall,
    this.onStartVideoCall,
    this.onStartSearch,
  });

  final String conversationId;
  final RemoteMessagingService messagingService;
  final RemoteGroupService? groupService;
  final bool callsAvailable;
  final VoidCallback? onStartAudioCall;
  final VoidCallback? onStartVideoCall;
  final VoidCallback? onStartSearch;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  List<RemoteDecryptedMessage> _messages = const [];
  List<RemoteConversation> _sharedGroups = const [];
  RemoteConversationPrivacy _privacy = const RemoteConversationPrivacy();
  RemoteStorageSummary? _storage;
  RemoteConversation? _conversation;
  String? _peerAccountId;
  bool _loaded = false;

  String get _displayName =>
      widget.messagingService.peerDisplayName(widget.conversationId) ??
      _conversation?.title ??
      'Helix contact';

  String get _initial {
    final value = _displayName.trim();
    if (value.isEmpty) return 'H';
    return value.characters.first.toUpperCase();
  }

  bool get _isFavorite => _conversation?.isFavorite == true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final conversations = widget.messagingService.conversationList();
    final conversation = conversations
        .where((c) => c.conversationId == widget.conversationId)
        .firstOrNull;
    final peer = widget.messagingService.peerAccountIdForConversation(
      widget.conversationId,
    );
    final groups = <RemoteConversation>[];
    if (peer != null) {
      for (final group in conversations.where(_isGroupConversation)) {
        final members = widget.messagingService.conversationMemberIds(
          group.conversationId,
        );
        if (members.contains(peer)) groups.add(group);
      }
    }
    final messages = await widget.messagingService.messageHistory(
      widget.conversationId,
      limit: 160,
    );
    if (!mounted) return;
    setState(() {
      _conversation = conversation;
      _peerAccountId = peer;
      _sharedGroups = groups;
      _messages = messages;
      _privacy = widget.messagingService.db.getConversationPrivacy(
        widget.conversationId,
      );
      _storage = widget.messagingService.storageSummary(widget.conversationId);
      _loaded = true;
    });
  }

  bool _isGroupConversation(RemoteConversation conversation) {
    final type = conversation.type.toUpperCase();
    return type == 'GROUP';
  }

  List<RemoteDecryptedMessage> get _mediaMessages {
    return _messages
        .where((message) {
          final attachment = message.media?.attachment ?? message.attachment;
          return attachment != null;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final pageColor = dark ? const Color(0xFF0B0B0C) : const Color(0xFFF4F5F7);
    final sectionColor = dark ? const Color(0xFF171719) : cs.surface;

    return Scaffold(
      backgroundColor: pageColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 398,
              elevation: 0,
              scrolledUnderElevation: 0.6,
              backgroundColor: cs.surface,
              foregroundColor: cs.onSurface,
              leading: const BackButton(),
              titleSpacing: 0,
              title: _CollapsedTitle(name: _displayName, initial: _initial),
              actions: [_OverflowMenu(onSelected: _handleOverflow)],
              flexibleSpace: FlexibleSpaceBar(
                background: _ProfileHeader(
                  name: _displayName,
                  subtitle: _profileSubtitle(),
                  initial: _initial,
                  onAvatarTap: _openProfileImage,
                  onAudio: _startAudio,
                  onVideo: _startVideo,
                  onSearch: _startSearch,
                ),
              ),
            ),
            if (!_loaded)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: cs.primary),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: _MediaSection(
                  color: sectionColor,
                  messages: _mediaMessages,
                  onOpen: _openMediaBrowser,
                ),
              ),
              SliverToBoxAdapter(
                child: _Section(
                  color: sectionColor,
                  children: [
                    _InfoRow(
                      icon: Icons.photo_library_outlined,
                      title: 'Manage storage',
                      subtitle: _formatBytes(_storage?.totalBytes ?? 0),
                      onTap: _showStorageDetails,
                    ),
                    _InfoRow(
                      icon: Icons.notifications_none_outlined,
                      title: 'Notifications',
                      onTap: () => _showSoon('Notifications'),
                    ),
                    _InfoRow(
                      icon: Icons.image_outlined,
                      title: 'Media visibility',
                      subtitle: _privacy.automaticMediaSaveAllowed
                          ? 'Visible in device media'
                          : 'Hidden from device media',
                      trailing: Switch.adaptive(
                        value: _privacy.automaticMediaSaveAllowed,
                        onChanged: _setMediaVisibility,
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: _Section(
                  color: sectionColor,
                  children: [
                    _InfoRow(
                      icon: Icons.lock_outline,
                      title: 'Encryption',
                      subtitle:
                          'Messages and calls are end-to-end encrypted. Tap to verify.',
                      onTap: _showSecurityCode,
                    ),
                    _InfoRow(
                      icon: Icons.timer_outlined,
                      title: 'Disappearing messages',
                      subtitle: _disappearingLabel(
                        _privacy.disappearingSeconds,
                      ),
                      onTap: _showDisappearingPolicyDialog,
                    ),
                    _InfoRow(
                      icon: Icons.lock_outline,
                      title: 'Chat lock',
                      subtitle: 'Lock and hide this chat on this device.',
                      trailing: Switch.adaptive(
                        value: _privacy.isLocked,
                        onChanged: _setChatLocked,
                      ),
                    ),
                    _InfoRow(
                      icon: Icons.shield_outlined,
                      title: 'Advanced chat privacy',
                      subtitle: _advancedPrivacyLabel(),
                      onTap: _showAdvancedPrivacy,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: _CommonGroupsSection(
                  color: sectionColor,
                  contactName: _displayName,
                  groups: _sharedGroups,
                  memberSummary: _memberSummary,
                  canManageGroups:
                      widget.groupService != null && _peerAccountId != null,
                  onCreateGroup: _createGroupWithContact,
                  onAddToGroup: _addToExistingGroup,
                ),
              ),
              SliverToBoxAdapter(
                child: _Section(
                  color: sectionColor,
                  children: [
                    _InfoRow(
                      icon: _isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      title: _isFavorite
                          ? 'Remove from Favorites'
                          : 'Add to Favorites',
                      onTap: _toggleFavorite,
                    ),
                    _InfoRow(
                      icon: Icons.library_add_outlined,
                      title: 'Add to list',
                      onTap: _addToList,
                    ),
                    _InfoRow(
                      icon: Icons.remove_circle_outline,
                      title: 'Clear chat',
                      onTap: _confirmClearChat,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: _Section(
                  color: sectionColor,
                  children: [
                    _InfoRow(
                      icon: Icons.block,
                      title: 'Block $_displayName',
                      destructive: true,
                      onTap: _confirmBlock,
                    ),
                    _InfoRow(
                      icon: Icons.thumb_down_alt_outlined,
                      title: 'Report $_displayName',
                      destructive: true,
                      onTap: _confirmReport,
                    ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
        ),
      ),
    );
  }

  String _profileSubtitle() {
    final peer = _peerAccountId;
    if (peer == null || peer.isEmpty) return 'Helix Remote contact';
    return 'Helix contact';
  }

  String _memberSummary(RemoteConversation group) {
    final members = widget.messagingService.conversationMemberIds(
      group.conversationId,
    );
    if (members.isEmpty) return 'No members';
    final names = members.map((id) {
      if (id == widget.messagingService.currentAccountId) return 'You';
      final convId = widget.messagingService.conversationIdForPeer(id);
      if (convId == null) return 'Helix contact';
      return widget.messagingService.peerDisplayName(convId) ?? 'Helix contact';
    }).toList();
    return names.take(6).join(', ');
  }

  Future<void> _handleOverflow(String value) async {
    switch (value) {
      case 'share':
        await Clipboard.setData(ClipboardData(text: _displayName));
        _toast('Profile name copied');
      case 'edit':
        await _editNickname();
      case 'verify':
        _showSecurityCode();
    }
  }

  void _startAudio() {
    if (!widget.callsAvailable) {
      _toast('Calls require TURN relay configuration');
      return;
    }
    widget.onStartAudioCall?.call();
  }

  void _startVideo() {
    if (!widget.callsAvailable) {
      _toast('Calls require TURN relay configuration');
      return;
    }
    widget.onStartVideoCall?.call();
  }

  void _startSearch() {
    widget.onStartSearch?.call();
    Navigator.of(context).maybePop();
  }

  void _openProfileImage() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Center(
            child: CircleAvatar(
              radius: 118,
              backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
              child: Text(
                _initial,
                style: Theme.of(ctx).textTheme.displayLarge?.copyWith(
                  color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMediaBrowser() {
    if (_mediaMessages.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Media, links, and docs',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _mediaMessages.take(12).length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (_, index) =>
                    _MediaThumb(message: _mediaMessages[index], large: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStorageDetails() {
    final storage = _storage;
    if (storage == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage storage',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _MetricLine(
                'Total chat storage',
                _formatBytes(storage.totalBytes),
              ),
              _MetricLine(
                'Downloaded media',
                _formatBytes(storage.downloadedBytes),
              ),
              _MetricLine('Attachments', '${storage.attachmentCount}'),
              _MetricLine(
                'Large attachments',
                '${storage.largeAttachmentCount}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setMediaVisibility(bool value) {
    final next = _privacy.copyWith(automaticMediaSaveAllowed: value);
    widget.messagingService.db.setConversationPrivacy(
      widget.conversationId,
      next,
    );
    setState(() => _privacy = next);
  }

  void _setChatLocked(bool value) {
    widget.messagingService.db.setConversationLocked(
      widget.conversationId,
      locked: value,
    );
    setState(() {
      _privacy = widget.messagingService.db.getConversationPrivacy(
        widget.conversationId,
      );
    });
  }

  Future<void> _showDisappearingPolicyDialog() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Disappearing messages'),
        children: [
          for (final option in const {
            0: 'Off',
            86400: '24 hours',
            604800: '7 days',
            7776000: '90 days',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, option.key),
              child: Text(option.value),
            ),
        ],
      ),
    );
    if (selected == null) return;
    widget.messagingService.db.setConversationDisappearingPolicy(
      widget.conversationId,
      selected,
    );
    setState(() {
      _privacy = widget.messagingService.db.getConversationPrivacy(
        widget.conversationId,
      );
    });
  }

  void _showSecurityCode() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify security code'),
        content: const Text(
          'Helix protects this chat with end-to-end encryption. Verify this '
          'contact on a trusted device before sharing sensitive information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showAdvancedPrivacy() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                value: _privacy.exportAllowed,
                title: const Text('Allow export'),
                onChanged: (value) =>
                    _updateAdvancedPrivacy(ctx, exportAllowed: value),
              ),
              SwitchListTile.adaptive(
                value: _privacy.forwardingAllowed,
                title: const Text('Allow forwarding'),
                onChanged: (value) =>
                    _updateAdvancedPrivacy(ctx, forwardingAllowed: value),
              ),
              SwitchListTile.adaptive(
                value: _privacy.externalSaveAllowed,
                title: const Text('Allow external save'),
                onChanged: (value) =>
                    _updateAdvancedPrivacy(ctx, externalSaveAllowed: value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateAdvancedPrivacy(
    BuildContext sheetContext, {
    bool? exportAllowed,
    bool? externalSaveAllowed,
    bool? forwardingAllowed,
  }) {
    final next = _privacy.copyWith(
      exportAllowed: exportAllowed,
      externalSaveAllowed: externalSaveAllowed,
      forwardingAllowed: forwardingAllowed,
    );
    widget.messagingService.db.setConversationPrivacy(
      widget.conversationId,
      next,
    );
    setState(() => _privacy = next);
    Navigator.pop(sheetContext);
  }

  Future<void> _createGroupWithContact() async {
    final peer = _peerAccountId;
    final groupService = widget.groupService;
    final current = widget.messagingService.currentAccountId;
    if (peer == null || groupService == null || current == null) return;
    final groupName = '$_displayName group';
    final groupId = 'group_${DateTime.now().microsecondsSinceEpoch}';
    groupService.createGroup(
      groupId: groupId,
      name: groupName,
      creatorId: current,
      initialMemberIds: [peer],
    );
    _toast('Group created');
    await _load();
  }

  Future<void> _addToExistingGroup() async {
    final peer = _peerAccountId;
    final groupService = widget.groupService;
    final current = widget.messagingService.currentAccountId;
    if (peer == null || groupService == null || current == null) return;
    final groups = widget.messagingService.conversationList().where((group) {
      if (!_isGroupConversation(group)) return false;
      final members = widget.messagingService.conversationMemberIds(
        group.conversationId,
      );
      return !members.contains(peer);
    }).toList();
    if (groups.isEmpty) {
      _toast('No available groups');
      return;
    }
    final group = await showModalBottomSheet<RemoteConversation>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                'Add to group',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final group in groups)
              ListTile(
                leading: CircleAvatar(child: Text(_groupInitial(group))),
                title: Text(group.title.isEmpty ? 'Group' : group.title),
                subtitle: Text(_memberSummary(group)),
                onTap: () => Navigator.pop(ctx, group),
              ),
          ],
        ),
      ),
    );
    if (group == null) return;
    groupService.inviteMember(
      groupId: group.conversationId,
      inviteId: groupService.generateId(),
      inviterId: current,
      inviteeId: peer,
    );
    _toast('Invite queued');
  }

  void _toggleFavorite() {
    widget.messagingService.favoriteConversation(
      widget.conversationId,
      favorite: !_isFavorite,
    );
    unawaited(_load());
  }

  void _addToList() {
    final listId = 'favorites';
    try {
      widget.messagingService.addConversationToCustomList(
        listId: listId,
        conversationId: widget.conversationId,
        sortOrder: DateTime.now().millisecondsSinceEpoch,
      );
      _toast('Added to list');
    } catch (_) {
      _toast('Lists are not configured yet');
    }
  }

  Future<void> _confirmClearChat() async {
    final ok = await _confirm(
      title: 'Clear chat?',
      message: 'This removes local messages from this conversation.',
      action: 'Clear',
      destructive: true,
    );
    if (!ok) return;
    widget.messagingService.clearChat(widget.conversationId);
    await _load();
    _toast('Chat cleared');
  }

  Future<void> _confirmBlock() async {
    final peer = _peerAccountId;
    if (peer == null) return;
    final ok = await _confirm(
      title: 'Block $_displayName?',
      message: 'This contact will no longer be able to message this device.',
      action: 'Block',
      destructive: true,
    );
    if (!ok) return;
    widget.messagingService.blockContact(peer);
    _toast('Contact blocked');
  }

  Future<void> _confirmReport() async {
    final peer = _peerAccountId;
    if (peer == null) return;
    final ok = await _confirm(
      title: 'Report $_displayName?',
      message: 'A safety report will be queued for Helix review.',
      action: 'Report',
      destructive: true,
    );
    if (!ok) return;
    widget.messagingService.reportAccount(
      subjectAccountId: peer,
      category: 'contact',
      reasonCode: 'user_reported',
      contextHash: widget.conversationId.hashCode.toRadixString(16),
    );
    _toast('Report queued');
  }

  Future<void> _editNickname() async {
    final peer = _peerAccountId;
    if (peer == null) return;
    final controller = TextEditingController(text: _displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    widget.messagingService.addContact(peerAccountId: peer, nickname: name);
    await _load();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(ctx).colorScheme.error,
                        foregroundColor: Theme.of(ctx).colorScheme.onError,
                      )
                    : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _advancedPrivacyLabel() {
    if (_privacy.exportAllowed &&
        _privacy.externalSaveAllowed &&
        _privacy.forwardingAllowed) {
      return 'Off';
    }
    return 'Limited';
  }

  String _disappearingLabel(int seconds) {
    return switch (seconds) {
      0 => 'Off',
      86400 => '24 hours',
      604800 => '7 days',
      7776000 => '90 days',
      _ => '$seconds seconds',
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} kB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _groupInitial(RemoteConversation group) {
    final title = group.title.trim();
    if (title.isEmpty) return 'G';
    return title.characters.first.toUpperCase();
  }

  void _showSoon(String label) {
    _toast('$label is not available yet');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.name, required this.initial});

  final String name;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.subtitle,
    required this.initial,
    required this.onAvatarTap,
    required this.onAudio,
    required this.onVideo,
    required this.onSearch,
  });

  final String name;
  final String subtitle;
  final String initial;
  final VoidCallback onAvatarTap;
  final VoidCallback onAudio;
  final VoidCallback onVideo;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(30, 72, 30, 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 72,
              backgroundColor: cs.primaryContainer,
              child: Text(
                initial,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeaderAction(
                  icon: Icons.call_outlined,
                  label: 'Audio',
                  onTap: onAudio,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeaderAction(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: onVideo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeaderAction(
                  icon: Icons.search,
                  label: 'Search',
                  onTap: onSearch,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cs.primary, size: 29),
              const SizedBox(height: 7),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(minWidth: 260),
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'share', child: Text('Share profile')),
        PopupMenuItem(value: 'edit', child: Text('Edit nickname')),
        PopupMenuItem(value: 'verify', child: Text('Verify security code')),
      ],
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.color,
    required this.messages,
    required this.onOpen,
  });

  final Color color;
  final List<RemoteDecryptedMessage> messages;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: color,
      padding: const EdgeInsets.fromLTRB(30, 18, 0, 16),
      child: Column(
        children: [
          InkWell(
            onTap: messages.isEmpty ? null : onOpen,
            child: Padding(
              padding: const EdgeInsets.only(right: 22),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Media, links, and docs',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${messages.length}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 98,
            child: messages.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No shared media yet',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 22),
                    itemCount: messages.take(18).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) =>
                        _MediaThumb(message: messages[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.message, this.large = false});

  final RemoteDecryptedMessage message;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final attachment = message.media?.attachment ?? message.attachment;
    final path = attachment?.localPath;
    final isImage =
        attachment?.mimeType.startsWith('image/') == true &&
        path != null &&
        File(path).existsSync();
    final icon = switch (message.media?.kind) {
      RemoteMediaContent.videoKind => Icons.play_arrow_rounded,
      RemoteMediaContent.voiceNoteKind => Icons.mic,
      _ when attachment?.mimeType.startsWith('video/') == true =>
        Icons.play_arrow_rounded,
      _ when attachment?.mimeType.startsWith('image/') == true =>
        Icons.image_outlined,
      _ => Icons.description_outlined,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: large ? null : 116,
        height: large ? null : 98,
        color: cs.surfaceContainerHighest,
        child: isImage
            ? Image.file(File(path), fit: BoxFit.cover)
            : Center(child: Icon(icon, color: cs.onSurfaceVariant, size: 32)),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: color,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 92,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.destructive = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = destructive ? cs.error : cs.onSurface;
    final subtitleColor = destructive ? cs.error : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 17, 30, 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: destructive ? cs.error : subtitleColor),
            const SizedBox(width: 43),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      color: titleColor,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: subtitleColor,
                        height: 1.18,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _CommonGroupsSection extends StatelessWidget {
  const _CommonGroupsSection({
    required this.color,
    required this.contactName,
    required this.groups,
    required this.memberSummary,
    required this.canManageGroups,
    required this.onCreateGroup,
    required this.onAddToGroup,
  });

  final Color color;
  final String contactName;
  final List<RemoteConversation> groups;
  final String Function(RemoteConversation group) memberSummary;
  final bool canManageGroups;
  final VoidCallback onCreateGroup;
  final VoidCallback onAddToGroup;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: color,
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              '${groups.length} ${groups.length == 1 ? 'Group' : 'Groups'} in common',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (canManageGroups) ...[
            _InfoRow(
              icon: Icons.group_outlined,
              title: 'Create group with $contactName',
              onTap: onCreateGroup,
            ),
            Divider(height: 1, indent: 92, color: cs.outlineVariant),
            _InfoRow(
              icon: Icons.group_add_outlined,
              title: 'Add to groups',
              subtitle: 'Add this contact to groups you are in.',
              onTap: onAddToGroup,
            ),
            Divider(height: 1, indent: 92, color: cs.outlineVariant),
          ],
          for (var i = 0; i < groups.length; i++) ...[
            _GroupRow(group: groups[i], summary: memberSummary(groups[i])),
            if (i != groups.length - 1)
              Divider(height: 1, indent: 92, color: cs.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.summary});

  final RemoteConversation group;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = group.title.isEmpty ? 'Group' : group.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 14, 30, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primary,
            child: Text(
              title.characters.first.toUpperCase(),
              style: TextStyle(
                color: cs.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
