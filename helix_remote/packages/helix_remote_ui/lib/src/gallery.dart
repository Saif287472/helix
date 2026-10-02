part of '../helix_remote_ui.dart';

// The component gallery: every chat component with sample data, as plain
// widgets with no app wiring. Used by the golden tests and handy as a
// development page (`home: Scaffold(body: HelixComponentGallery())`).
//
// All sample names, numbers and messages are made up.

/// A section heading plus its content, used by the gallery pages.
class HelixGallerySection extends StatelessWidget {
  const HelixGallerySection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HelixSectionHeader(title: title),
      ...children,
      const SizedBox(height: HelixSpace.md),
    ],
  );
}

/// Sample data shared by the gallery sections.
abstract final class HelixGallerySamples {
  static const sam = HelixAvatarModel(name: 'Sam Rivera', colorIndex: 3);
  static const lee = HelixAvatarModel(name: 'Lee Chen', colorIndex: 5);
  static const team = HelixAvatarModel(
    name: 'Weekend hike',
    colorIndex: 6,
    isGroup: true,
  );

  static const chats = <HelixChatListItem>[
    HelixChatListItem(
      id: 'c1',
      title: 'Sam Rivera',
      avatar: sam,
      online: true,
      timeLabel: '14:05',
      unreadCount: 3,
      preview: HelixChatPreview(text: 'See you at the station at six'),
    ),
    HelixChatListItem(
      id: 'c2',
      title: 'Weekend hike',
      avatar: team,
      timeLabel: '13:40',
      unreadCount: 12,
      hasMention: true,
      pinned: true,
      preview: HelixChatPreview(
        text: 'Who is bringing the stove?',
        senderPrefix: 'Lee',
      ),
    ),
    HelixChatListItem(
      id: 'c3',
      title: 'Lee Chen',
      avatar: lee,
      timeLabel: 'Yesterday',
      muted: true,
      unreadCount: 2,
      preview: HelixChatPreview(text: '', kind: HelixPreviewKind.voiceNote),
    ),
    HelixChatListItem(
      id: 'c4',
      title: 'Aisha Khan',
      avatar: HelixAvatarModel(name: 'Aisha Khan', colorIndex: 1),
      timeLabel: 'Mon',
      verified: true,
      preview: HelixChatPreview(
        text: 'Thanks!',
        senderPrefix: 'You',
        status: HelixDeliveryStatus.read,
      ),
    ),
    HelixChatListItem(
      id: 'c5',
      title: 'Print shop',
      avatar: HelixAvatarModel(name: 'Print shop', colorIndex: 9),
      timeLabel: '12/09/26',
      archived: true,
      preview: HelixChatPreview(
        text: 'invoice.pdf',
        kind: HelixPreviewKind.document,
        status: HelixDeliveryStatus.delivered,
        senderPrefix: 'You',
      ),
    ),
    HelixChatListItem(
      id: 'c6',
      title: 'Nadia',
      avatar: HelixAvatarModel(name: 'Nadia', colorIndex: 0),
      timeLabel: '09:12',
      typingLabel: 'typing...',
    ),
    HelixChatListItem(
      id: 'c7',
      title: '+44 7700 900123',
      avatar: HelixAvatarModel(name: '+44 7700 900123', colorIndex: 7),
      timeLabel: '08:30',
      markedUnread: true,
      preview: HelixChatPreview(text: '', kind: HelixPreviewKind.undecryptable),
    ),
    HelixChatListItem(
      id: 'c8',
      title: 'Kofi',
      avatar: HelixAvatarModel(name: 'Kofi', colorIndex: 4),
      timeLabel: '07:55',
      preview: HelixChatPreview(text: 'Call me when you land', isDraft: true),
    ),
  ];

  static final waveform = Uint8List.fromList([
    for (var i = 0; i < 72; i++) 30 + ((i * 53) % 200),
  ]);

  static HelixMessage text(
    String id,
    String body, {
    bool outgoing = false,
    String time = '14:05',
    HelixDeliveryStatus status = HelixDeliveryStatus.read,
    HelixReplyQuote? reply,
    bool forwarded = false,
    bool edited = false,
    List<HelixReaction> reactions = const [],
    String? author,
    String? expires,
    int sentAtMs = 0,
    List<HelixTextRange> mentions = const [],
    HelixLinkPreview? link,
  }) => HelixMessage(
    id: id,
    outgoing: outgoing,
    timeLabel: time,
    status: status,
    reply: reply,
    forwarded: forwarded,
    edited: edited,
    reactions: reactions,
    authorName: author,
    authorId: outgoing ? 'me' : (author ?? 'them'),
    authorColorIndex: author == null
        ? 0
        : HelixAvatarModel.colorIndexFor(author),
    expiresLabel: expires,
    sentAtMs: sentAtMs,
    content: HelixTextContent(body, mentions: mentions, linkPreview: link),
  );
}

