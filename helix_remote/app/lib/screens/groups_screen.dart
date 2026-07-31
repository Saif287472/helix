import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({
    super.key,
    required this.groupService,
    required this.messagingService,
    this.attachmentService,
  });

  final RemoteGroupService groupService;
  final RemoteMessagingService messagingService;
  final RemoteAttachmentService? attachmentService;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _joinRequests = [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _invites = widget.groupService.db.getGroupInvites();
      // Aggregate pending join requests across all admin groups.
      final allRequests = <Map<String, dynamic>>[];
      for (final conv in widget.messagingService.conversationList()) {
        if (!_isGroupConversation(conv)) continue;
        final gid = conv.conversationId;
        if (_isCurrentUserAdmin(gid)) {
          allRequests.addAll(widget.groupService.getPendingJoinRequests(gid));
        }
      }
      _joinRequests = allRequests;
    });
  }

  String get _currentAccountId =>
      widget.messagingService.currentAccountId ?? '';

  bool _isGroupConversation(RemoteConversation conv) =>
      conv.type == 'group' || conv.type == 'GROUP';

  bool _isCurrentUserAdmin(String groupId) {
    final roles = widget.groupService.getGroupMembersWithRoles(groupId);
    return roles.any(
      (m) => m['account_id'] == _currentAccountId && m['role'] == kRoleAdmin,
    );
  }

  List<_GroupRowData> _groupRows() {
    final currentAccountId = _currentAccountId;
    final rows = <_GroupRowData>[];
    for (final conversation in widget.messagingService.conversationList()) {
      final members = widget.messagingService.conversationMemberIds(
        conversation.conversationId,
      );
      final isGroup = members.length > 2 || _isGroupConversation(conversation);
      if (!isGroup) continue;

      final gid = conversation.conversationId;
      final roles = widget.groupService.getGroupMembersWithRoles(gid);
      final isAdmin = roles.any(
        (member) =>
            member['account_id'] == currentAccountId &&
            member['role'] == kRoleAdmin,
      );
      final notifPolicy = widget.groupService.getGroupNotificationPolicy(gid);
      final unreadMentions = widget.groupService.getUnreadMentions(
        gid,
        currentAccountId,
      );
      rows.add(
        _GroupRowData(
          conversationId: gid,
          title: conversation.title.isNotEmpty ? conversation.title : gid,
          memberCount: members.length,
          isAdmin: isAdmin,
          notificationPolicy: notifPolicy,
          unreadMentionCount: unreadMentions.length,
        ),
      );
    }
    return rows;
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create Group'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final groupId = _randomId();
                widget.groupService.createGroup(
                  groupId: groupId,
                  name: name,
                  creatorId: _currentAccountId,
                );
                Navigator.pop(ctx);
                setState(() => _status = 'Group "$name" created (queued)');
                _reload();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  void _respondToInvite(Map<String, dynamic> invite, bool accept) {
    final inviteId = invite['invite_id'] as String;
    widget.groupService.respondToInvite(
      inviteId: inviteId,
      selfAccountId: _currentAccountId,
      accept: accept,
    );
    setState(() => _status = accept ? 'Invite accepted' : 'Invite rejected');
    _reload();
  }

  void _approveJoinRequest(Map<String, dynamic> req, bool approve) {
    widget.groupService.approveJoinRequest(
      requestId: req['request_id'] as String,
      groupId: req['group_id'] as String,
      approve: approve,
    );
    setState(
      () =>
          _status = approve ? 'Join request approved' : 'Join request rejected',
    );
    _reload();
  }

  void _openGroup(String groupId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: groupId,
          messagingService: widget.messagingService,
          attachmentService: widget.attachmentService,
          groupService: widget.groupService,
        ),
      ),
    );
  }

  Future<void> _inviteMember(String groupId) async {
    final controller = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite Member'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Account ID to invite',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final inviteeId = controller.text.trim();
                if (inviteeId.isEmpty) return;
                if (widget.groupService.isMemberBlocked(groupId, inviteeId)) {
                  Navigator.pop(ctx);
                  setState(
                    () => _status = 'This member is blocked from re-joining',
                  );
                  return;
                }
                final inviteId = _randomId();
                try {
                  widget.groupService.inviteMember(
                    groupId: groupId,
                    inviteId: inviteId,
                    inviterId: _currentAccountId,
                    inviteeId: inviteeId,
                  );
                  Navigator.pop(ctx);
                  setState(() => _status = 'Invite sent to $inviteeId');
                } catch (e) {
                  Navigator.pop(ctx);
                  setState(() => _status = 'Invite failed: $e');
                }
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showJoinLink(String groupId) async {
    final links = widget.groupService.getActiveJoinLinks(groupId);
    if (!mounted) return;
    if (links.isEmpty) {
      await _createJoinLink(groupId);
      return;
    }
    final link = links.first;
    final token = link['token'] as String;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(token, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              'Requires approval: ${link['requires_approval'] == true}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              Navigator.pop(ctx);
              setState(() => _status = 'Join link copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              widget.groupService.revokeJoinLink(
                groupId: groupId,
                linkId: link['link_id'] as String,
              );
              Navigator.pop(ctx);
              setState(() => _status = 'Join link revoked');
              _reload();
            },
            child: const Text('Revoke', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _createJoinLink(String groupId) async {
    bool requiresApproval = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Create Join Link'),
          content: CheckboxListTile(
            title: const Text('Require admin approval'),
            value: requiresApproval,
            onChanged: (v) => setSt(() => requiresApproval = v ?? false),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final linkId = _randomId();
    final token = _randomToken();
    final expiresAt =
        DateTime.now().millisecondsSinceEpoch + 7 * 24 * 60 * 60 * 1000;
    widget.groupService.createJoinLink(
      linkId: linkId,
      groupId: groupId,
      token: token,
      requiresApproval: requiresApproval,
      expiresAt: expiresAt,
    );
    setState(() => _status = 'Join link created');
    _reload();
    if (mounted) await _showJoinLink(groupId);
  }

  Future<void> _showPrivacySettings(String groupId) async {
    final current = widget.groupService.getGroupAddPolicy(groupId);
    String selected = current;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Group-Add Privacy'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setSt(() => selected = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final policy in [
                  kGroupAddPolicyEveryone,
                  kGroupAddPolicyContacts,
                  kGroupAddPolicyNobody,
                ])
                  RadioListTile<String>(
                    title: Text(_policyLabel(policy)),
                    value: policy,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    widget.groupService.setGroupAddPolicy(groupId: groupId, policy: result);
    setState(
      () => _status = 'Group-add privacy set to ${_policyLabel(result)}',
    );
  }

  Future<void> _showNotificationPolicy(String groupId) async {
    final current = widget.groupService.getGroupNotificationPolicy(groupId);
    String selected = current;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Notification Policy'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setSt(() => selected = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final policy in [
                  kGroupNotificationAll,
                  kGroupNotificationMentionsOnly,
                  kGroupNotificationAdminOnly,
                  kGroupNotificationMuted,
                ])
                  RadioListTile<String>(
                    title: Text(_notifPolicyLabel(policy)),
                    value: policy,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    widget.groupService.setGroupNotificationPolicy(
      groupId: groupId,
      policy: result,
    );
    setState(() => _status = 'Notifications: ${_notifPolicyLabel(result)}');
    _reload();
  }

  Future<void> _showMemberManagement(String groupId) async {
    final members = widget.groupService.getGroupMembersWithRoles(groupId);
    if (!mounted) return;
    final blockController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Member Management'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (members.isEmpty)
                  const Text('No members')
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (ctx, i) {
                        final m = members[i];
                        final mid = m['account_id'] as String;
                        final role = m['role'] as String;
                        return ListTile(
                          dense: true,
                          title: Text(mid),
                          subtitle: Text(role),
                          trailing: mid != _currentAccountId
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.block, size: 18),
                                      tooltip: 'Block & remove',
                                      onPressed: () {
                                        widget.groupService.blockMember(
                                          groupId: groupId,
                                          accountId: mid,
                                        );
                                        Navigator.pop(ctx);
                                        setState(
                                          () => _status = 'Blocked $mid',
                                        );
                                        _reload();
                                      },
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: blockController,
                        decoration: const InputDecoration(
                          labelText: 'Block account ID',
                          isDense: true,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final aid = blockController.text.trim();
                        if (aid.isEmpty) return;
                        widget.groupService.blockMember(
                          groupId: groupId,
                          accountId: aid,
                        );
                        Navigator.pop(ctx);
                        setState(() => _status = 'Blocked $aid');
                        _reload();
                      },
                      child: const Text('Block'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      blockController.dispose();
    }
  }

  Future<void> _showTransferOwnership(String groupId) async {
    final members = widget.groupService.getGroupMembersWithRoles(groupId);
    final others = members
        .where((m) => m['account_id'] != _currentAccountId)
        .toList();
    if (others.isEmpty) {
      setState(() => _status = 'No other members to transfer ownership to');
      return;
    }
    String? selected = others.first['account_id'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Transfer Ownership'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select the new group owner. You will remain an admin.',
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selected,
                isExpanded: true,
                items: others
                    .map(
                      (m) => DropdownMenuItem(
                        value: m['account_id'] as String,
                        child: Text('${m['account_id']} (${m['role']})'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setSt(() => selected = v),
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
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
    final newOwner = selected;
    if (confirmed != true || newOwner == null || !mounted) return;
    widget.groupService.transferOwnership(
      groupId: groupId,
      newOwnerId: newOwner,
      selfAccountId: _currentAccountId,
    );
    setState(() => _status = 'Ownership transfer queued to $newOwner');
  }

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
      setState(() => _status = 'Left group "$title"');
      _reload();
    } catch (e) {
      setState(() => _status = 'Leave failed: $e');
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
      setState(() => _status = 'Group "$title" deleted');
      _reload();
    } catch (e) {
      setState(() => _status = 'Delete failed: $e');
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

  @override
  Widget build(BuildContext context) {
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
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _approveJoinRequest(req, true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
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
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _respondToInvite(inv, true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
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
              padding: const EdgeInsets.all(8),
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
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${group.unreadMentionCount}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
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
                                  color: Colors.grey,
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
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      'Delete group',
                                      style: TextStyle(color: Colors.red),
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

class _GroupRowData {
  const _GroupRowData({
    required this.conversationId,
    required this.title,
    required this.memberCount,
    required this.isAdmin,
    required this.notificationPolicy,
    required this.unreadMentionCount,
  });

  final String conversationId;
  final String title;
  final int memberCount;
  final bool isAdmin;
  final String notificationPolicy;
  final int unreadMentionCount;
}
