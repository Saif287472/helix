part of '../contact_info_screen.dart';

extension _ContactInfoActions on _ContactInfoScreenState {
  String _profileSubtitle() {
    final peer = _peerAccountId;
    if (peer == null || peer.isEmpty) return 'Helix Remote contact';
    return 'Helix contact';
  }

  String _memberSummary(RemoteConversation group) {
    final members = _viewModel.memberIds(
      group.conversationId,
    );
    if (members.isEmpty) return 'No members';
    final names = members.map((id) {
      if (id == _viewModel.currentAccountId) return 'You';
      final convId = _viewModel.conversationIdForPeer(id);
      if (convId == null) return 'Helix contact';
      return _viewModel.peerDisplayName(convId) ?? 'Helix contact';
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
    _viewModel.setPrivacy(
      widget.conversationId,
      next,
    );
    _update(() => _privacy = next);
  }

  void _setChatLocked(bool value) {
    _viewModel.setLocked(
      widget.conversationId,
      locked: value,
    );
    _update(() {
      _privacy = _viewModel.privacy(widget.conversationId);
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
    _viewModel.setDisappearingPolicy(
      widget.conversationId,
      selected,
    );
    _update(() {
      _privacy = _viewModel.privacy(widget.conversationId);
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
    _viewModel.setPrivacy(
      widget.conversationId,
      next,
    );
    _update(() => _privacy = next);
    Navigator.pop(sheetContext);
  }

  Future<void> _createGroupWithContact() async {
    final peer = _peerAccountId;
    final groupService = widget.groupService;
    final current = _viewModel.currentAccountId;
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
    final current = _viewModel.currentAccountId;
    if (peer == null || groupService == null || current == null) return;
    final groups = _viewModel.conversations().where((group) {
      if (!_isGroupConversation(group)) return false;
      final members = _viewModel.memberIds(
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
    _viewModel.setFavorite(
      widget.conversationId,
      favorite: !_isFavorite,
    );
    unawaited(_load());
  }

  void _addToList() {
    final listId = 'favorites';
    try {
      _viewModel.addToList(
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
    _viewModel.clearChat(widget.conversationId);
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
    _viewModel.blockContact(peer);
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
    _viewModel.reportContact(
      accountId: peer,
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
    _viewModel.saveNickname(accountId: peer, nickname: name);
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
