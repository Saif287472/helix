import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/domain/models.dart';

class DeliveryReceiptTrackerImpl implements DeliveryReceiptTracker {
  DeliveryReceiptTrackerImpl({
    required this._conversationRepository,
    required this._onNotify,
  });

  final ConversationRepository _conversationRepository;
  final void Function(String threadId) _onNotify;

  @override
  Future<void> markDelivered(String messageId) async {
    for (final thread in _conversationRepository.listThreads()) {
      var changed = false;
      for (var i = 0; i < thread.messages.length; i++) {
        final m = thread.messages[i];
        if (m.messageId == messageId &&
            m.deliveryStatus == MessageDeliveryStatus.sending) {
          thread.messages[i] = m.copyWith(
            deliveryStatus: MessageDeliveryStatus.delivered,
          );
          changed = true;
        }
      }
      if (changed) {
        await _conversationRepository.saveThread(thread);
        _onNotify(thread.threadId);
        return;
      }
    }
  }

  @override
  Future<void> markRead(String messageId) async {
    for (final thread in _conversationRepository.listThreads()) {
      var changed = false;
      for (var i = 0; i < thread.messages.length; i++) {
        final m = thread.messages[i];
        if (m.messageId == messageId &&
            m.deliveryStatus != MessageDeliveryStatus.read) {
          thread.messages[i] = m.copyWith(
            deliveryStatus: MessageDeliveryStatus.read,
          );
          changed = true;
        }
      }
      if (changed) {
        await _conversationRepository.saveThread(thread);
        _onNotify(thread.threadId);
        return;
      }
    }
  }
}
