import 'dart:math';

import 'package:helix_local_groups/domain/lobby_constants.dart';

/// Returns how long this device should wait before self-electing as host.
///
/// [localFp] must be present in [candidateFps] (survivors sorted ascending).
/// If not found (e.g. cold-start with empty list), rank defaults to 0.
Duration electionDelay(String localFp, List<String> candidateFps) {
  final sorted = List<String>.from(candidateFps)..sort();
  final rank = sorted.indexOf(localFp).clamp(0, sorted.length);
  final jitter = Random().nextInt(kLobbyElectionJitterNoise);
  return kLobbyElectionJitterBase * rank + Duration(milliseconds: jitter);
}

/// Returns true when the local device loses the conflict-resolution race.
///
/// [incomingGen] / [incomingHostFp] come from a received ANNOUNCE.
/// Higher generation always wins; ties broken by lexicographically lower fp.
bool localLosesConflict({
  required int localGen,
  required String localFp,
  required int incomingGen,
  required String incomingHostFp,
}) {
  if (incomingGen > localGen) {
    return true;
  }
  if (incomingGen == localGen && incomingHostFp.compareTo(localFp) < 0) {
    return true;
  }
  return false;
}

/// Returns the fingerprint of the preferred next host from [candidates]
/// (the member with the lexicographically lowest fp, excluding [excludeFp]).
String? pickNextHost(List<String> candidates, String excludeFp) {
  final eligible = candidates.where((fp) => fp != excludeFp).toList()..sort();
  return eligible.isEmpty ? null : eligible.first;
}
