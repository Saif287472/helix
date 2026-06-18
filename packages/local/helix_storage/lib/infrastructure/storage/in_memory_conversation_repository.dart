import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_domain/domain/models.dart';

class InMemoryConversationRepository implements ConversationRepository {
  final Map<String, ChatThread> _threads = {};

  @override
  List<ChatThread> listThreads() {
    return _threads.values.toList();
  }

  @override
  ChatThread? getThread(String threadId) {
    return _threads[threadId];
  }

  @override
  Future<void> saveThread(ChatThread thread) async {
    _threads[thread.threadId] = thread;
  }

  @override
  Future<void> removeThread(String threadId) async {
    _threads.remove(threadId);
  }
}
