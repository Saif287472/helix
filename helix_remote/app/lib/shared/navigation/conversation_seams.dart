import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/router/app_router.dart';

/// Where the people screens hand over to other features.
///
/// A feature never imports another feature (`test/architecture_test.dart`), so
/// people - which starts chats and calls, and links to a chat's shared media
/// and to a group - cannot call the conversation or calls screens directly.
/// They meet here instead: this interface is the whole contract, its default
/// goes to a route by path, and the feature that owns the destination changes
/// **its own method** when its route exists.
///
/// - [openChat]: A2a. The default pushes `/home/chats/<conversation id>`
///   (a direct chat is `direct:<account>`, a group `group:<id>`); A2a
///   registers that route or edits this method to match theirs.
/// - [openSharedMedia]: A2a. Media, links and documents of one conversation.
///   Returns false while there is no such screen.
/// - [startCall]: A3a. Returns false while there is no call screen, and the
///   caller tells the person so.
abstract interface class ConversationSeams {
  /// Opens a conversation. [conversationId] is `direct:<account>` or
  /// `group:<id>`.
  Future<void> openChat(String conversationId);

  /// Opens the media, links and documents of [conversationId]. False when
  /// that screen does not exist yet.
  Future<bool> openSharedMedia(String conversationId);

  /// Starts a one-to-one call. False when calling is not available yet.
  Future<bool> startCall(String accountId, {required bool video});
}

/// The default seams: a route for chats, nothing yet for the other two.
final class RouterConversationSeams implements ConversationSeams {
  RouterConversationSeams(this._ref);

  final Ref _ref;

  @override
  Future<void> openChat(String conversationId) async {
    _ref
        .read(appRouterProvider)
        .push('/home/chats/${Uri.encodeComponent(conversationId)}');
  }

  @override
  Future<bool> openSharedMedia(String conversationId) async => false;

  @override
  Future<bool> startCall(String accountId, {required bool video}) async =>
      false;
}

/// The seams the people screens call. Tests override it; A2a and A3a fill the
/// methods of [RouterConversationSeams].
final conversationSeamsProvider = Provider<ConversationSeams>(
  RouterConversationSeams.new,
);
