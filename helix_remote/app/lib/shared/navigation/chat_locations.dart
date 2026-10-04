/// Where the chat screens live in the router.
///
/// Any feature can open a conversation (people search, a call log, a group's
/// info page), and no feature may import another, so the paths are shared
/// here. The routes themselves are registered by the features that own the
/// screens (`conversation_routes.dart`, `chats_routes.dart`).
abstract final class ChatRoutes {
  /// `/chat/:conversationId`, optionally `?m=<message id>` to open at a
  /// message (a search hit, a quote).
  static const conversation = '/chat/:conversationId';

  /// The archived chats list.
  static const archived = '/archived-chats';

  /// The media viewer over one message: `/chat/:id/media/:rowid`.
  static const media = '/chat/:conversationId/media/:rowid';

  /// Forward one or more messages: `/chat/:id/forward`.
  static const forward = '/chat/:conversationId/forward';

  /// Message info (receipts): `/chat/:id/info/:rowid`.
  static const info = '/chat/:conversationId/info/:rowid';

  /// Conversation settings: `/chat/:id/settings`.
  static const settings = '/chat/:conversationId/settings';

  /// Preview before sending picked files: `/chat/:id/send-files`.
  static const sendFiles = '/chat/:conversationId/send-files';
}

/// The location of the conversation [conversationId], optionally opened at
/// the message with content id [messageId].
String chatLocation(String conversationId, {String? messageId}) {
  final base = '/chat/${Uri.encodeComponent(conversationId)}';
  return messageId == null
      ? base
      : '$base?m=${Uri.encodeQueryComponent(messageId)}';
}

String _base(String conversationId) =>
    '/chat/${Uri.encodeComponent(conversationId)}';

/// The media viewer over message [rowid] of a conversation, at [index].
String mediaLocation(String conversationId, int rowid, {int index = 0}) =>
    '${_base(conversationId)}/media/$rowid?i=$index';

/// Forward the messages [rowids] (database ids) of a conversation.
String forwardLocation(String conversationId, Iterable<int> rowids) =>
    '${_base(conversationId)}/forward?ids=${rowids.join(',')}';

/// "Message info" for message [rowid].
String infoLocation(String conversationId, int rowid) =>
    '${_base(conversationId)}/info/$rowid';

/// The conversation's settings.
String chatSettingsLocation(String conversationId) =>
    '${_base(conversationId)}/settings';

/// The preview shown before picked files are sent.
String sendFilesLocation(String conversationId) =>
    '${_base(conversationId)}/send-files';
