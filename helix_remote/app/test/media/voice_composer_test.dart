import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';

import '../support/chat_harness.dart';
import '../support/media_fakes.dart';

void main() {
  late Directory dir;
  late Directory voiceDir;
  late FakeVoiceRecorder recorder;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('helix_voice_test');
    voiceDir = Directory('${dir.path}/helix_voice')..createSync();
    recorder = FakeVoiceRecorder(voiceDir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> open(WidgetTester tester, TestChatGateway gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat),
        overrides: [
          voiceRecorderProvider.overrideWithValue(recorder),
          mediaTempProvider.overrideWithValue(tempIn(dir)),
        ],
      ),
    );
    await settle(tester, rounds: 8);
    return chat;
  }

  Finder mic() => find.bySemanticsLabel('Record voice message');

  Future<TestGesture> hold(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getCenter(mic()));
    await tester.pump(const Duration(milliseconds: 600));
    return gesture;
  }

  /// Real file work (deleting the recording) runs outside the fake clock.
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
  }

  int sends(TestChatGateway g) =>
      g.log.where((l) => l.startsWith('sendMedia')).length;

  chatTest('holding and letting go sends the note and deletes the file', (
    tester,
    gateway,
  ) async {
    await open(tester, gateway);
    final gesture = await hold(tester);
    expect(recorder.events, ['start']);
    expect(find.text('Slide to cancel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:02'), findsOneWidget);
    final file = voiceDir.listSync().single;
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(recorder.events, ['start', 'stop']);
    expect(sends(gateway), 1);
    expect(find.text('Slide to cancel'), findsNothing);
    await flush(tester);
    expect(file.existsSync(), isFalse, reason: 'the recording is deleted');
  });

  chatTest('sliding to cancel throws the recording away', (
    tester,
    gateway,
  ) async {
    await open(tester, gateway);
    final gesture = await hold(tester);
    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(recorder.events, ['start', 'cancel']);
    expect(sends(gateway), 0);
    expect(voiceDir.listSync(), isEmpty);
  });

  chatTest('a note that is too short is not sent, and says why', (
    tester,
    gateway,
  ) async {
    recorder.durationMs = 300;
    await open(tester, gateway);
    final gesture = await hold(tester);
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(sends(gateway), 0);
    expect(
      find.textContaining('Hold the microphone to record'),
      findsOneWidget,
    );
    await flush(tester);
    expect(voiceDir.listSync(), isEmpty);
  });

  chatTest('sliding up locks it; send and delete work without holding', (
    tester,
    gateway,
  ) async {
    await open(tester, gateway);
    var gesture = await hold(tester);
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.byTooltip('Send recording'), findsOneWidget);
    expect(recorder.events, ['start'], reason: 'still recording');
    await tester.tap(find.byTooltip('Send recording'));
    await tester.pump();
    await tester.pump();
    expect(sends(gateway), 1);

    gesture = await hold(tester);
    await gesture.moveBy(const Offset(0, -90));
    await gesture.up();
    await tester.pump();
    await tester.tap(find.byTooltip('Delete recording'));
    await tester.pump();
    expect(recorder.events.last, 'cancel');
    expect(sends(gateway), 1);
  });

  chatTest('a refused microphone permission is explained, nothing records', (
    tester,
    gateway,
  ) async {
    recorder.startError = const VoiceRecorderPermissionDenied();
    await open(tester, gateway);
    final gesture = await hold(tester);
    await gesture.up();
    await tester.pump();
    expect(find.textContaining('Allow microphone access'), findsOneWidget);
    expect(find.text('Slide to cancel'), findsNothing);
    expect(sends(gateway), 0);
  });

  chatTest('a finger lifted while the microphone was opening drops it', (
    tester,
    gateway,
  ) async {
    // The first use: the permission prompt takes the touch away.
    recorder.startDelay = const Duration(milliseconds: 400);
    await open(tester, gateway);
    final gesture = await tester.startGesture(tester.getCenter(mic()));
    await tester.pump(const Duration(milliseconds: 600)); // long press: start
    await gesture.up(); // lifted while start() is still waiting
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(recorder.events, containsAllInOrder(['start', 'cancel']));
    expect(find.text('Slide to cancel'), findsNothing);
    expect(sends(gateway), 0);
    expect(voiceDir.listSync(), isEmpty);
  });

  chatTest('a call pauses the clock; going to the background pauses a locked '
      'note and drops a held one', (tester, gateway) async {
    await open(tester, gateway);
    var gesture = await hold(tester);
    await gesture.moveBy(const Offset(0, -90));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);

    recorder.systemPhase(VoicePhase.paused); // an incoming call
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('0:01'), findsOneWidget, reason: 'the clock waits');
    recorder.systemPhase(VoicePhase.recording);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:02'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(recorder.events, contains('pause'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(recorder.events, contains('resume'));
    await tester.tap(find.byTooltip('Delete recording'));
    await tester.pump();

    // A held (not locked) recording cannot survive the background.
    gesture = await hold(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    // Frames stop while paused; the person comes back to see it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Slide to cancel'), findsNothing);
    expect(
      find.textContaining('stopped because you left the app'),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pump();
    expect(sends(gateway), 0);
  });

  chatTest('a locked note stops and sends itself at the length limit', (
    tester,
    gateway,
  ) async {
    await open(tester, gateway);
    final gesture = await hold(tester);
    await gesture.moveBy(const Offset(0, -90));
    await gesture.up();
    await tester.pump(VoiceRecorder.maxDuration + const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(sends(gateway), 1);
    expect(find.textContaining('longest a voice message'), findsOneWidget);
    expect(find.text('Slide to cancel'), findsNothing);
  });

  chatTest('the microphone says so when recording is unavailable', (
    tester,
    gateway,
  ) async {
    recorder.available = false;
    await open(tester, gateway);
    await tester.longPress(mic());
    await settle(tester);
    expect(
      find.text('Voice messages are not available on this device.'),
      findsOneWidget,
    );
  });
}
