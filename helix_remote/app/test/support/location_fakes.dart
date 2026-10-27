import 'dart:async';

import 'package:helix_remote/core/platform/location_source.dart';

/// A phone whose location the test controls.
final class FakeLocationSource implements LocationSource {
  LocationAccess granted = LocationAccess.granted;
  LocationFix? here = const LocationFix(
    latE7: 236810000,
    lngE7: 903560000,
    accuracyM: 12,
  );

  /// Whether the permission prompt was shown (an `ask: true` call).
  int asked = 0;

  /// Whether the position stream is being listened to.
  bool tracking = false;

  final _moves = StreamController<LocationFix>.broadcast();

  void move(LocationFix fix) => _moves.add(fix);

  @override
  Future<LocationAccess> access({required bool ask}) async {
    if (ask) asked++;
    return granted;
  }

  @override
  Future<LocationFix?> current() async => here;

  @override
  Stream<LocationFix> track({required Duration interval}) {
    late StreamController<LocationFix> out;
    StreamSubscription<LocationFix>? inner;
    out = StreamController<LocationFix>(
      onListen: () {
        tracking = true;
        inner = _moves.stream.listen(out.add);
      },
      onCancel: () async {
        tracking = false;
        await inner?.cancel();
      },
    );
    return out.stream;
  }
}
