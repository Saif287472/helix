import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';

class ReceiveMessageCoordinatorImpl implements ReceiveMessageCoordinator {
  ReceiveMessageCoordinatorImpl({
    required this._conversationRepository,
    required this._onNotify,
    required this._isAtCapacity,
    required this._isDuplicate,
    required this._markSeen,
    required this._setAtCapacity,
  });

  final ConversationRepository _conversationRepository;
  final void Function(String threadId) _onNotify;
  final bool Function(String threadId) _isAtCapacity;
  final bool Function(String threadId, String messageId) _isDuplicate;
  final void Function(String threadId, String messageId) _markSeen;
  final void Function(String threadId, bool atCapacity) _setAtCapacity;

  @override
  Future<void> receive(ChatMessage message) async {
    final threadId = message.threadId;
    final thread = _conversationRepository.getThread(threadId);
    if (thread == null) return;

    if (_isDuplicate(threadId, message.messageId)) return;
    _markSeen(threadId, message.messageId);

    if (_isAtCapacity(threadId)) return;

    thread.messages.add(message);
    if (message.origin == MessageOrigin.remote) {
      thread.unreadCount++;
    }

    _enforceCapacity(thread);

    await _conversationRepository.saveThread(thread);
    _onNotify(threadId);
  }

  void _enforceCapacity(ChatThread thread) {
    if (thread.messages.length > kMaxThreadMessages ||
        thread.totalBytes > kMaxThreadBytes) {
      _setAtCapacity(thread.threadId, true);
    }
  }
}
