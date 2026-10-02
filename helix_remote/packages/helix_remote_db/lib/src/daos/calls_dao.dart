import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/groups.dart';

part 'calls_dao.g.dart';

/// The call log, for the Calls tab.
///
/// It holds the *fact* of a call and its timings, nothing else: the SDP, the ICE
/// candidates and the caller's audio/video choice travel as sealed, ephemeral
/// signals and are never written down (CRYPTO_V2.md §10).
@DriftAccessor(tables: [CallLog])
class CallsDao extends DatabaseAccessor<HelixDb> with _$CallsDaoMixin {
  CallsDao(super.attachedDatabase);

  Future<CallLogRow?> byId(String callId) => (select(
    callLog,
  )..where((c) => c.callId.equals(callId))).getSingleOrNull();

  /// The log, newest first.
  Future<List<CallLogRow>> recent({int limit = 50}) =>
      (select(callLog)
            ..orderBy([(c) => OrderingTerm.desc(c.startedAt)])
            ..limit(limit))
          .get();

  Stream<List<CallLogRow>> watchRecent({int limit = 50}) =>
      (select(callLog)
            ..orderBy([(c) => OrderingTerm.desc(c.startedAt)])
            ..limit(limit))
          .watch();

  /// The log for one peer, newest first. The Calls tab groups consecutive calls
  /// with the same person into one row, so this is what it reads.
  Stream<List<CallLogRow>> watchWithPeer(
    String peerAccountId, {
    int limit = 50,
  }) =>
      (select(callLog)
            ..where((c) => c.peerAccountId.equals(peerAccountId))
            ..orderBy([(c) => OrderingTerm.desc(c.startedAt)])
            ..limit(limit))
          .watch();

  /// Records a call when it starts.
  ///
  /// The id is the server's, so a call this device joins from a pending call
  /// and one it starts are the same row.
  Future<void> start(CallLogCompanion call) =>
      into(callLog).insertOnConflictUpdate(call);

  /// Marks the moment the call connected, which is what a duration is measured
  /// from: ringing time is not talk time.
  Future<void> answered(String callId, {required DateTime at}) =>
      (update(callLog)..where((c) => c.callId.equals(callId))).write(
        CallLogCompanion(state: const Value('active'), answeredAt: Value(at)),
      );

  /// Ends the call and its timings.
  Future<void> end(
    String callId, {
    required String state,
    required DateTime at,
  }) => (update(callLog)..where((c) => c.callId.equals(callId))).write(
    CallLogCompanion(state: Value(state), endedAt: Value(at)),
  );

  /// Calls that are still marked active, so a crash or a revoked device does
  /// not leave one ringing forever in the log.
  Future<List<CallLogRow>> unfinished() =>
      (select(callLog)
            ..where((c) => c.state.equals('active') | c.state.equals('ringing'))
            ..orderBy([(c) => OrderingTerm.asc(c.startedAt)]))
          .get();

  /// How long a call ran, in seconds, or null when it was never answered.
  ///
  /// A missed call has no duration at all rather than a zero one, so the UI can
  /// tell "did not connect" from "hung up at once".
  static int? durationSeconds(CallLogRow call) {
    final answered = call.answeredAt;
    final ended = call.endedAt;
    if (answered == null || ended == null) return null;
    return ended.difference(answered).inSeconds;
  }

  /// Whether this call was missed: somebody called this device and it was never
  /// answered. A call this device placed that nobody picked up is not a missed
  /// call, and one it declined was seen.
  static bool wasMissed(CallLogRow call) =>
      call.direction == 'missed' ||
      (call.direction == 'incoming' &&
          call.answeredAt == null &&
          (call.state == 'ended' || call.state == 'missed'));

  /// Removes a call's row. Used when the log is purged; the row holds no
  /// content, but a person's call history is still theirs.
  Future<void> forget(String callId) =>
      (delete(callLog)..where((c) => c.callId.equals(callId))).go();
}
