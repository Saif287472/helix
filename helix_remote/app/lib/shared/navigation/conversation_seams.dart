import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/calls/place_call.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';

/// Where the people screens hand over to other features.
///
/// A feature never imports another feature (`test/architecture_test.dart`), so
/// people - which starts chats and calls, and links to a chat's shared media
/// and to a group - cannot call the conversation or calls screens directly.
/// They meet here instead: this interface is the whole contract, and
/// [RouterConversationSeams] fills it in.
///
/// - [openChat]: the conversation route (`chatLocation`; a direct chat is
///   `direct:<account>`, a group `group:<id>`).
/// - [openSharedMedia]: the conversation's media, links and documents page.
/// - [startCall]: `placeCallProvider` (the calls feature), the one seam every
///   call button reads.
abstract interface class ConversationSeams {
  /// Opens a conversation. [conversationId] is `direct:<account>` or
  /// `group:<id>`.
  Future<void> openChat(String conversationId);

  /// Opens the media, links and documents of [conversationId]. False when
  /// that screen could not be opened.
  Future<bool> openSharedMedia(String conversationId);

  /// Starts a one-to-one call. Null when the call started (the full-screen
  /// call opens by itself); otherwise one plain sentence to show the person.
  Future<String?> startCall(String accountId, {required bool video});
}

/// The seams over the router and the calls seam.
final class RouterConversationSeams implements ConversationSeams {
  RouterConversationSeams(this._ref);

  final Ref _ref;

  @override
  Future<void> openChat(String conversationId) async {
    _ref.read(appRouterProvider).push(chatLocation(conversationId));
  }

  @override
  Future<bool> openSharedMedia(String conversationId) async {
    _ref.read(appRouterProvider).push(sharedMediaLocation(conversationId));
    return true;
  }

  @override
  Future<String?> startCall(String accountId, {required bool video}) async {
    final outcome = await _ref.read(placeCallProvider)(accountId, video: video);
    if (outcome.started) return null;
    return outcome.message ?? 'The call could not be placed.';
  }
}

/// The seams the people screens call. Tests override it.
final conversationSeamsProvider = Provider<ConversationSeams>(
  RouterConversationSeams.new,
);
