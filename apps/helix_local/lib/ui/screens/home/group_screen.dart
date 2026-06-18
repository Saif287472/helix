import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/providers/controllers/group_service.dart';
import 'package:helix_local_groups/helix_groups.dart';

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  bool get _isLanLobby => groupId == GroupService.publicLobbyId;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget._isLanLobby) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final profileService = ref.read(profileServiceProvider);
        final identity = profileService.identity;
        final profile = profileService.profile;
        if (identity != null && profile != null) {
          ref.read(lanLobbyServiceProvider).join(
            localFp: identity.staticPublicKeyFingerprint,
            name: profile.displayName,
            suffix: identity.deviceSuffix,
          ).ignore();
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget._isLanLobby) {
      ref.read(lanLobbyServiceProvider).leave().ignore();
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget._isLanLobby) return _buildLanLobbyScreen(context);

    final theme = Theme.of(context);
    final groups = ref.watch(groupSnapshotsProvider).value ?? [];
    final group = groups.cast<GroupSnapshot?>().firstWhere(
      (g) => g!.groupId == widget.groupId,
      orElse: () => null,
    );

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: Text('Group not found or has been left.')),
      );
    }

    final List<GroupMessage> messages =
        ref.watch(groupMessagesProvider(widget.groupId));
    final groupService = ref.read(groupServiceProvider);
    final localFingerprint = groupService.localFingerprint;

    ref.listen<List<GroupMessage>>(groupMessagesProvider(widget.groupId), (prev, next) {
      if (next.length != (prev?.length ?? 0)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name),
            Text(
              '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Group Info',
            onPressed: () => _showGroupInfoSheet(context, group, localFingerprint),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = messages[i];
                      final isMe = msg.senderFingerprint == localFingerprint;

                      final details = groupService.resolvePeerDetails?.call(msg.senderFingerprint);
                      final displayName = isMe ? 'You' : (details?.displayName ?? msg.senderFingerprint.substring(0, 8));
                      final suffix = (isMe || details == null || details.deviceSuffix.isEmpty) ? '' : ' (${details.deviceSuffix})';

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isMe)
                                Text(
                                  '$displayName$suffix',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (!isMe) const SizedBox(height: 4),
                              Text(msg.text),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (val) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    ref.read(groupMessagesProvider(widget.groupId).notifier).sendMessage(text).ignore();
    _messageController.clear();
    _scrollToBottom();
  }

  void _showGroupInfoSheet(BuildContext context, GroupSnapshot group, String localFingerprint) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final groupService = ref.read(groupServiceProvider);
        final isHost = group.hostFingerprint == localFingerprint;
        final isPublic = group.isPublicLobby;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Consumer(
              builder: (ctx, ref, _) {
                final currentGroups = ref.watch(groupSnapshotsProvider).value ?? [];
                final currentGroup = currentGroups.cast<GroupSnapshot?>().firstWhere(
                  (g) => g!.groupId == widget.groupId,
                  orElse: () => null,
                );
                if (currentGroup == null) return const Center(child: Text('Group left.'));

                final inviteCode = isPublic ? '' : groupService.buildGroupCode(widget.groupId);

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      currentGroup.name,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPublic ? 'Public LAN Lobby' : 'Private Group',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(160),
                      ),
                    ),
                    const Divider(height: 32),

                    if (!isPublic) ...[
                      Text('Invite Code', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                inviteCode,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: inviteCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invite code copied.')),
                              );
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                    ],

                    if (!isPublic && isHost && currentGroup.pending.isNotEmpty) ...[
                      Text('Join Requests (${currentGroup.pending.length})', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...currentGroup.pending.map((p) => ListTile(
                            title: Text(p.displayName),
                            subtitle: Text(p.fingerprint.substring(0, 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check, color: Colors.green),
                                  onPressed: () => groupService.executeDecideJoin(
                                    currentGroup.groupId,
                                    p.fingerprint,
                                    GroupJoinDecision.approved,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  onPressed: () => groupService.executeDecideJoin(
                                    currentGroup.groupId,
                                    p.fingerprint,
                                    GroupJoinDecision.denied,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const Divider(height: 32),
                    ],

                    Text('Members (${currentGroup.memberCount})', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...currentGroup.members.map((m) {
                      final isMe = m.fingerprint == localFingerprint;
                      final isHostMember = m.fingerprint == currentGroup.hostFingerprint;

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(m.displayName.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(isMe ? '${m.displayName} (You)' : m.displayName),
                        subtitle: Text(m.fingerprint.substring(0, 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isHostMember)
                              const Chip(
                                label: Text('Host'),
                                labelStyle: TextStyle(fontSize: 10),
                                padding: EdgeInsets.zero,
                              ),
                            if (!isPublic && isHost && !isMe) ...[
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'kick') {
                                    groupService.executeKick(currentGroup.groupId, m.fingerprint);
                                  } else if (val == 'block') {
                                    groupService.executeBlock(currentGroup.groupId, m.fingerprint);
                                  } else if (val == 'handover') {
                                    groupService.executeHandover(currentGroup.groupId, m.fingerprint);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'handover',
                                    child: Text('Make Host'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'kick',
                                    child: Text('Kick'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'block',
                                    child: Text('Block'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),

                    const Divider(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      ),
                      onPressed: () => _leaveGroup(context, currentGroup, localFingerprint),
                      icon: const Icon(Icons.exit_to_app),
                      label: Text(isPublic ? 'Leave Lobby' : 'Leave Group'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _leaveGroup(BuildContext context, GroupSnapshot group, String localFingerprint) async {
    final groupService = ref.read(groupServiceProvider);

    if (group.hostFingerprint == localFingerprint) {
      final otherMembers = group.members.where((m) => m.fingerprint != localFingerprint).toList();
      if (otherMembers.isNotEmpty) {
        final handoverTarget = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Transfer Host Role'),
            content: const Text('Select a member to transfer hosting duties before leaving.'),
            actions: [
              ...otherMembers.map((m) => TextButton(
                    onPressed: () => Navigator.of(ctx).pop(m.fingerprint),
                    child: Text(m.displayName),
                  )),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
        if (handoverTarget == null) return;
        await groupService.executeHandover(group.groupId, handoverTarget);
      }
    }

    try {
      await groupService.leaveGroup(group.groupId);
      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to leave: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LAN Lobby UI
  // ---------------------------------------------------------------------------

  Widget _buildLanLobbyScreen(BuildContext context) {
    final theme = Theme.of(context);
    final lobbyState = ref.watch(lanLobbyStateProvider).value;
    final messages = ref.watch(lanLobbyMessagesProvider);
    final localFp = lobbyState?.localFp ??
        ref.read(profileServiceProvider).identity?.staticPublicKeyFingerprint ??
        '';
    final memberCount = lobbyState?.memberCount ?? 0;

    ref.listen<List<LobbyMessage>>(lanLobbyMessagesProvider, (prev, next) {
      if (next.length != (prev?.length ?? 0)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('LAN Lobby'),
            Text(
              memberCount == 0
                  ? 'Connecting…'
                  : '$memberCount member${memberCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Lobby Info',
            onPressed: lobbyState == null
                ? null
                : () => _showLanLobbyInfoSheet(context, lobbyState, localFp),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (lobbyState == null) const LinearProgressIndicator(),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        lobbyState == null ? 'Joining lobby…' : 'No messages yet. Say hello!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = messages[i];
                        final isMe = msg.senderFp == localFp;
                        final displayName = isMe ? 'You' : msg.senderName;

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isMe)
                                  Text(
                                    displayName,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (!isMe) const SizedBox(height: 4),
                                Text(msg.text),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: lobbyState != null,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendLanLobbyMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: lobbyState == null ? null : _sendLanLobbyMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendLanLobbyMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    ref.read(lanLobbyServiceProvider).sendMessage(text).ignore();
    _messageController.clear();
    _scrollToBottom();
  }

  void _showLanLobbyInfoSheet(BuildContext context, LobbyState lobbyState, String localFp) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Consumer(
              builder: (ctx, ref, _) {
                final currentState = ref.watch(lanLobbyStateProvider).value;
                if (currentState == null) {
                  return const Center(child: Text('Not connected.'));
                }
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'LAN Lobby',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Public LAN Lobby',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(160),
                      ),
                    ),
                    const Divider(height: 32),
                    Text('Members (${currentState.memberCount})', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...currentState.members.map((m) {
                      final isMe = m.fp == localFp;
                      final isHostMember = m.fp == currentState.hostFp;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            m.name.isNotEmpty ? m.name.substring(0, 1).toUpperCase() : '?',
                          ),
                        ),
                        title: Text(isMe ? '${m.name} (You)' : m.name),
                        subtitle: Text(m.fp.substring(0, 12)),
                        trailing: isHostMember
                            ? const Chip(
                                label: Text('Host'),
                                labelStyle: TextStyle(fontSize: 10),
                                padding: EdgeInsets.zero,
                              )
                            : null,
                      );
                    }),
                    const Divider(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      ),
                      onPressed: () => _leaveLanLobby(context),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Leave Lobby'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _leaveLanLobby(BuildContext context) async {
    await ref.read(lanLobbyServiceProvider).leave();
    if (context.mounted) {
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    }
  }
}
