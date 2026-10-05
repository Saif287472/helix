import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/security/app_lock.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/application/start_call.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/call_support.dart';
import '../support/names_support.dart';

/// The call screen's state machine, driven by the engine's REAL call service
/// over its in-memory network: every transition the screen draws comes from a
/// genuine signalling exchange with a second device, not from a hand-built
/// snapshot.
void main() {
  late TestClock clock;
  late FakeCallNetwork net;
  late CallDevice me;
  late CallDevice bob;
  late FakeCallPermissions permissions;
  late FakeCallPlatform platform;
  late FakeRinger ringer;
  late FakeAudioPlatform audio;
  late CallMediaHub hub;
  late ProviderContainer container;

  final names = directoryOf(const {
    'account-bob': HelixPersonNames(
      phoneBookName: 'Bob Builder',
      number: '+8801711000002',
    ),
  });

  Future<void> setUpDevices() async {
    clock = TestClock();
    net = FakeCallNetwork(clock);
    me = await net.add('me');
    bob = await net.add('bob');
    permissions = FakeCallPermissions();
    platform = FakeCallPlatform();
    ringer = FakeRinger();
    audio = FakeAudioPlatform();
    hub = CallMediaHub();
    container = ProviderContainer(
      overrides: callOverrides(
        port: me.port,
        permissions: permissions,
        platform: platform,
        ringer: ringer,
        audio: audio,
        hub: hub,
        names: names,
        clock: clock.call,
        linger: const Duration(milliseconds: 200),
      ),
    );
    // Keep the derived providers alive, as the call host does.
    container.listen(callScreenStateProvider, (_, _) {});
    container.listen(callElapsedProvider, (_, _) {});
    container.read(callEffectsProvider);
    container.listen(peopleDirectoryProvider, (_, _) {});
    await container.read(peopleDirectoryProvider.future);
  }

  setUp(setUpDevices);

  tearDown(() async {
    container.dispose();
    await net.dispose();
    AppLock.callInProgress.value = false;
  });

  CallScreenState? screen() => container.read(callScreenStateProvider);

  Future<void> untilScreen(
    bool Function(CallScreenState? state) check, [
    String reason = 'screen state',
  ]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!check(screen())) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $reason; at ${screen()?.stage}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  PlaceCall place() => container.read(startCallProvider);

  group('an outgoing call', () {
    test('dials, rings, connects, mutes and hangs up', () async {
      final outcome = await place()(bob.account, video: false);
      expect(outcome.started, isTrue);
      expect(permissions.asked, [false]);

      await untilScreen((s) => s?.stage == CallStage.dialing);
      expect(screen()!.title, 'Bob Builder');
      expect(screen()!.subtitle, '+8801711000002');
      expect(screen()!.incoming, isFalse);

      // Bob's device is ringing, so the caller's screen says Ringing.
      await bob.untilPhase(CallPhase.ringing);
      await untilScreen((s) => s?.statusText == 'Ringing…', 'ringing');

      await bob.service.accept();
      await untilScreen((s) => s?.stage == CallStage.active, 'active');
      expect(screen()!.statusText, 'Connected');
      expect(screen()!.answeredAt, isNotNull);

      await container.read(callActionsProvider).setMuted(muted: true);
      await untilScreen((s) => s?.muted == true, 'muted');
      expect(me.media.last.muted, isTrue);

      await container.read(callActionsProvider).hangUp();
      await untilScreen((s) => s?.stage == CallStage.ended, 'ended');
      expect(screen()!.statusText, 'Call ended');
      expect(screen()!.talkTime, isNotNull);

      // The screen holds the ended call for a moment, then lets go.
      await untilScreen((s) => s == null, 'screen gone');
    });

    test(
      'the timer follows the clock and freezes when the call ends',
      () async {
        await place()(bob.account, video: false);
        await bob.untilPhase(CallPhase.ringing);
        await bob.service.accept();
        await untilScreen((s) => s?.stage == CallStage.active);

        clock.advance(const Duration(seconds: 65));
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final live = container.read(callElapsedProvider).value;
        expect(live, isNotNull);
        expect(live! >= const Duration(seconds: 65), isTrue);
      },
    );

    test('a call nobody answers ends as No answer', () async {
      final quick = await net.add(
        'quick',
        config: const CallConfig(
          ringTimeout: Duration(milliseconds: 150),
          iceBatchDelay: Duration.zero,
          signalTimeout: Duration(seconds: 2),
        ),
      );
      final caller = ProviderContainer(
        overrides: callOverrides(port: quick.port, names: names),
      );
      addTearDown(caller.dispose);
      caller.listen(callScreenStateProvider, (_, _) {});
      await caller.read(startCallProvider)(bob.account, video: false);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (caller.read(callScreenStateProvider)?.stage != CallStage.ended) {
        if (DateTime.now().isAfter(deadline)) fail('never ended');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(caller.read(callScreenStateProvider)!.statusText, 'No answer');
    });

    test('a refused microphone places no call and says why', () async {
      permissions.result = CallPermissionResult.microphoneDenied;
      final outcome = await place()(bob.account, video: false);

      expect(outcome.status, PlaceCallStatus.microphoneDenied);
      expect(outcome.message, contains('microphone'));
      expect(me.current, isNull);
      expect(screen(), isNull);
    });

    test('a refused camera on a video call says so', () async {
      permissions.result = CallPermissionResult.cameraDenied;
      final outcome = await place()(bob.account, video: true);

      expect(outcome.status, PlaceCallStatus.cameraDenied);
      expect(outcome.message, contains('camera'));
    });

    test('a second call while one is live is refused as busy', () async {
      await place()(bob.account, video: false);
      final second = await place()(bob.account, video: false);

      expect(second.status, PlaceCallStatus.busy);
      expect(second.message, 'You are already in a call.');
    });

    test(
      'media that cannot start is a plain failure, not an exception',
      () async {
        me.media.failCreate = true;
        final outcome = await place()(bob.account, video: false);

        expect(outcome.status, PlaceCallStatus.unavailable);
        expect(outcome.message, contains('microphone or camera'));
      },
    );

    test(
      'a server with no relay says so rather than blaming the phone',
      () async {
        me.media.failCreate = true;
        hub.lastProblem = CallMediaProblem.noRelay;
        final outcome = await place()(bob.account, video: false);

        expect(outcome.status, PlaceCallStatus.noRelay);
        expect(outcome.message, contains('no call relay'));
      },
    );
  });

  group('an incoming call', () {
    test('rings with the caller named, and answering connects it', () async {
      await bob.service.startCall(me.account, video: true);
      await untilScreen((s) => s?.stage == CallStage.incoming, 'incoming');

      expect(screen()!.title, 'Bob Builder');
      expect(screen()!.video, isTrue);
      expect(screen()!.statusText, 'Incoming video call');

      await container.read(callActionsProvider).accept();
      await untilScreen((s) => s?.stage == CallStage.active, 'active');
      expect(permissions.asked, [true]);
      expect(me.media.last.config.video, isTrue);
    });

    test('a refused microphone keeps it ringing and says what to do', () async {
      permissions.result = CallPermissionResult.microphoneDenied;
      await bob.service.startCall(me.account, video: false);
      await untilScreen((s) => s?.stage == CallStage.incoming);

      await container.read(callActionsProvider).accept();

      expect(screen()!.stage, CallStage.incoming);
      expect(screen()!.notice, contains('needs the microphone'));
      expect(me.current!.phase, CallPhase.ringing);

      container.read(callActionsProvider).dismissNotice();
      expect(screen()!.notice, isNull);
    });

    test('declining ends it as declined, and Bob sees it declined', () async {
      await bob.service.startCall(me.account, video: false);
      await untilScreen((s) => s?.stage == CallStage.incoming);

      await container.read(callActionsProvider).decline();

      await untilScreen((s) => s?.stage == CallStage.ended, 'ended');
      expect(screen()!.statusText, 'Call declined');
      await bob.until(() => bob.current == null, reason: 'bob sees the end');
      final row = (await bob.db.callsDao.recent()).single;
      expect(row.state, 'declined');
    });

    test('when the caller gives up it reads as a missed call', () async {
      await bob.service.startCall(me.account, video: false);
      await untilScreen((s) => s?.stage == CallStage.incoming);

      await bob.service.hangUp();

      await untilScreen((s) => s?.stage == CallStage.ended, 'ended');
      expect(screen()!.statusText, 'Missed call');
    });

    test(
      'answered on another device ends the ring here, and says so',
      () async {
        final other = await net.add('me2', account: me.account);
        final otherContainer = ProviderContainer(
          overrides: callOverrides(
            port: other.port,
            permissions: FakeCallPermissions(),
            names: names,
          ),
        );
        addTearDown(otherContainer.dispose);
        otherContainer.listen(callScreenStateProvider, (_, _) {});

        await bob.service.startCall(me.account, video: false);
        await untilScreen((s) => s?.stage == CallStage.incoming);
        await other.until(() => other.current?.phase == CallPhase.ringing);

        await otherContainer.read(callActionsProvider).accept();

        await untilScreen((s) => s?.stage == CallStage.ended, 'ended here');
        expect(screen()!.statusText, 'Answered on another device');
        expect(screen()!.end, CallEnd.answeredElsewhere);
      },
    );
  });

  group('the phone around a call', () {
    test(
      'an incoming call rings over the lock, answering stops it and starts '
      'the service, the earpiece turns the screen off, and ending cleans up',
      () async {
        await bob.service.startCall(me.account, video: false);
        await untilScreen((s) => s?.stage == CallStage.incoming);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(ringer.log, ['ring Bob Builder video:false full:true']);
        // Ringing is not "somebody holds the phone": the app lock stays on
        // until the call is connecting or active.
        expect(AppLock.callInProgress.value, isFalse);
        expect(platform.log, contains('active:true keepOn:false'));

        await container.read(callActionsProvider).accept();
        await untilScreen((s) => s?.stage == CallStage.active);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(AppLock.callInProgress.value, isTrue);

        expect(ringer.log.last, 'stop');
        expect(platform.log, contains('service:start Bob Builder video:false'));
        // A voice call starts on the earpiece, so the screen goes off at the ear.
        expect(audio.selected, contains(CallAudioRoute.earpiece));
        expect(platform.log, contains('proximity:true'));

        await container.read(callActionsProvider).hangUp();
        await untilScreen((s) => s == null, 'gone');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          platform.log,
          containsAllInOrder(['service:stop', 'proximity:false']),
        );
        expect(platform.log.last, 'active:false keepOn:false');
        expect(AppLock.callInProgress.value, isFalse);
      },
    );

    test(
      'a video call starts on the speaker and keeps the screen on',
      () async {
        await bob.service.startCall(me.account, video: true);
        await untilScreen((s) => s?.stage == CallStage.incoming);
        await container.read(callActionsProvider).accept();
        await untilScreen((s) => s?.stage == CallStage.active);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(audio.selected, contains(CallAudioRoute.speaker));
        expect(platform.log, contains('active:true keepOn:true'));
        expect(platform.log, isNot(contains('proximity:true')));
      },
    );

    test('a headset that connects wins, and one pulled falls back', () async {
      await bob.service.startCall(me.account, video: false);
      await untilScreen((s) => s?.stage == CallStage.incoming);
      await container.read(callActionsProvider).accept();
      await untilScreen((s) => s?.stage == CallStage.active);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      audio.change({
        CallAudioRoute.earpiece,
        CallAudioRoute.speaker,
        CallAudioRoute.bluetooth,
      });
      await untilScreen((s) => s?.audio.route == CallAudioRoute.bluetooth);
      expect(screen()!.audio.available.length, 3);

      audio.change({CallAudioRoute.earpiece, CallAudioRoute.speaker});
      await untilScreen((s) => s?.audio.route == CallAudioRoute.earpiece);
    });

    test('the person can choose another output', () async {
      await bob.service.startCall(me.account, video: false);
      await untilScreen((s) => s?.stage == CallStage.incoming);
      await container.read(callActionsProvider).accept();
      await untilScreen((s) => s?.stage == CallStage.active);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await container
          .read(callActionsProvider)
          .selectRoute(CallAudioRoute.speaker);

      expect(screen()!.audio.route, CallAudioRoute.speaker);
      expect(audio.selected.last, CallAudioRoute.speaker);
    });
  });

  group('media and quality', () {
    test(
      'a dropped connection reads as Reconnecting and a weak one as poor',
      () async {
        await place()(bob.account, video: false);
        await bob.untilPhase(CallPhase.ringing);
        await bob.service.accept();
        await untilScreen((s) => s?.stage == CallStage.active);

        hub.publish(const CallMediaInfo(state: CallMediaState.disconnected));
        await untilScreen((s) => s?.quality == CallQuality.reconnecting);
        expect(screen()!.statusText, 'Reconnecting…');

        hub.publish(
          const CallMediaInfo(weak: true, state: CallMediaState.connected),
        );
        await untilScreen((s) => s?.quality == CallQuality.weak);

        hub.publish(const CallMediaInfo(state: CallMediaState.connected));
        await untilScreen((s) => s?.quality == CallQuality.good);
      },
    );
  });
}
