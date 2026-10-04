import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_settings_screen.dart';
import 'package:helix_remote/features/conversation/presentation/forward_screen.dart';
import 'package:helix_remote/features/conversation/presentation/media_viewer_screen.dart';
import 'package:helix_remote/features/conversation/presentation/message_info_screen.dart';
import 'package:helix_remote/features/conversation/presentation/send_files_screen.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';

/// The routes the conversation feature owns. They sit above the home shell,
/// so back returns to whichever tab opened the conversation. The router adds
/// these to its route list.
final List<RouteBase> conversationRoutes = [
  GoRoute(
    path: ChatRoutes.conversation,
    builder: (context, state) => ConversationScreen(
      // go_router has already decoded the path parameter.
      conversationId: state.pathParameters['conversationId']!,
      messageId: state.uri.queryParameters['m'],
    ),
    routes: [
      GoRoute(
        path: 'media/:rowid',
        builder: (context, state) => MediaViewerScreen(
          rowid: int.parse(state.pathParameters['rowid']!),
          initialIndex: int.tryParse(state.uri.queryParameters['i'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: 'forward',
        builder: (context, state) => ForwardScreen(
          conversationId: state.pathParameters['conversationId']!,
          rowids: [
            for (final id in (state.uri.queryParameters['ids'] ?? '').split(
              ',',
            ))
              ?int.tryParse(id),
          ],
        ),
      ),
      GoRoute(
        path: 'info/:rowid',
        builder: (context, state) =>
            MessageInfoScreen(rowid: int.parse(state.pathParameters['rowid']!)),
      ),
      GoRoute(
        path: 'settings',
        builder: (context, state) => ConversationSettingsScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        path: 'send-files',
        builder: (context, state) => SendFilesScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
    ],
  ),
];
