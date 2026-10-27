import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Where the phone is, in the units a location message carries.
final class LocationFix {
  const LocationFix({
    required this.latE7,
    required this.lngE7,
    required this.accuracyM,
  });

  /// Degrees times 10^7.
  final int latE7;
  final int lngE7;

  /// Metres, rounded up.
  final int accuracyM;
}

/// Whether the phone will say where it is.
enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// The phone's location, behind one interface (the only file that knows the
/// plugin). Location is read only for something the person started: sending a
/// place, or a live share.
abstract interface class LocationSource {
  /// Whether location can be read; with [ask], the system permission prompt is
  /// shown when it has not been decided yet.
  Future<LocationAccess> access({required bool ask});

  /// One reading, or null when none arrives in time.
  Future<LocationFix?> current();

  /// Readings as the phone moves, until the listener cancels. On Android this
  /// runs as a foreground service with a notification that says a live
  /// location is being shared, so it continues with the screen off.
  Stream<LocationFix> track({required Duration interval});
}

final locationSourceProvider = Provider<LocationSource>(
  (ref) => GeolocatorLocationSource(),
);

/// [LocationSource] on the `geolocator` plugin.
final class GeolocatorLocationSource implements LocationSource {
  @override
  Future<LocationAccess> access({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && ask) {
        permission = await Geolocator.requestPermission();
      }
      return switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        _ => LocationAccess.denied,
      };
    } on Object {
      return LocationAccess.serviceOff;
    }
  }

  @override
  Future<LocationFix?> current() async {
    try {
      return _fix(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Stream<LocationFix> track({required Duration interval}) {
    const title = 'Sharing your live location';
    const text = 'Orbit is sharing where you are. Open Orbit to stop.';
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: interval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: title,
              notificationText: text,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          );
    return Geolocator.getPositionStream(locationSettings: settings).map(_fix);
  }

  static LocationFix _fix(Position p) => LocationFix(
    latE7: (p.latitude * 1e7).round(),
    lngE7: (p.longitude * 1e7).round(),
    accuracyM: p.accuracy.isFinite ? p.accuracy.ceil().clamp(0, 100000) : 0,
  );
}
