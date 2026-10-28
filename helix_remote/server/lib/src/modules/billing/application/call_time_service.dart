import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/billing/api.dart';
import 'package:helix_remote_server/src/modules/billing/data/call_time_store.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// The Free plan's call time (ADR-036): a daily claim of voice and video
/// minutes, set aside when a call's relay credentials are issued and settled
/// when the call ends. The module decides who is metered; this holds the rules.
final class CallTimeService {
  CallTimeService({
    required this.db,
    required this.store,
    required this.clock,
    required this.isMetered,
  });

  final Db db;
  final CallTimeStore store;
  final Clock clock;

  /// Whether the account spends call time: plans on and the Free plan.
  final Future<bool> Function(String accountId) isMetered;

  /// A group call's last leg gets this long before the room is settled.
  static const endGrace = Duration(minutes: 1);

  static const _unlimited = CallTime(unlimited: true, pools: []);

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------- balance

  Future<CallTime> balance(String accountId, {SqlSession? session}) async {
    final s = session ?? db;
    if (!await isMetered(accountId)) return _unlimited;
    final now = clock.now();
    final today = CallTimeLimits.dhakaDay(now);
    final claimed = await store.claimedOn(s, accountId, _dayKey(today));
    final voice = await store.held(s, accountId, CallPool.voice, now);
    final video = await store.held(s, accountId, CallPool.video, now);
    return CallTime(
      unlimited: false,
      pools: [
        CallPoolBalance(
          media: CallPool.voice,
          minutes: voice.minutes,
          dailyMinutes: CallTimeLimits.voiceDaily,
          capMinutes: CallTimeLimits.voiceCap,
          expiresAt: voice.expiresAt,
        ),
        CallPoolBalance(
          media: CallPool.video,
          minutes: video.minutes,
          dailyMinutes: CallTimeLimits.videoDaily,
          capMinutes: CallTimeLimits.videoCap,
          expiresAt: video.expiresAt,
        ),
      ],
      canClaim: !claimed,
      nextClaimAt: claimed
          ? CallTimeLimits.startOf(today.add(const Duration(days: 1)))
          : null,
    );
  }

  Future<CallTime> claim(String accountId) async {
    if (!await isMetered(accountId)) return _unlimited;
    final now = clock.now();
    final today = CallTimeLimits.dhakaDay(now);
    final taken = await db.tx((tx) async {
      await store.lockAccount(tx, accountId);
      return store.insertClaim(
        tx,
        id: Uuid.v7(),
        accountId: accountId,
        day: _dayKey(today),
        now: now,
        expiresAt: CallTimeLimits.startOf(
          today.add(const Duration(days: CallTimeLimits.claimDays)),
        ),
        voice: CallTimeLimits.voiceDaily,
        video: CallTimeLimits.videoDaily,
      );
    });
    if (!taken) {
      throw const ApiError(
        ErrorCode.conflict,
        message: "You already claimed today's call time.",
        details: {'reason': 'already_claimed'},
      );
    }
    return balance(accountId);
  }

  /// The operator's gift: a claim of its own (its own day key, so it never
  /// blocks the daily one) that expires like any claim.
  Future<void> gift(
    Tx tx,
    String accountId, {
    required int voice,
    required int video,
  }) async {
    final now = clock.now();
    final today = CallTimeLimits.dhakaDay(now);
    final id = Uuid.v7();
    await store.insertClaim(
      tx,
      id: id,
      accountId: accountId,
      day: 'gift-$id',
      now: now,
      expiresAt: CallTimeLimits.startOf(
        today.add(const Duration(days: CallTimeLimits.claimDays)),
      ),
      voice: voice,
      video: video,
    );
  }

  // ------------------------------------------------------------------ grant

  CallGrant _of(ReservationRow r, DateTime now) => CallGrant(
    metered: r.metered,
    expiresAt: r.metered
        ? r.expiresAt
        : now.add(CallTimeLimits.unmeteredLifetime),
    pool: r.pool,
  );

