import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/presentation/groups/groups_view_model.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';

part 'groups/actions_and_body.dart';
part 'groups/models.dart';

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
  late final GroupsViewModel _viewModel;
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _joinRequests = [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _viewModel = GroupsViewModel(widget.messagingService);
    _reload();
  }

  void _reload() {
    setState(() {
      _invites = widget.groupService.db.getGroupInvites();
      // Aggregate pending join requests across all admin groups.
      final allRequests = <Map<String, dynamic>>[];
      for (final conv in _viewModel.conversations()) {
        if (!_isGroupConversation(conv)) continue;
        final gid = conv.conversationId;
        if (_isCurrentUserAdmin(gid)) {
          allRequests.addAll(widget.groupService.getPendingJoinRequests(gid));
        }
      }
      _joinRequests = allRequests;
    });
  }

  String get _currentAccountId => _viewModel.currentAccountId;

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
    for (final conversation in _viewModel.conversations()) {
      final members = _viewModel.memberIds(conversation.conversationId);
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
            child: const Text(
              'Revoke',
              style: TextStyle(color: HelixStatusColors.danger),
            ),
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

  @override
  Widget build(BuildContext context) => _buildScreen(context);

  void _update(VoidCallback change) => setState(change);
}
