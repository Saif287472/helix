// The call and outbox lifecycles used to be enforced only by `WHERE status
// = ...` clauses on the update statements. That is silent: an update that
// violates the lifecycle matches zero rows and still reports success, so a
// caller in the wrong order sees no error and the row just doesn't change.
//
// These tests cover both halves of the fix - the transition tables
// themselves, and the repository writes that now consult them.

import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteCallRoomStatus', () {
    test('a room opens waiting, activates once, and ends permanently', () {
      RemoteCallRoomStatus.validateTransition(
        RemoteCallRoomStatus.waiting,
        RemoteCallRoomStatus.active,
      );
      RemoteCallRoomStatus.validateTransition(
        RemoteCallRoomStatus.active,
        RemoteCallRoomStatus.ended,
      );
      // A host ending a room nobody joined is routine, not an error.
      RemoteCallRoomStatus.validateTransition(
        RemoteCallRoomStatus.waiting,
        RemoteCallRoomStatus.ended,
      );
      expect(RemoteCallRoomStatus.isTerminal(RemoteCallRoomStatus.ended), true);
    });

    test('an ended room cannot be reopened', () {
      expect(
        () => RemoteCallRoomStatus.validateTransition(
          RemoteCallRoomStatus.ended,
          RemoteCallRoomStatus.active,
        ),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });

    test('an unknown source status is rejected rather than assumed', () {
      expect(
        () => RemoteCallRoomStatus.validateTransition(
          'PAUSED',
          RemoteCallRoomStatus.ended,
        ),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });
  });

  group('RemoteCallRoomParticipantStatus', () {
    test('a participant may drop off and rejoin', () {
      RemoteCallRoomParticipantStatus.validateTransition(
        RemoteCallRoomParticipantStatus.joined,
        RemoteCallRoomParticipantStatus.left,
      );
      RemoteCallRoomParticipantStatus.validateTransition(
        RemoteCallRoomParticipantStatus.left,
        RemoteCallRoomParticipantStatus.joined,
      );
    });

    test('a kick outlasts a reconnect attempt', () {
      // If kicked -> joined were legal, being kicked would achieve nothing:
      // the removed device could simply rejoin.
      expect(
        () => RemoteCallRoomParticipantStatus.validateTransition(
          RemoteCallRoomParticipantStatus.kicked,
          RemoteCallRoomParticipantStatus.joined,
        ),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });
  });

  group('RemoteCallSessionStatus', () {
    test('caller and callee paths both converge on connecting', () {
      RemoteCallSessionStatus.validateTransition(
        RemoteCallSessionStatus.dialing,
        RemoteCallSessionStatus.connecting,
      );
      RemoteCallSessionStatus.validateTransition(
        RemoteCallSessionStatus.ringing,
        RemoteCallSessionStatus.connecting,
      );
    });

    test('active and reconnecting cycle for ICE restarts', () {
      RemoteCallSessionStatus.validateTransition(
        RemoteCallSessionStatus.active,
        RemoteCallSessionStatus.reconnecting,
      );
      RemoteCallSessionStatus.validateTransition(
        RemoteCallSessionStatus.reconnecting,
        RemoteCallSessionStatus.active,
      );
    });

    test('every ending is terminal - a retry is a new call', () {
      for (final terminal in [
        RemoteCallSessionStatus.declined,
        RemoteCallSessionStatus.busy,
        RemoteCallSessionStatus.failed,
        RemoteCallSessionStatus.ended,
      ]) {
        expect(
          RemoteCallSessionStatus.isTerminal(terminal),
          true,
          reason: terminal,
        );
        expect(
          () => RemoteCallSessionStatus.validateTransition(
            terminal,
            RemoteCallSessionStatus.active,
          ),
          throwsA(isA<RemoteIllegalStatusTransitionException>()),
          reason: terminal,
        );
      }
    });
  });

  group('RemoteGroupCallStatus', () {
    test('a cancelled join returns to idle', () {
      RemoteGroupCallStatus.validateTransition(
        RemoteGroupCallStatus.joining,
        RemoteGroupCallStatus.idle,
      );
    });

    test('a finished call is reusable for the next one', () {
      RemoteGroupCallStatus.validateTransition(
        RemoteGroupCallStatus.ended,
        RemoteGroupCallStatus.idle,
      );
    });

    test('a call cannot go active without joining first', () {
      expect(
        () => RemoteGroupCallStatus.validateTransition(
          RemoteGroupCallStatus.idle,
          RemoteGroupCallStatus.active,
        ),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });
  });

  group('RemoteOutboxStatus', () {
    test('a failed event is retryable', () {
      RemoteOutboxStatus.validateTransition(
        RemoteOutboxStatus.failed,
        RemoteOutboxStatus.pending,
      );
      RemoteOutboxStatus.validateTransition(
        RemoteOutboxStatus.pending,
        RemoteOutboxStatus.completed,
      );
    });

    test('a delivered event is never requeued', () {
      expect(
        () => RemoteOutboxStatus.validateTransition(
          RemoteOutboxStatus.completed,
          RemoteOutboxStatus.pending,
        ),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });

    test('a dead-lettered event is never retried back into the queue', () {
      // Parking an event in DLQ is an operator decision; silently pulling it
      // back out would redeliver something deliberately held back.
      for (final to in [
        RemoteOutboxStatus.pending,
        RemoteOutboxStatus.failed,
        RemoteOutboxStatus.completed,
      ]) {
        expect(
          () =>
              RemoteOutboxStatus.validateTransition(RemoteOutboxStatus.dlq, to),
          throwsA(isA<RemoteIllegalStatusTransitionException>()),
          reason: to,
        );
      }
    });
  });

  group('enforcement at the repository boundary', () {
    late BackendDatabase db;

    setUp(() => db = BackendDatabase(sqlite3.openInMemory()));

    test('joining an ended room fails loudly instead of doing nothing', () {
      const roomId = 'room_ended';
      db.createCallRoom(
        roomId: roomId,
        hostAccountId: 'alice',
        hostDeviceId: 'alice_phone',
        isVideo: false,
        now: 1000,
      );
      db.endCallRoom(roomId, 2000);
      expect(db.getCallRoom(roomId)!['status'], 'ENDED');

      expect(
        () => db.joinCallRoom(
          roomId: roomId,
          accountId: 'bob',
          deviceId: 'bob_phone',
          now: 3000,
        ),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });

    test('ending a room twice stays idempotent', () {
      const roomId = 'room_twice';
      db.createCallRoom(
        roomId: roomId,
        hostAccountId: 'alice',
        hostDeviceId: 'alice_phone',
        isVideo: false,
        now: 1000,
      );
      // Both the host's explicit end and the last participant leaving can
      // reach this; whichever arrives second must not throw.
      db.endCallRoom(roomId, 2000);
      db.endCallRoom(roomId, 2500);
      expect(db.getCallRoom(roomId)!['status'], 'ENDED');
      expect(db.getCallRoom(roomId)!['ended_at'], 2000);
    });

    test('a first join activates a waiting room', () {
      const roomId = 'room_join';
      db.createCallRoom(
        roomId: roomId,
        hostAccountId: 'alice',
        hostDeviceId: 'alice_phone',
        isVideo: false,
        now: 1000,
      );
      expect(db.getCallRoom(roomId)!['status'], 'WAITING');
      db.inviteToRoom(roomId: roomId, accountId: 'bob', deviceId: 'bob_phone');
      expect(
        db.joinCallRoom(
          roomId: roomId,
          accountId: 'bob',
          deviceId: 'bob_phone',
          now: 1500,
        ),
        isTrue,
      );
      expect(db.getCallRoom(roomId)!['status'], 'ACTIVE');
    });

    test('a completed outbox event cannot be requeued', () {
      db.enqueueOutbox('evt_1', 'S2S_GROUP_SYNC', '{}');
      db.updateOutboxStatus('evt_1', RemoteOutboxStatus.completed, 0);
      expect(
        () => db.updateOutboxStatus('evt_1', RemoteOutboxStatus.pending, 1),
        throwsA(isA<RemoteIllegalStatusTransitionException>()),
      );
    });
  });

  test('an illegal transition surfaces as a 409, not a 500', () async {
    // Without the middleware clause this would fall into the generic
    // catch-all and report a server fault for what is a client ordering
    // mistake.
    final handler = withAppErrorHandling((_) async {
      throw RemoteIllegalStatusTransitionException(
        'Illegal call room status transition: ENDED → ACTIVE',
        from: 'ENDED',
        to: 'ACTIVE',
      );
    });
    final response = await handler(
      Request('POST', Uri.parse('http://localhost/api/v1/group-calls/join')),
    );
    expect(response.statusCode, 409);
    final body = await response.readAsString();
    expect(body, contains('code'));
    expect(body, contains('conflict'));
    expect(body, contains('ENDED'));
  });
}