  Future<CallGrant> grant({
    required String accountId,
    required String callId,
    required CallRole role,
    required CallPool pool,
    String? roomId,
    String? groupId,
    required bool callerIsRemote,
  }) async {
    final now = clock.now();
    final metered = role == CallRole.caller && await isMetered(accountId);
    return db.tx((tx) async {
      // The two ends of a call, and the legs of a room, take turns.
      await store.lockCall(tx, roomId ?? callId);
      final mapped = await store.forCall(tx, callId);

      if (role == CallRole.callee) {
        if (mapped == null) {
          if (callerIsRemote) {
            return CallGrant(
              metered: false,
              expiresAt: now.add(CallTimeLimits.unmeteredLifetime),
              pool: pool,
            );
          }
          throw const ApiError(
            ErrorCode.conflict,
            message: 'The call has not been started.',
            details: {'reason': 'call_not_started'},
          );
        }
        // The answering side starts the clock: the time is spent from here.
        await store.markAnswered(tx, mapped.id, now);
        return _of(mapped, now);
      }

      if (mapped != null) {
        // The same call asking again (a retry), never someone else's.
        if (mapped.accountId != accountId &&
            (roomId == null || mapped.roomId != roomId)) {
          throw const ApiError(
            ErrorCode.conflict,
            message: 'That call belongs to someone else.',
          );
        }
        // The caller of a one-to-one call asks for the other kind of media:
        // the call switches between voice and video (ADR-036). What has been
        // used is settled in the pool it was spent from, and the rest of the
        // call is reserved from the other.
        if (mapped.pool != pool &&
            mapped.roomId == null &&
            mapped.accountId == accountId &&
            !mapped.finalized) {
          return _switch(tx, callId, mapped, pool, now, metered);
        }
        return _of(mapped, now);
      }

      if (roomId != null) {
        final room = await store.forRoom(tx, roomId);
        if (room != null) {
          // A room belongs to one group: its id opens nothing from another.
          if (room.groupId != groupId) {
            throw const ApiError(
              ErrorCode.conflict,
              message: 'That room belongs to another group.',
              details: {'reason': 'room_group'},
            );
          }
          if (room.finalized) {
            throw const ApiError(
              ErrorCode.conflict,
              message: 'The group call has ended.',
              details: {'reason': 'room_ended'},
            );
          }
          await store.mapCall(
            tx,
            callId: callId,
            reservationId: room.id,
            callerAccount: accountId,
            now: now,
          );
          return _of(room, now);
        }
      }

      final id = Uuid.v7();
      if (!metered) {
        final expires = now.add(CallTimeLimits.unmeteredLifetime);
        await store.insertReservation(
          tx,
          id: id,
          accountId: accountId,
          pool: pool,
          metered: false,
          reserved: 0,
          parts: const [],
          now: now,
          expiresAt: expires,
          roomId: roomId,
          groupId: groupId,
        );
        await store.mapCall(
          tx,
          callId: callId,
          reservationId: id,
          callerAccount: accountId,
          now: now,
        );
        return CallGrant(metered: false, expiresAt: expires, pool: pool);
      }

      await store.lockAccount(tx, accountId);
      // Minutes still held by a call that has ended are free to spend again.
      for (final done in await store.endedOpen(tx, accountId)) {
        await _settle(tx, done, now);
      }
      final taken = await store.takeAll(tx, accountId, pool, now);
      if (taken.total <= 0) {
        throw ApiError(
          ErrorCode.quotaExceeded,
          message:
              'You have no call time left. Claim today\'s minutes or get '
              'Orbit Premium.',
          details: {'reason': 'call_time', 'pool': pool.wire},
        );
      }
      final expires = now.add(Duration(minutes: taken.total));
      await store.insertReservation(
        tx,
        id: id,
        accountId: accountId,
        pool: pool,
        metered: true,
        reserved: taken.total,
        parts: taken.parts,
        now: now,
        expiresAt: expires,
        roomId: roomId,
        groupId: groupId,
      );
      await store.mapCall(
        tx,
        callId: callId,
        reservationId: id,
        callerAccount: accountId,
        now: now,
      );
      return CallGrant(metered: true, expiresAt: expires, pool: pool);
    });
  }

