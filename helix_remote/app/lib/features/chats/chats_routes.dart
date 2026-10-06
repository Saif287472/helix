import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/chats/presentation/archived_chats_screen.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';

/// The routes the chats feature owns. The list itself is the Chats tab (a
/// child of the home screen, not a route); the archived list is a page above
/// it. The router adds these to its route list.
final List<RouteBase> chatsRoutes = [
  GoRoute(
    path: ChatRoutes.archived,
    builder: (context, state) => const ArchivedChatsScreen(),
  ),
];
