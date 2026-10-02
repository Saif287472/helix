import 'dart:math';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The clock the engine reads. Injected so tests control time and so no
/// engine code calls `DateTime.now()`.
typedef Clock = DateTime Function();

/// [Random] over the engine's injected [CryptoRandom], for UUIDs and retry
/// jitter. Not a replacement for the CSPRNG where keys are made: key
/// generation takes the [CryptoRandom] directly.
final class RandomAdapter implements Random {
  RandomAdapter(this._source);

  final CryptoRandom _source;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() {
    var value = 0;
    for (final b in _source.nextBytes(7)) {
      value = value * 256 + b;
    }
    return (value & 0x1fffffffffffff) / 9007199254740992.0; // 2^53
  }

  @override
  int nextInt(int max) {
    if (max <= 0 || max > 0x100000000) {
      throw RangeError.range(max, 1, 0x100000000, 'max');
    }
    var value = 0;
    for (final b in _source.nextBytes(7)) {
      value = value * 256 + b;
    }
    return (value & 0x1fffffffffffff) % max;
  }
}

/// New ids: UUIDv7 from the injected clock and randomness.
final class IdFactory {
  IdFactory(this._clock, CryptoRandom random) : _random = RandomAdapter(random);

  final Clock _clock;
  final RandomAdapter _random;

  /// A new message, device, account or link id.
  String next() => Uuid.v7(now: _clock().toUtc(), random: _random);

  double jitter() => _random.nextDouble();
}
