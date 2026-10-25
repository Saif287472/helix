import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';

/// Where the info page of a conversation is: the other person's contact info
/// for a direct chat, the group's info for a group chat. Both belong to other
/// features (people, groups), so only their shared paths are known here.
/// Null for anything that is neither - and for the chat you keep your notes
/// in, whose peer is this device's own account: there is no contact info of
/// yourself to open, and rename, block or report are all meaningless there.
String? infoLocationOf(String conversationId, {String? selfAccount}) {
  final peer = peerOfConversation(conversationId);
  if (peer != null) {
    return peer == selfAccount ? null : PeoplePaths.person(peer);
  }
  final group = groupIdOf(conversationId);
  return group == null ? null : GroupPaths.info(group);
}

/// [infoLocationOf] with this device's own account id, so a screen asks one
/// question about its conversation and never reaches for the gateway itself.
final conversationInfoRouteProvider = Provider.autoDispose
    .family<String?, String>(
      (ref, conversationId) => infoLocationOf(
        conversationId,
        selfAccount: ref.watch(chatGatewayProvider).value?.selfAccountId,
      ),
    );
