import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/calls/place_call.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/home/application/home_tab.dart';
import 'package:helix_remote/shared/navigation/conversation_seams.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:helix_remote/shared/widgets/people_search_panel.dart';

import 'support/people_fakes.dart';

/// The rules the people feature carries (AGENTS.md product rules and the
/// privacy invariants), as tests that fail when somebody breaks them.
void main() {
  Iterable<File> sources(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  String code(File file) => file
      .readAsStringSync()
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i == -1 ? line : line.substring(0, i);
      })
      .join('\n');

  final peopleFiles = [
    ...sources('lib/features/people'),
    File('lib/shared/widgets/people_search_panel.dart'),
    File('lib/shared/widgets/phone_book_sync_host.dart'),
    File('lib/shared/navigation/conversation_seams.dart'),
    File('lib/shared/navigation/people_paths.dart'),
    File('lib/core/people/people_names.dart'),
    File('lib/core/platform/phone_numbers.dart'),
    File('lib/core/platform/contacts_access.dart'),
    File('lib/core/platform/device_phone_book.dart'),
  ];

  group('no contact requests, no Contacts tab', () {
    test('home is exactly Chats, Calls and Settings', () {
      expect(HomeTab.values.map((t) => t.label), [
        'Chats',
        'Calls',
        'Settings',
      ]);
    });

    test('nothing in the people feature asks, accepts or adds a contact', () {
      final offenders = <String>[];
      for (final file in peopleFiles) {
        final source = code(file);
        for (final needle in const [
          'contact request',
          'Contact request',
          'Add contact',
          'Accept request',
          'friend request',
          'pending request',
        ]) {
          if (source.contains(needle)) offenders.add('${file.path}: $needle');
        }
      }
      expect(offenders, isEmpty);
    });

    testWidgets('a person who has never been messaged can be opened at once', (
      tester,
    ) async {
      final gateway = FakePeopleGateway()
        ..put(personRow('new', phonebook: 'New Person'));
      final seams = FakeSeams();
      await pumpPeople(
        tester,
        const PeopleSearchPanel(query: ''),
        gateway: gateway,
        seams: seams,
      );
      await tester.tap(find.text('New Person'));
      await tester.pump();
      await tester.pump();
      expect(seams.opened, ['direct:new'], reason: 'no request, no approval');
    });
  });

  group('privacy of discovery', () {
    test('the app never calls the discovery route itself', () {
      // Discovery goes through `PeopleService.syncPhoneBook` and
      // `findByNumber`, which hash on the device. Calling the API directly
      // from the app would be one step from sending a raw number.
      final offenders = <String>[];
      for (final file in sources('lib')) {
        final source = code(file);
        if (RegExp(r'\.people\.discover\(|DiscoverRequest').hasMatch(source)) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('the contacts plugin is touched in exactly one file', () {
      // Platform code stays behind the adapter in core/, so a fake can stand
      // in for it everywhere else.
      final offenders = [
        for (final file in sources('lib'))
          if (file.readAsStringSync().contains('package:flutter_contacts') &&
              !file.path
                  .replaceAll(r'\', '/')
                  .endsWith('core/platform/contacts_access.dart'))
            file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('the camera plugin is touched in exactly one file', () {
      // Every scan (a person's safety number, a device link) goes through the
      // one adapter, so a fake can stand in for the camera everywhere else.
      final offenders = [
        for (final file in sources('lib'))
          if (file.readAsStringSync().contains('package:mobile_scanner') &&
              !file.path
                  .replaceAll(r'\', '/')
                  .endsWith('shared/widgets/qr_scanner_view.dart'))
            file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('phone numbers and names are never interpolated into an error or '
        'a snackbar by the people code', () {
      // A snackbar can linger in a screenshot and an error reaches logs;
      // both may carry a name only a person's own screen should show.
      final offenders = <String>[];
      for (final file in peopleFiles) {
        final source = code(file);
        for (final match in RegExp(
          r'(showHelixSnackBar|SnackBar|_say)\(',
        ).allMatches(source)) {
          // The call's whole argument list, to its closing parenthesis.
          var depth = 1;
          var i = match.end;
          while (i < source.length && depth > 0) {
            if (source[i] == '(') depth++;
            if (source[i] == ')') depth--;
            i++;
          }
          final arguments = source.substring(match.end, i);
          // `context` is a variable, not text; only a string interpolation
          // can carry a name or a number in.
          if (arguments.contains(r'$')) {
            offenders.add(
              '${file.path}: ${match.group(1)}(${arguments.trim()}',
            );
          }
        }
        if (RegExp(r'throw\s+\w+\([^;]*?\$').hasMatch(source)) {
          offenders.add('${file.path}: throws with interpolation');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('seams', () {
    testWidgets('a chat is opened by route, for the owner of that route to '
        'serve', (tester) async {
      final visited = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) {
              visited.add(state.pathParameters['id']!);
              return const SizedBox();
            },
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [appRouterProvider.overrideWithValue(router)],
      );
      addTearDown(() {
        container.dispose();
        router.dispose();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      final seams = container.read(conversationSeamsProvider);
      expect(seams, isA<RouterConversationSeams>());
      await seams.openChat('direct:abc');
      await tester.pumpAndSettle();
      expect(visited, contains('direct:abc'));
      await seams.openChat('group:g1');
      await tester.pumpAndSettle();
      expect(visited, containsAll(['direct:abc', 'group:g1']));
    });

    test(
      'a call goes through the calls seam and a refusal is its sentence',
      () async {
        final placed = <String>[];
        var refuse = false;
        final container = ProviderContainer(
          overrides: [
            placeCallProvider.overrideWithValue((peer, {required video}) async {
              placed.add('${video ? 'video' : 'voice'}:$peer');
              return refuse
                  ? const PlaceCallOutcome(PlaceCallStatus.busy, 'Busy now.')
                  : const PlaceCallOutcome(PlaceCallStatus.started);
            }),
          ],
        );
        addTearDown(container.dispose);
        final seams = container.read(conversationSeamsProvider);
        expect(await seams.startCall('a', video: false), isNull);
        refuse = true;
        expect(await seams.startCall('b', video: true), 'Busy now.');
        expect(placed, ['voice:a', 'video:b']);
      },
    );

    testWidgets('shared media opens the shared page of the chat', (
      tester,
    ) async {
      final visited = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(
            path: '/chat/:id/shared',
            builder: (_, state) {
              visited.add(state.pathParameters['id']!);
              return const SizedBox();
            },
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [appRouterProvider.overrideWithValue(router)],
      );
      addTearDown(() {
        container.dispose();
        router.dispose();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      final seams = container.read(conversationSeamsProvider);
      expect(await seams.openSharedMedia('direct:abc'), isTrue);
      await tester.pumpAndSettle();
      expect(visited, ['direct:abc']);
    });

    test('the people paths are the ones the router registers', () {
      expect(PeoplePaths.home, '/home/people');
      expect(PeoplePaths.search, '/home/people/search');
      expect(
        PeoplePaths.searchFor(calls: true),
        '/home/people/search?mode=calls',
      );
      expect(PeoplePaths.person('a@b.c'), '/home/people/a%40b.c');
      expect(PeoplePaths.safetyNumber('x'), '/home/people/x/safety');
      expect(PeoplePaths.scan('x'), '/home/people/x/scan');
      // The deep link for adding a contact already lands on the people search.
      expect(AppRoutes.home, '/home');
    });
  });
}
