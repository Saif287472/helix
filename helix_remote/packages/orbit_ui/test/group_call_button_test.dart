import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The call buttons of a group chat: up to three others are rung at once, a
/// larger group chooses who in a sheet.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  HelixPersonItem person(String name) => HelixPersonItem(
    id: name.toLowerCase(),
    names: HelixPersonNames(nickname: name),
  );

  Future<void> show(
    WidgetTester tester,
    List<String> others,
    ChatActions actions,
  ) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(
          body: ChatScreen(
            model: ChatModel(
              conversationId: 'group:g1',
              title: 'Friday crew',
              avatar: const HelixAvatarModel(
                name: 'Friday crew',
                isGroup: true,
              ),
              isGroup: true,
              callCandidates: [for (final n in others) person(n)],
            ),
            actions: actions,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a small group is rung at once, without a sheet', (tester) async {
    List<String>? rung;
    await show(
      tester,
      ['Ada', 'Bilal'],
      ChatActions(
        onGroupCall: (invite, {required video}) {
          rung = invite;
          return null;
        },
      ),
    );
    await tester.tap(find.byTooltip('Voice call'));
    await tester.pumpAndSettle();
    expect(rung, ['ada', 'bilal']);
    expect(find.text('Choose who to call'), findsNothing);
  });

  testWidgets('a large group chooses up to three, then rings them', (
    tester,
  ) async {
    List<String>? rung;
    bool? wasVideo;
    await show(
      tester,
      ['Ada', 'Bilal', 'Chen', 'Dara', 'Eli'],
      ChatActions(
        onGroupCall: (invite, {required video}) {
          rung = invite;
          wasVideo = video;
          return null;
        },
      ),
    );
    await tester.tap(find.byTooltip('Video call'));
    await tester.pumpAndSettle();
    expect(find.text('Choose who to call'), findsOneWidget);
    for (final n in ['Ada', 'Chen', 'Eli', 'Bilal']) {
      await tester.tap(find.text(n));
      await tester.pump();
    }
    // A fourth is not taken: a room holds four, you being one.
    expect(find.text('Call 3'), findsOneWidget);
    await tester.tap(find.text('Call 3'));
    await tester.pumpAndSettle();
    expect(rung, ['ada', 'chen', 'eli']);
    expect(wasVideo, isTrue);
  });

  testWidgets('dismissing the sheet rings nobody', (tester) async {
    var rang = false;
    await show(
      tester,
      ['Ada', 'Bilal', 'Chen', 'Dara'],
      ChatActions(
        onGroupCall: (invite, {required video}) {
          rang = true;
          return null;
        },
      ),
    );
    await tester.tap(find.byTooltip('Voice call'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(rang, isFalse);
  });
}
