import 'dart:math';

import 'package:flutter/material.dart';
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
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _invites = widget.groupService.db.getGroupInvites();
    });
  }

  String get _currentAccountId =>
      widget.messagingService.currentAccountId ?? '';

  bool _isAdmin(String groupId) {
    final members = widget.groupService.getGroupMembersWithRoles(groupId);
    final me = members
        .where((m) => m['account_id'] == _currentAccountId)
        .firstOrNull;
    return me?['role'] == kRoleAdmin;
  }

  List<RemoteConversation> _groupConversations() {
    return widget.messagingService.conversationList().where((c) {
      final members = widget.messagingService.conversationMemberIds(
        c.conversationId,
      );
      return members.length > 2 || c.type == 'group' || c.type == 'GROUP';
    }).toList();
  }

  void _createGroup() {
    final nameController = TextEditingController();
    showDialog(
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

  void _openGroup(String groupId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          conversationId: groupId,
          messagingService: widget.messagingService,
          attachmentService: widget.attachmentService,
        ),
      ),
    );
  }

  void _inviteMember(String groupId) {
    final controller = TextEditingController();
    showDialog(
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

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupConversations();

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
                      final c = groups[index];
                      final memberCount = widget.messagingService
                          .conversationMemberIds(c.conversationId)
                          .length;
                      final isAdmin = _isAdmin(c.conversationId);
                      final title = c.title.isNotEmpty
                          ? c.title
                          : c.conversationId;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.group),
                          title: Text(title),
                          subtitle: Text('Members: $memberCount'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'open':
                                  _openGroup(c.conversationId);
                                case 'invite':
                                  _inviteMember(c.conversationId);
                                case 'leave':
                                  _leaveGroup(c.conversationId, title);
                                case 'delete':
                                  _deleteGroup(c.conversationId, title);
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
                              if (isAdmin)
                                const PopupMenuItem(
                                  value: 'invite',
                                  child: ListTile(
                                    leading: Icon(Icons.person_add),
                                    title: Text('Invite member'),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'leave',
                                child: ListTile(
                                  leading: Icon(Icons.exit_to_app),
                                  title: Text('Leave group'),
                                ),
                              ),
                              if (isAdmin)
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
                          onTap: () => _openGroup(c.conversationId),
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
