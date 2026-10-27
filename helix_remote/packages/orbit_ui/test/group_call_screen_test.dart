import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The group call screen: ringing, and a room of up to four tiles.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 866),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: OrbitTheme.of(orbit),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  GroupCallTile tile(
    String name, {
    GroupTileState state = GroupTileState.connected,
  }) => GroupCallTile(
    id: name.toLowerCase(),
    name: name,
    avatar: HelixAvatarModel(name: name),
    state: state,
  );

  GroupCallModel model({
    CallStage stage = CallStage.active,
    List<GroupCallTile>? tiles,
    bool video = true,
    bool muted = false,
    bool cameraOn = true,
    String? notice,
  }) => GroupCallModel(
    roomId: 'r',
    title: 'Friday crew',
    stage: stage,
    statusText: stage == CallStage.incoming ? 'Incoming group call' : '',
    starterName: 'Nadia',
    tiles: tiles ?? [tile('Nadia'), tile('Bilal')],
    video: video,
    elapsedLabel: stage == CallStage.active ? '01:12' : null,
    muted: muted,
    cameraOn: cameraOn,
    notice: notice,
  );

  testWidgets('a ringing room says which group and who, and Join answers', (
    tester,
  ) async {
    var joined = 0;
    var declined = 0;
    await show(
      tester,
      GroupCallScreen(
        model: model(stage: CallStage.incoming),
        actions: GroupCallActions(
          answer: () => joined++,
          decline: () => declined++,
        ),
      ),
    );
    expect(find.text('Friday crew'), findsOneWidget);
    expect(find.text('Nadia is calling the group'), findsOneWidget);
    expect(find.text('Nadia, Bilal'), findsOneWidget);
    await tester.tap(find.byTooltip('Join video call'));
    await tester.tap(find.byTooltip('Decline group call'));
    expect((joined, declined), (1, 1));
  });

  testWidgets('a live room shows everyone, and you', (tester) async {
    await show(
      tester,
      GroupCallScreen(
        model: model(
          tiles: [
            tile('Nadia'),
            tile('Bilal', state: GroupTileState.connecting),
            tile('Cara', state: GroupTileState.ringing),
          ],
        ),
      ),
    );
    expect(find.text('01:12'), findsOneWidget);
    expect(find.text('Nadia'), findsOneWidget);
    expect(find.text('Bilal · Connecting…'), findsOneWidget);
    expect(find.text('Cara · Ringing…'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('someone who left or dropped is marked, and you can be muted', (
    tester,
  ) async {
    await show(
      tester,
      GroupCallScreen(
        model: model(
          muted: true,
          tiles: [
            tile('Nadia', state: GroupTileState.left),
            tile('Bilal', state: GroupTileState.failed),
          ],
        ),
      ),
    );
    expect(find.text('Nadia · Left'), findsOneWidget);
    expect(find.text('Bilal · Could not connect'), findsOneWidget);
    expect(find.text('You · Muted'), findsOneWidget);
  });

  testWidgets('the app draws each person\'s picture where they are', (
    tester,
  ) async {
    final asked = <String>[];
    await show(
      tester,
      GroupCallScreen(
        model: model(),
        tileVideo: (context, id, placeholder) {
          asked.add(id);
          return Text('video:$id');
        },
      ),
    );
    expect(asked.toSet(), {'nadia', 'bilal'});
    expect(find.text('video:nadia'), findsOneWidget);
  });

  testWidgets('the tray mutes, switches the camera and ends the call', (
    tester,
  ) async {
    final muted = <bool>[];
    final camera = <bool>[];
    var ended = 0;
    await show(
      tester,
      GroupCallScreen(
        model: model(),
        actions: GroupCallActions(
          setMuted: muted.add,
          setCamera: camera.add,
          hangUp: () => ended++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Mute microphone'));
    await tester.tap(find.byTooltip('Turn camera off'));
    await tester.tap(find.byTooltip('End call'));
    expect(muted, [true]);
    expect(camera, [false]);
    expect(ended, 1);
  });

  testWidgets('a voice room has no camera controls', (tester) async {
    await show(tester, GroupCallScreen(model: model(video: false)));
    expect(find.byTooltip('Turn camera off'), findsNothing);
    expect(find.byTooltip('Flip camera'), findsNothing);
    expect(find.byTooltip('Mute microphone'), findsOneWidget);
  });

  testWidgets('an ended room disables the controls, and a notice dismisses', (
    tester,
  ) async {
    var dismissed = 0;
    await show(
      tester,
      GroupCallScreen(
        model: model(stage: CallStage.ended, notice: 'Allow the microphone.'),
        actions: GroupCallActions(dismissNotice: () => dismissed++),
      ),
    );
    expect(find.text('Allow the microphone.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, 1);
    var ended = 0;
    await show(tester, const SizedBox());
    await show(
      tester,
      GroupCallScreen(
        model: model(stage: CallStage.ended),
        actions: GroupCallActions(hangUp: () => ended++),
      ),
    );
    await tester.tap(find.byTooltip('End call'), warnIfMissed: false);
    expect(ended, 0);
  });

  testWidgets('four people fit', (tester) async {
    await show(
      tester,
      GroupCallScreen(
        model: model(tiles: [tile('Nadia'), tile('Bilal'), tile('Cara')]),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final n in ['Nadia', 'Bilal', 'Cara', 'You']) {
      expect(find.text(n), findsOneWidget);
    }
  });
}
