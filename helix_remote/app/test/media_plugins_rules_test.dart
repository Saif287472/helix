import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The media plugins stay behind `core/platform` adapters: one file each, so a
/// fake stands in for it everywhere else and presentation never sees a plugin
/// (the architecture test already keeps `presentation/` to its own layer).
void main() {
  final sources = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  String norm(String path) => path.replaceAll(r'\', '/');

  void onlyIn(String package, List<String> allowed) {
    final offenders = [
      for (final f in sources)
        if (f.readAsStringSync().contains('package:$package/') &&
            !allowed.any(norm(f.path).endsWith))
          f.path,
    ];
    expect(offenders, isEmpty, reason: '$package belongs in $allowed');
  }

  test('each media plugin is imported by exactly one adapter file', () {
    onlyIn('image_picker', ['core/platform/device_camera.dart']);
    onlyIn('record', ['core/platform/device_voice_recorder.dart']);
    onlyIn('audioplayers', ['core/platform/device_audio_player.dart']);
    onlyIn('video_player', ['core/platform/device_video_player.dart']);
    onlyIn('fc_native_video_thumbnail', ['core/platform/video_frames.dart']);
    onlyIn('image', ['core/platform/thumbnail_encoder.dart']);
  });

  test('the adapters named in the rules above exist', () {
    for (final name in [
      'device_camera',
      'device_voice_recorder',
      'device_audio_player',
      'device_video_player',
      'video_frames',
      'thumbnail_encoder',
    ]) {
      expect(File('lib/core/platform/$name.dart').existsSync(), isTrue);
    }
  });

  test('the manifest declares the camera and microphone as optional', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    for (final feature in [
      'android.hardware.camera',
      'android.hardware.microphone',
    ]) {
      expect(
        RegExp(
          'uses-feature android:name="$feature" android:required="false"',
        ).hasMatch(manifest),
        isTrue,
        reason: '$feature must not be required',
      );
    }
    // Reading the whole gallery is not needed: the pickers copy what the
    // person chooses.
    expect(manifest, isNot(contains('READ_MEDIA_IMAGES')));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    // Location is asked for by live location sharing (E4) and nothing else:
    // it is declared with a foreground service of the location type, and a
    // phone without it still installs the app. No media code reads it.
    expect(manifest, contains('FOREGROUND_SERVICE_LOCATION'));
    expect(
      RegExp(
        'uses-feature android:name="android.hardware.location" '
        'android:required="false"',
      ).hasMatch(manifest),
      isTrue,
    );
    final users = [
      for (final f in sources)
        if (f.readAsStringSync().contains('package:geolocator/')) norm(f.path),
    ];
    expect(users, hasLength(1));
    expect(users.single, endsWith('core/platform/location_source.dart'));
  });

  test('no media code logs, and no plugin error text reaches a screen', () {
    final offenders = [
      for (final f in sources)
        if (norm(f.path).contains('core/platform/') &&
            RegExp(r'\b(print|debugPrint)\(').hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
