part of '../groups_screen.dart';

extension _GroupsActionsAndBody on _GroupsScreenState {
  Future<void> _leaveGroup(String groupId, String title) async {
    final confirmed = await _confirm(
      title: 'Leave "$title"?',
      message: 'You will lose access to this group conversation.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) return;
    try {
      widget.groupService.leaveGroup(
        groupId: groupId,
        selfAccountId: _currentAccountId,
      );
      _update(() => _status = 'Left group "$title"');
      _reload();
    } catch (e) {
      _update(() => _status = 'Leave failed: $e');
    }
  }

  Future<void> _deleteGroup(String groupId, String title) async {
    final confirmed = await _confirm(
      title: 'Delete "$title"?',
      message: 'This will permanently delete the group for all members.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      widget.groupService.deleteGroup(groupId);
      _update(() => _status = 'Group "$title" deleted');
      _reload();
    } catch (e) {
      _update(() => _status = 'Delete failed: $e');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
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
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes);
  }

  String _policyLabel(String policy) {
    switch (policy) {
      case kGroupAddPolicyEveryone:
        return 'Everyone';
      case kGroupAddPolicyContacts:
        return 'Contacts only';
      case kGroupAddPolicyNobody:
        return 'Nobody (invite only)';
      default:
        return policy;
    }
  }

  String _notifPolicyLabel(String policy) {
    switch (policy) {
      case kGroupNotificationAll:
        return 'All messages';
      case kGroupNotificationMentionsOnly:
        return 'Mentions only';
      case kGroupNotificationAdminOnly:
        return 'Admin events only';
      case kGroupNotificationMuted:
        return 'Muted';
      default:
        return policy;
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  Widget _buildScreen(BuildContext context) {
    final groups = _groupRows();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createGroup,
            tooltip: 'Create group',
          ),
        ],
      ),
      body: Column(
        children: [
          // Pending admin join requests section.
          if (_joinRequests.isNotEmpty)
            ExpansionTile(
              title: Text('Join Requests (${_joinRequests.length})'),
              leading: const Icon(Icons.person_add_alt),
              initiallyExpanded: true,
              children: _joinRequests
                  .map(
                    (req) => ListTile(
                      title: Text('From: ${req['requester_id']}'),
                      subtitle: Text('Group: ${req['group_id']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Approve join request',
                            icon: const Icon(
                              Icons.check,
                              color: HelixStatusColors.positive,
                            ),
                            onPressed: () => _approveJoinRequest(req, true),
                          ),
                          IconButton(
                            tooltip: 'Decline join request',
                            icon: const Icon(
                              Icons.close,
                              color: HelixStatusColors.danger,
                            ),
                            onPressed: () => _approveJoinRequest(req, false),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          // Pending invites section.
          if (_invites.isNotEmpty)
            ExpansionTile(
              title: Text('Pending Invites (${_invites.length})'),
              leading: const Icon(Icons.mail_outline),
              initiallyExpanded: true,
              children: _invites
                  .map(
                    (inv) => ListTile(
                      title: Text('Group: ${inv['group_id']}'),
                      subtitle: Text('From: ${inv['inviter_id']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Accept invitation',
                            icon: const Icon(
                              Icons.check,
                              color: HelixStatusColors.positive,
                            ),
                            onPressed: () => _respondToInvite(inv, true),
                          ),
                          IconButton(
                            tooltip: 'Decline invitation',
                            icon: const Icon(
                              Icons.close,
                              color: HelixStatusColors.danger,
                            ),
                            onPressed: () => _respondToInvite(inv, false),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (_status != null)
            Padding(
              padding: HelixInsets.all(8),
              child: Text(_status!, textAlign: TextAlign.center),
            ),
          Expanded(
            child: groups.isEmpty
                ? const Center(child: Text('No groups yet'))
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return Card(
                        child: ListTile(
                          leading: Stack(
                            children: [
                              const Icon(Icons.group),
                              if (group.unreadMentionCount > 0)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: HelixInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: HelixStatusColors.danger,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${group.unreadMentionCount}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: HelixScrimColors.onBackdrop,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(group.title)),
                              if (group.notificationPolicy !=
                                  kGroupNotificationAll)
                                Icon(
                                  group.notificationPolicy ==
                                          kGroupNotificationMuted
                                      ? Icons.volume_off
                                      : Icons.notifications_none,
                                  size: 14,
                                  color: HelixStatusColors.neutral,
                                ),
                            ],
                          ),
                          subtitle: Text('Members: ${group.memberCount}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'open':
                                  _openGroup(group.conversationId);
                                case 'invite':
                                  _inviteMember(group.conversationId);
                                case 'join_link':
                                  _showJoinLink(group.conversationId);
                                case 'privacy':
                                  _showPrivacySettings(group.conversationId);
                                case 'members':
                                  _showMemberManagement(group.conversationId);
                                case 'transfer':
                                  _showTransferOwnership(group.conversationId);
                                case 'notifications':
                                  _showNotificationPolicy(group.conversationId);
                                case 'leave':
                                  _leaveGroup(
                                    group.conversationId,
                                    group.title,
                                  );
                                case 'delete':
                                  _deleteGroup(
                                    group.conversationId,
                                    group.title,
                                  );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'open',
                                child: ListTile(
                                  leading: Icon(Icons.chat),
                                  title: Text('Open'),
                                ),
                              ),
                              if (group.isAdmin)
                                const PopupMenuItem(
                                  value: 'invite',
                                  child: ListTile(
                                    leading: Icon(Icons.person_add),
                                    title: Text('Invite member'),
                                  ),
                                ),
                              if (group.isAdmin)
                                const PopupMenuItem(
                                  value: 'join_link',
                                  child: ListTile(
                                    leading: Icon(Icons.link),
                                    title: Text('Join link'),
                                  ),
                                ),
                              if (group.isAdmin)
                                const PopupMenuItem(
                                  value: 'privacy',
                                  child: ListTile(
                                    leading: Icon(Icons.lock_outline),
                                    title: Text('Group-add privacy'),
                                  ),
                                ),
                              if (group.isAdmin)
                                const PopupMenuItem(
                                  value: 'members',
                                  child: ListTile(
                                    leading: Icon(Icons.people_outline),
                                    title: Text('Manage members'),
                                  ),
                                ),
                              if (group.isAdmin)
                                const PopupMenuItem(
                                  value: 'transfer',
                                  child: ListTile(
                                    leading: Icon(Icons.swap_horiz),
                                    title: Text('Transfer ownership'),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'notifications',
                                child: ListTile(
                                  leading: Icon(Icons.notifications_outlined),
                                  title: Text('Notifications'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'leave',
                                child: ListTile(
                                  leading: Icon(Icons.exit_to_app),
                                  title: Text('Leave group'),
                                ),
                              ),
                              if (group.isAdmin)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.delete_forever,
                                      color: HelixStatusColors.danger,
                                    ),
                                    title: Text(
                                      'Delete group',
                                      style: TextStyle(
                                        color: HelixStatusColors.danger,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _openGroup(group.conversationId),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
