import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The conversation keys (`prototype/js/screens/conversation.js`) on the
/// sample data.

const _members = {
  'group:family': ['ammu', 'abbu', 'rumana', 'karim'],
  'group:design': ['sadia', 'tanvir', 'arif', 'nadia', 'rumana', 'karim'],
  'group:lunch': ['arif', 'tanvir'],
  'group:studio': ['sadia', 'tanvir'],
};

HelixMessage? _find(String chat, String id) {
  for (final it in OrbitFakes.conversations[chat] ?? const []) {
    if (it is HelixMessageItem && it.message.id == id) return it.message;
  }
  return null;
}

/// `previewText(m)`.
String _previewText(HelixMessage? m) => switch (m?.content) {
  null => '',
  final HelixTextContent c => c.text,
  final HelixMediaContent c =>
    c.caption.isNotEmpty
        ? c.caption
        : (c.items.first.isVideo ? 'Video' : 'Photo'),
  final HelixAudioContent c =>
    c.isVoiceNote ? 'Voice message' : (c.title ?? 'Audio'),
  final HelixDocumentContent c => c.name,
  HelixLocationContent() => 'Location',
  final HelixContactContent c => c.name,
  final HelixPollContent c => 'Poll: ${c.question}',
  _ => 'Message',
};

ChatModel chatFor(
  String id, {
  String draft = '',
  String? reply,
  String? edit,
  bool mention = false,
  OrbitRecording recording = OrbitRecording.none,
  String? pending,
  String? pendingReason,
  ChatLoadState state = ChatLoadState.ready,
  bool left = false,
  String? blocked,
}) {
  final chat = [
    ...OrbitFakes.chats,
    ...OrbitFakes.archived,
  ].where((c) => c.id == id).firstOrNull;
  final pid = id.split(':')[1];
  final group = id.startsWith('group:');
  final person = group ? null : OrbitFakes.people[pid];
  final title = chat?.title ?? person?.names.display ?? 'Chat';
  final peerName = person?.names.display ?? 'them';
  final members = _members[id] ?? const [];
  String? sub;
  if (group) {
    if (left) {
      sub = 'You are no longer a member';
    } else if (members.length + 1 <= 4) {
      sub = [
        'You',
        for (final m in members)
          OrbitFakes.people[m]!.names.display.split(' ').first,
      ].join(', ');
    } else {
      sub = '${members.length + 1} members';
    }
  } else if (person != null) {
    sub = person.online
        ? 'online'
        : person.id == 'arif'
        ? 'last seen today at 08:31'
        : person.names.secondary ?? '';
  }
  HelixComposerBannerModel? banner;
  if (reply != null) {
    final m = _find(id, reply);
    final who = m?.outgoing ?? false ? 'yourself' : m?.authorName ?? peerName;
    banner = HelixComposerBannerModel(
      kind: HelixComposerBannerKind.reply,
      title: 'Replying to $who',
      text: _previewText(m),
    );
  }
  if (edit != null) {
    banner = HelixComposerBannerModel(
      kind: HelixComposerBannerKind.edit,
      title: 'Edit message',
      text: _previewText(_find(id, edit)),
    );
  }
  final q = RegExp(r'@(\w*)$').firstMatch(draft)?.group(1)?.toLowerCase();
  final link = pendingReason == 'link';
  return ChatModel(
    conversationId: id,
    title: title,
    avatar:
        chat?.avatar ?? person?.avatar ?? const HelixAvatarModel(name: 'Chat'),
    loadState: state,
    subtitle: sub,
    verified: chat?.verified ?? person?.verified ?? false,
    isGroup: group,
    showCallButtons: !group && blocked == null,
    pendingMembers: [
      if (group && pending != null)
        PendingMemberItem(
          account: 'karim',
          title: 'Confirm Karim Uncle?',
          explanation:
              '${link ? 'Karim Uncle joined this group through its invite link, and nothing else vouches for them.' : 'Karim Uncle was added by the server roster, but no admin of this group announced it.'}'
              ' Until you confirm, what you send in this group stays '
              'unreadable to them.',
          canRemove: pending == 'admin',
        ),
    ],
    items: OrbitFakes.conversations[id] ?? const [],
    composerDisabledReason: switch (blocked) {
      'byMe' => 'You blocked this contact. Open chat settings to unblock.',
      'byThem' => '$peerName has blocked you. You can’t message or call them.',
      _ => left ? 'You can no longer send messages to this group.' : null,
    },
    disabledIsBlock: blocked != null,
    initialDraft: edit != null ? _previewText(_find(id, edit)) : draft,
    banner: banner,
    mentionCandidates: [
      if (mention && q != null)
        for (final m in members)
          if (OrbitFakes.people[m]!.names.display.toLowerCase().contains(q))
            OrbitFakes.people[m]!,
    ].take(4).toList(),
    recording: recording,
    recordingWave: recording == OrbitRecording.locked
        ? OrbitFakes.wave.take(24).toList().reversed.toList()
        : const [],
  );
}