  /// Moves a one-to-one call to [pool]: settles the old reservation up to now
  /// (each started minute, in the pool it came from) and reserves the rest of
  /// the call from [pool]. Throws (so nothing changes) when the new pool is
  /// empty.
  Future<CallGrant> _switch(
    Tx tx,
    String callId,
    ReservationRow old,
    CallPool pool,
    DateTime now,
    bool metered,
  ) async {
    await store.lockAccount(tx, old.accountId);
    await store.markEnded(tx, old.id, now);
    final settled = await store.byId(tx, old.id);
    if (settled != null) await _settle(tx, settled, now);
    for (final done in await store.endedOpen(tx, old.accountId)) {
      await _settle(tx, done, now);
    }
    final id = Uuid.v7();
    var reserved = 0;
    var parts = const <({String claim, int minutes})>[];
    var expires = now.add(CallTimeLimits.unmeteredLifetime);
    if (metered) {
      final taken = await store.takeAll(tx, old.accountId, pool, now);
      if (taken.total <= 0) {
        throw ApiError(
          ErrorCode.quotaExceeded,
          message:
              'You have no ${pool.wire} call time left. Claim today\'s '
              'minutes or get Orbit Premium.',
          details: {'reason': 'call_time', 'pool': pool.wire},
        );
      }
      reserved = taken.total;
      parts = taken.parts;
      expires = now.add(Duration(minutes: taken.total));
    }
    await store.insertReservation(
      tx,
      id: id,
      accountId: old.accountId,
      pool: pool,
      metered: metered,
      reserved: reserved,
      parts: parts,
      now: now,
      expiresAt: expires,
    );
    await store.markAnswered(tx, id, now);
    await store.remapCall(tx, callId, id);
    return CallGrant(metered: metered, expiresAt: expires, pool: pool);
  }

  // ----------------------------------------------------------------- settle

  /// Spends what the call used (each started minute, from the answer to the
  /// last end or the end of the reservation) and gives the rest back.
  Future<void> _settle(Tx tx, ReservationRow r, DateTime now) async {
    if (r.finalized) return;
    var used = 0;
    if (r.metered && r.answeredAt != null) {
      final end = r.lastEndAt ?? r.expiresAt;
      final until = end.isAfter(r.expiresAt) ? r.expiresAt : end;
      final seconds = until.difference(r.answeredAt!).inSeconds;
      used = (seconds <= 0 ? 1 : (seconds + 59) ~/ 60).clamp(1, r.reserved);
    }
    final back = r.metered ? r.reserved - used : 0;
    if (back > 0) {
      await store.refund(tx, r.parts, r.pool, back, now);
    }
    await store.markFinalized(tx, r.id, used, now);
  }

  Future<void> callEnded(
    String callId, {
    required String by,
    required bool isParty,
  }) async {
    final now = clock.now();
    await db.tx((tx) async {
      final r = await store.forCall(tx, callId);
      if (r == null || r.finalized) return;
      if (!isParty && r.accountId != by) return;
      await store.markEnded(tx, r.id, now);
      // A one-to-one call is over; a group call waits for its other legs.
      if (r.roomId == null) {
        final fresh = await store.byId(tx, r.id);
        if (fresh != null) await _settle(tx, fresh, now);
      }
    });
  }

  /// The periodic settle of reservations that are over.
  Future<void> settleDue() async {
    final now = clock.now();
    for (final id in await store.due(db, now, endGrace)) {
      await db.tx((tx) async {
        final r = await store.byId(tx, id);
        if (r != null) await _settle(tx, r, now);
      });
    }
  }
}
