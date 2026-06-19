import 'dart:math';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({
    super.key,
    required this.groupService,
    required this.messagingService,
  });

  final RemoteGroupService groupService;
  final RemoteMessagingService messagingService;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>> _invites = [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  void _loadInvites() {
    setState(() {
      _invites = widget.groupService.db.getGroupInvites();
    });
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
              final creatorId =
                  widget.messagingService.currentAccountId ?? 'unknown';
              widget.groupService.createGroup(
                groupId: groupId,
                name: name,
                creatorId: creatorId,
              );
              Navigator.pop(ctx);
              setState(() => _status = 'Group "$name" created (queued)');
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _respondToInvite(Map<String, dynamic> invite, bool accept) {
    final inviteId = invite['invite_id'] as String;
    final accountId = widget.messagingService.currentAccountId ?? '';
    widget.groupService.respondToInvite(
      inviteId: inviteId,
      selfAccountId: accountId,
      accept: accept,
    );
    _loadInvites();
    setState(() => _status = accept ? 'Invite accepted' : 'Invite rejected');
  }

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
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
            child:
                widget.messagingService
                    .conversationList()
                    .where((c) {
                      final members = widget.messagingService
                          .conversationMemberIds(c.conversationId);
                      return members.length > 2 || c.type == 'group';
                    })
                    .toList()
                    .isEmpty
                ? const Center(child: Text('No groups yet'))
                : ListView(
                    children: widget.messagingService
                        .conversationList()
                        .where((c) {
                          final members = widget.messagingService
                              .conversationMemberIds(c.conversationId);
                          return members.length > 2 || c.type == 'group';
                        })
                        .map(
                          (c) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.group),
                              title: Text(
                                c.title.isNotEmpty ? c.title : c.conversationId,
                              ),
                              subtitle: Text(
                                'Members: ${widget.messagingService.conversationMemberIds(c.conversationId).length}',
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