final Map<String, WidgetBuilder> chatPreviews = {
  'chat': (_) => ChatScreen(model: chatFor('direct:nadia')),
  'chat-typing': (_) => ChatScreen(
    model: chatFor('direct:nadia', draft: 'On my way, see you in 10'),
  ),
  'chat-reply': (_) => ChatScreen(
    model: chatFor('direct:nadia', reply: 'n8', draft: 'They look amazing!'),
  ),
  'chat-edit': (_) => ChatScreen(model: chatFor('direct:nadia', edit: 'n5')),
  'chat-attach': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(attach: true),
  ),
  'chat-emoji': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(emoji: true),
  ),
  'chat-rec': (_) => ChatScreen(
    model: chatFor('direct:nadia', recording: OrbitRecording.hold),
  ),
  'chat-rec-lock': (_) => ChatScreen(
    model: chatFor('direct:nadia', recording: OrbitRecording.locked),
  ),
  'chat-actions': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(actionsFor: 'n6'),
  ),
  'chat-actions-mine': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(actionsFor: 'n5'),
  ),
  'chat-select': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(selected: {'n3', 'n5'}),
  ),
  'chat-search': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(searching: true),
  ),
  'chat-search-q': (_) => ChatScreen(
    model: chatFor('direct:nadia'),
    start: const ChatStart(searching: true, query: 'the'),
  ),
  'chat-kinds': (_) => ChatScreen(model: chatFor('direct:arif')),
  'chat-transfer': (_) => ChatScreen(model: chatFor('direct:rafiq')),
  'chat-new': (_) => ChatScreen(model: chatFor('direct:sadia')),
  'group': (_) => ChatScreen(model: chatFor('group:family')),
  'group-mention': (_) => ChatScreen(
    model: chatFor('group:family', draft: 'Thanks @', mention: true),
  ),
  'group-pending': (_) =>
      ChatScreen(model: chatFor('group:family', pending: 'admin')),
  'group-pending-member': (_) =>
      ChatScreen(model: chatFor('group:family', pending: 'member')),
  'group-pending-link': (_) => ChatScreen(
    model: chatFor('group:family', pending: 'admin', pendingReason: 'link'),
  ),
  'chat-loading': (_) =>
      ChatScreen(model: chatFor('direct:nadia', state: ChatLoadState.loading)),
  'chat-error': (_) => ChatScreen(
    model: chatFor('direct:nadia', state: ChatLoadState.openFailed),
  ),
  'group-left': (_) => ChatScreen(model: chatFor('group:family', left: true)),
  'chat-blocked': (_) =>
      ChatScreen(model: chatFor('direct:shuvo', blocked: 'byMe')),
  'chat-blocked-me': (_) =>
      ChatScreen(model: chatFor('direct:shuvo', blocked: 'byThem')),
};