/// Chat-list rows: every state of a tile, swipe actions, selection, empty,
/// loading.
class HelixGalleryChatList extends StatelessWidget {
  const HelixGalleryChatList({super.key});

  @override
  Widget build(BuildContext context) {
    final extent = HelixChatListTile.extentFor(
      MediaQuery.textScalerOf(context),
    );
    return HelixGallerySection(
      title: 'Chat list',
      children: [
        const HelixArchivedRow(count: 3),
        for (final (i, item) in HelixGallerySamples.chats.indexed)
          SizedBox(
            height: extent,
            child: HelixSwipeableChatListTile(
              item: item,
              selected: i == 1,
              selectionMode: i == 1,
              startAction: const HelixSwipeAction(
                icon: Icons.push_pin,
                label: 'Pin',
                onTriggered: _noop,
              ),
              endAction: const HelixSwipeAction(
                icon: Icons.archive,
                label: 'Archive',
                onTriggered: _noop,
              ),
            ),
          ),
        const SizedBox(height: HelixSpace.sm),
        SizedBox(
          height: extent * 2,
          child: const HelixChatListSkeleton(count: 2, animate: false),
        ),
      ],
    );
  }
}

void _noop() {}

/// A conversation: runs, quotes, reactions, media, voice notes, documents,
/// placeholders, notices.
class HelixGalleryConversation extends StatelessWidget {
  const HelixGalleryConversation({super.key});

  @override
  Widget build(BuildContext context) {
    const t = HelixGallerySamples.text;
    final messages = <HelixMessage>[
      t(
        '1',
        'Morning! Are we still on for Saturday?',
        author: 'Sam',
        sentAtMs: 1,
      ),
      t(
        '2',
        'I checked the forecast',
        author: 'Sam',
        sentAtMs: 2,
        time: '09:01',
      ),
      t(
        '3',
        'Yes. Leaving at seven, bring water.',
        outgoing: true,
        time: '09:02',
        status: HelixDeliveryStatus.read,
        reactions: const [
          HelixReaction(emoji: '👍', count: 2, mine: true),
          HelixReaction(emoji: '❤️', count: 1),
        ],
      ),
      t(
        '4',
        'Great, I will tell the others. Details at https://example.org/hike',
        author: 'Sam',
        time: '09:03',
        reply: const HelixReplyQuote(
          authorName: 'You',
          text: 'Leaving at seven, bring water.',
          authorColorIndex: 3,
        ),
        link: const HelixLinkPreview(
          url: 'https://example.org/hike',
          title: 'Saturday hike - route and times',
          description: 'Meet at the station, bring water and a jacket.',
        ),
      ),
      t(
        '5',
        'Forwarded from the group',
        outgoing: true,
        forwarded: true,
        edited: true,
        status: HelixDeliveryStatus.delivered,
        expires: '1d',
      ),
      t(
        '6',
        'This one failed to send',
        outgoing: true,
        status: HelixDeliveryStatus.failed,
      ),
      const HelixMessage(
        id: '7',
        outgoing: false,
        timeLabel: '09:10',
        authorName: 'Sam',
        authorId: 'Sam',
        content: HelixMediaContent([
          HelixMediaItem(width: 4, height: 3),
          HelixMediaItem(
            width: 4,
            height: 3,
            isVideo: true,
            durationLabel: '0:12',
          ),
          HelixMediaItem(width: 3, height: 4),
          HelixMediaItem(width: 3, height: 4),
          HelixMediaItem(width: 3, height: 4),
        ], caption: 'Trail photos'),
      ),
      HelixMessage(
        id: '8',
        outgoing: true,
        timeLabel: '09:12',
        content: HelixAudioContent(
          durationLabel: '0:23',
          positionLabel: '0:07',
          progress: .3,
          playing: true,
          speed: 1.5,
          waveform: HelixGallerySamples.waveform,
        ),
      ),
      const HelixMessage(
        id: '9',
        outgoing: false,
        timeLabel: '09:13',
        authorName: 'Sam',
        authorId: 'Sam',
        content: HelixDocumentContent(
          name: 'route-plan.pdf',
          sizeLabel: '482 KB',
          typeLabel: 'PDF',
        ),
      ),
      const HelixMessage(
        id: '10',
        outgoing: false,
        timeLabel: '09:14',
        authorName: 'Sam',
        authorId: 'Sam',
        content: HelixViewOnceContent(),
      ),
      const HelixMessage(
        id: '11',
        outgoing: false,
        timeLabel: '09:15',
        authorName: 'Sam',
        authorId: 'Sam',
        content: HelixPlaceholderContent(HelixPlaceholderKind.undecryptable),
      ),
      const HelixMessage(
        id: '12',
        outgoing: true,
        timeLabel: '09:16',
        content: HelixPlaceholderContent(HelixPlaceholderKind.deleted),
      ),
      const HelixMessage(
        id: '13',
        outgoing: false,
        timeLabel: '09:17',
        authorName: 'Sam',
        authorId: 'Sam',
        content: HelixPlaceholderContent(HelixPlaceholderKind.unsupported),
      ),
      const HelixMessage(
        id: '14',
        outgoing: false,
        timeLabel: '09:18',
        authorName: 'Sam',
        authorId: 'Sam',
        content: HelixLocationContent(
          label: 'Station car park',
          address: 'North entrance',
        ),
      ),
      const HelixMessage(
        id: '15',
        outgoing: true,
        timeLabel: '09:19',
        content: HelixContactContent(
          name: 'Aisha Khan',
          detail: '+44 7700 900456',
          onHelix: true,
        ),
      ),
      t('16', 'مرحبا، هل نلتقي غدا؟', author: 'Nadia', time: '09:20'),
      t('17', 'আজ দেখা হবে তো?', outgoing: true, time: '09:21'),
    ];
    final positions = helixRunPositions(messages);
    return ColoredBox(
      color: HelixChatColors.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HelixDateSeparator(label: 'Today'),
          const HelixSystemNotice(
            text: 'Messages are end-to-end encrypted',
            icon: Icons.lock_outline,
          ),
          const HelixUnreadDivider(count: 3),
          for (var i = 0; i < messages.length; i++)
            HelixMessageBubble(
              message: messages[i],
              position: positions[i],
              selected: i == 2,
            ),
          const HelixSystemNotice(
            text: 'Missed voice call',
            icon: Icons.call_missed,
          ),
          const HelixTypingIndicator(label: 'Sam is typing', animate: false),
          const SizedBox(height: HelixSpace.sm),
        ],
      ),
    );
  }
}

