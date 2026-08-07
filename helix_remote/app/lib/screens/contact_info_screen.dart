import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/presentation/contact_info/contact_info_view_model.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

part 'contact_info/actions.dart';
part 'contact_info/widgets_primary.dart';
part 'contact_info/widgets_secondary.dart';

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
  late final ContactInfoViewModel _viewModel;
  List<RemoteDecryptedMessage> _messages = const [];
  List<RemoteConversation> _sharedGroups = const [];
  RemoteConversationPrivacy _privacy = const RemoteConversationPrivacy();
  RemoteStorageSummary? _storage;
  RemoteConversation? _conversation;
  String? _peerAccountId;
  bool _loaded = false;

  String get _displayName =>
      _viewModel.peerDisplayName(widget.conversationId) ??
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
    _viewModel = ContactInfoViewModel(widget.messagingService);
    unawaited(_load());
  }

  Future<void> _load() async {
    final conversations = _viewModel.conversations();
    final conversation = conversations
        .where((c) => c.conversationId == widget.conversationId)
        .firstOrNull;
    final peer = _viewModel.peerAccountIdForConversation(widget.conversationId);
    final groups = <RemoteConversation>[];
    if (peer != null) {
      for (final group in conversations.where(_isGroupConversation)) {
        final members = _viewModel.memberIds(group.conversationId);
        if (members.contains(peer)) groups.add(group);
      }
    }
    final messages = await _viewModel.messages(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _conversation = conversation;
      _peerAccountId = peer;
      _sharedGroups = groups;
      _messages = messages;
      _privacy = _viewModel.privacy(widget.conversationId);
      _storage = _viewModel.storage(widget.conversationId);
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
    final pageColor = dark
        ? HelixColorTokens.cFF0B0B0C
        : HelixColorTokens.cFFF4F5F7;
    final sectionColor = dark ? HelixColorTokens.cFF171719 : cs.surface;

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
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: HelixSkeleton(width: 192, height: 24)),
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

  void _update(VoidCallback change) => setState(change);
}
