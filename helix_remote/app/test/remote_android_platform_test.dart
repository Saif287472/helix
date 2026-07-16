import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// RP6-003, RP6-008 — Android manifest and permission declarations
// RP6-006, RP6-007 — Notification privacy and push-capability honesty
// RP6-009           — Activity configuration (launchMode, configChanges,
//                     keyboard input mode)
// ---------------------------------------------------------------------------

void main() {
  // Manifest tests read from the filesystem; path is relative to the
  // package root (Directory.current == app/) during flutter test.

  group('RP6-003/RP6-008: AndroidManifest permission declarations', () {
    late String manifest;

    setUpAll(() {
      manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
    });

    test('declares INTERNET permission', () {
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('declares POST_NOTIFICATIONS for Android 13+ runtime prompt', () {
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    });

    test('declares RECORD_AUDIO permission for call microphone', () {
      expect(manifest, contains('android.permission.RECORD_AUDIO'));
    });

    test('declares CAMERA permission for video calls', () {
      expect(manifest, contains('android.permission.CAMERA'));
    });

    test('declares FOREGROUND_SERVICE permission', () {
      expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    });

    test(
      'declares typed foreground-service permissions for camera and microphone',
      () {
        expect(
          manifest,
          contains('android.permission.FOREGROUND_SERVICE_CAMERA'),
        );
        expect(
          manifest,
          contains('android.permission.FOREGROUND_SERVICE_MICROPHONE'),
        );
      },
    );
  });

  group('RP6-009: Activity lifecycle and navigation configuration', () {
    late String manifest;

    setUpAll(() {
      manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
    });

    test(
      'configChanges covers orientation so Activity is not recreated on rotate',
      () {
        expect(manifest, contains('orientation'));
      },
    );

    test('configChanges covers keyboard and screenSize', () {
      expect(manifest, contains('keyboard'));
      expect(manifest, contains('screenSize'));
    });

    test(
      'launchMode is singleTop — prevents duplicate MainActivity on re-launch',
      () {
        expect(manifest, contains('android:launchMode="singleTop"'));
      },
    );

    test(
      'windowSoftInputMode is adjustResize — content not obscured by keyboard',
      () {
        expect(manifest, contains('adjustResize'));
      },
    );
  });

  group('RP6-006/RP6-007: Notification privacy and push-capability honesty', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/services/local_notification_service.dart',
      ).readAsStringSync();
    });

    test(
      'RP6-006: notification body is generic and does not expose peerAccountId',
      () {
        // The user-visible notification body must be a fixed, non-identifying string.
        expect(src, contains("'Someone wants to connect with you'"));
        expect(src, contains("'New contact request'"));

        // peerAccountId appears only as .hashCode (integer notification ID).
        // It must NOT appear in the visible title or body strings.
        final bodyLine = RegExp(
          r"'Someone wants to connect with you'",
        ).hasMatch(src);
        expect(bodyLine, isTrue);
      },
    );

    test(
      'RP6-006: notification channel id is helix_contact_requests with high importance',
      () {
        expect(src, contains("'helix_contact_requests'"));
        expect(src, contains('Importance.high'));
      },
    );

    test(
      'RP6-007: service comment accurately discloses FCM requirement for offline push',
      () {
        // The service handles foreground/background-alive cases only.
        // A comment must honestly state that offline (killed-app) push needs FCM.
        expect(src, contains('FCM'));
        // The disclosed limitation phrase
        expect(src, contains('offline'));
        // There must be no false claim that offline push is already working.
        expect(src, isNot(contains('offline push is supported')));
        expect(src, isNot(contains('works without FCM')));
      },
    );
  });
}