/// The composer in its states: empty, with text, reply and edit banners,
/// recording, mentions, and the reaction picker and action menu content.
class HelixGalleryComposer extends StatefulWidget {
  const HelixGalleryComposer({super.key});

  @override
  State<HelixGalleryComposer> createState() => _HelixGalleryComposerState();
}

class _HelixGalleryComposerState extends State<HelixGalleryComposer> {
  final _empty = TextEditingController();
  final _typed = TextEditingController(text: 'On my way');
  final _edit = TextEditingController(text: 'Leaving at seven');

  @override
  void dispose() {
    _empty.dispose();
    _typed.dispose();
    _edit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HelixGallerySection(
    title: 'Composer',
    children: [
      HelixComposer(controller: _empty, onSend: _noop),
      HelixComposer(
        controller: _typed,
        onSend: _noop,
        banner: const HelixComposerBannerModel(
          kind: HelixComposerBannerKind.reply,
          title: 'Replying to Sam',
          text: 'Are we still on for Saturday?',
        ),
      ),
      HelixComposer(
        controller: _edit,
        onSend: _noop,
        editing: true,
        banner: const HelixComposerBannerModel(
          kind: HelixComposerBannerKind.edit,
          title: 'Edit message',
          text: 'Leaving at six',
        ),
      ),
      HelixComposer(
        controller: _empty,
        onSend: _noop,
        recording: const HelixVoiceRecordState(
          elapsedLabel: '0:07',
          cancelProgress: .3,
          lockProgress: .4,
        ),
      ),
      HelixComposer(
        controller: _empty,
        onSend: _noop,
        recording: const HelixVoiceRecordState(
          elapsedLabel: '0:31',
          locked: true,
        ),
      ),
      HelixComposer(
        controller: _empty,
        onSend: _noop,
        mentionCandidates: const [
          HelixMentionCandidate(id: 'a', name: 'Aisha Khan'),
          HelixMentionCandidate(id: 'b', name: 'Lee Chen', detail: 'Admin'),
        ],
        onMentionSelected: _ignore,
      ),
      const SizedBox(height: HelixSpace.sm),
      const Center(
        child: HelixReactionPicker(onPick: _ignore, current: '👍'),
      ),
      const SizedBox(height: HelixSpace.sm),
      HelixMessageActionMenu(
        actions: helixDefaultMessageActions(
          outgoing: true,
          canEdit: true,
          canDeleteForEveryone: true,
        ),
        onAction: _ignore,
      ),
      const HelixAttachmentSheet(onSelected: _ignore),
    ],
  );
}

void _ignore(Object? _) {}

/// Everything else: avatars, search, people, calls, settings, banners, safety
/// number, QR, empty states.
class HelixGalleryGeneral extends StatefulWidget {
  const HelixGalleryGeneral({super.key});

