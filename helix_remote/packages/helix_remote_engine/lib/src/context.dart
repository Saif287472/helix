import 'dart:async';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/config.dart';
import 'package:helix_remote_engine/src/crypto/db_stores.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/util/ids.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';

/// What every engine component shares: the injected collaborators, the
/// signed-in identity, per-device locks and the event sink. One per
/// [Engine]; nothing here is global, so two engines (Alice and Bob in a
/// test, the app and an FCM isolate) never interfere.
final class EngineContext {
  EngineContext({
    required this.api,
    required this.db,
    required this.clock,
    required this.random,
    required this.config,
  }) : ids = IdFactory(clock, random),
       sessionStore = DbSessionStore(db),
       prekeyStore = DbPrekeyStore(db);

  final HelixApi api;
  final HelixDb db;
  final Clock clock;
  final CryptoRandom random;
  final EngineConfig config;

  final IdFactory ids;
  final DbSessionStore sessionStore;
  final DbPrekeyStore prekeyStore;

  /// Serialises ratchet state per remote device (CRYPTO_V2.md §14).
  final KeyedLock<DeviceAddress> deviceLocks = KeyedLock();

  final StreamController<EngineEvent> _events = StreamController.broadcast();

  LocalIdentity? _identity;

  /// The signed-in identity. Throws [NotSignedInException] when there is
  /// none.
  LocalIdentity get identity =>
      _identity ?? (throw const NotSignedInException());

  bool get isSignedIn => _identity != null;

  void setIdentity(LocalIdentity? identity) => _identity = identity;

  DateTime now() => clock().toUtc();

  Stream<EngineEvent> get events => _events.stream;

  void emit(EngineEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> close() => _events.close();
}
