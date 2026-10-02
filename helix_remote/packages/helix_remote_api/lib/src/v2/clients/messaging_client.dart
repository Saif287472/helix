import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `messaging` module: pairwise sends and the REST mailbox. Group sends
/// belong to the `groups` module (`GroupsClient.sendMessage`).
final class MessagingClient {
  const MessagingClient(this._t);

  final HelixTransport _t;

  /// Sends one message to every addressed device. The message id is the
  /// idempotency key, so a retried send is never delivered twice.
  ///
  /// A wrong device list throws `ApiException` with code
  /// `device_list_stale`; its `staleDevices` says what to fix.
  Future<SendMessageResponse> send(SendMessageRequest request) => _t.call(
    Routes.sendMessage,
    SendMessageResponse.fromJson,
    json: request.toJson(),
    idempotencyKey: request.id,
  );

  /// Stored envelopes after [after], oldest first.
  Future<MailboxPage> mailbox({int after = 0, int? limit}) => _t.call(
    Routes.mailbox,
    MailboxPage.fromJson,
    query: {'after': '$after', 'limit': ?limit?.toString()},
  );

  /// Cumulative ack: deletes every stored envelope with `seq <= seq` (and
  /// returns the socket's window credit).
  Future<AckResponse> ack(int seq) => _t.call(
    Routes.ackMailbox,
    AckResponse.fromJson,
    json: AckRequest(seq: seq).toJson(),
  );
}