  @override
  State<HelixGalleryGeneral> createState() => _HelixGalleryGeneralState();
}

class _HelixGalleryGeneralState extends State<HelixGalleryGeneral> {
  final _search = TextEditingController();
  final _qr = HelixQrMatrix(21, [
    for (var i = 0; i < 21 * 21; i++) ((i * 7 + i ~/ 21) % 3 == 0),
  ]);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _search;
    final qr = _qr;
    return HelixGallerySection(
      title: 'General',
      children: [
        Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: Wrap(
            spacing: HelixSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final size in HelixAvatarSize.values)
                HelixAvatar(
                  model: HelixGallerySamples.sam,
                  size: size,
                  online: size == HelixAvatarSize.lg,
                ),
              const HelixAvatar(
                model: HelixAvatarModel(name: 'Group', isGroup: true),
              ),
            ],
          ),
        ),
        const HelixBanner(kind: HelixBannerKind.offline),
        const HelixBanner(kind: HelixBannerKind.connecting),
        const HelixBanner(
          kind: HelixBannerKind.updateAvailable,
          actionLabel: 'Update',
        ),
        Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: HelixSearchField(controller: search),
        ),
        const HelixMessageSearchTile(
          result: HelixMessageSearchResult(
            id: 'r1',
            chatTitle: 'Weekend hike',
            avatar: HelixGallerySamples.team,
            snippet: HelixHighlightedText('Who is bringing the stove?', [
              HelixTextRange(23, 3),
            ]),
            timeLabel: 'Yesterday',
            senderLabel: 'Lee',
          ),
        ),
        const HelixPersonTile(
          person: HelixPersonItem(
            id: 'p1',
            names: HelixPersonNames(
              phoneBookName: 'Aisha Khan',
              number: '+44 7700 900456',
              helixName: 'aisha',
            ),
            online: true,
          ),
        ),
        const HelixPersonTile(
          person: HelixPersonItem(
            id: 'p2',
            names: HelixPersonNames(
              nickname: 'Climbing Lee',
              number: '+44 7700 900789',
            ),
          ),
        ),
        const HelixPersonTile(
          person: HelixPersonItem(
            id: 'p3',
            names: HelixPersonNames(
              number: '+44 7700 900123',
              helixName: 'kofi',
            ),
          ),
        ),
        const HelixPersonTile(
          person: HelixPersonItem(
            id: 'p4',
            names: HelixPersonNames(helixName: 'nadia'),
          ),
        ),
        const HelixCallLogTile(
          item: HelixCallLogItem(
            id: 'k1',
            title: 'Sam Rivera',
            avatar: HelixGallerySamples.sam,
            direction: HelixCallDirection.missed,
            timeLabel: 'Today, 14:05',
            count: 2,
          ),
          onCallBack: _noop,
        ),
        const HelixCallLogTile(
          item: HelixCallLogItem(
            id: 'k2',
            title: 'Weekend hike',
            avatar: HelixGallerySamples.team,
            direction: HelixCallDirection.outgoing,
            timeLabel: 'Yesterday, 19:30',
            video: true,
            isGroup: true,
          ),
          onCallBack: _noop,
        ),
        const HelixSettingsSection(
          title: 'Privacy',
          footer: 'Read receipts also apply to group chats.',
          children: [
            HelixProfileHeaderTile(
              avatar: HelixGallerySamples.lee,
              name: 'Lee Chen',
              about: 'Out on the trail',
            ),
            HelixSettingsTile(
              icon: Icons.lock_outline,
              title: 'Blocked contacts',
              subtitle: '2 contacts',
              showChevron: true,
              onTap: _noop,
            ),
            HelixSettingsSwitchTile(
              icon: Icons.done_all,
              title: 'Read receipts',
              value: true,
              onChanged: _ignoreBool,
            ),
            HelixSettingsTile(
              icon: Icons.logout,
              title: 'Log out',
              destructive: true,
              onTap: _noop,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.all(HelixSpace.md),
          child: HelixSafetyNumberView(
            groups: [
              '12345',
              '67890',
              '24680',
              '13579',
              '11223',
              '44556',
              '77889',
              '99001',
              '23456',
              '78901',
              '34567',
              '89012',
            ],
            verified: true,
          ),
        ),
        Center(child: HelixQrDisplay(matrix: qr, size: 160)),
        const SizedBox(height: HelixSpace.md),
        const SizedBox(
          height: 200,
          child: HelixQrScanFrame(
            frameSize: 130,
            child: ColoredBox(color: HelixScrimColors.backdrop),
          ),
        ),
        const HelixChatListEmpty(onFindPeople: _noop),
      ],
    );
  }
}

void _ignoreBool(bool _) {}

/// All the gallery sections in one scrollable page.
class HelixComponentGallery extends StatelessWidget {
  const HelixComponentGallery({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      HelixGalleryChatList(),
      HelixGalleryConversation(),
      HelixGalleryComposer(),
      HelixGalleryGeneral(),
    ],
  );
}
