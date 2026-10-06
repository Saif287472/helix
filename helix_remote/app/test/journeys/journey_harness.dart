import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/main.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/a3b_fakes.dart' hide settle, stubRoute;
import '../support/call_support.dart';
import '../support/chat_harness.dart';
import '../support/group_support.dart';
import '../support/people_fakes.dart' hide pumpPeople, testNow;

/// A group chat with the roster of [testGroup], in the chat database.
final class JourneyGroupsPort extends FakeGroupsPort {
  JourneyGroupsPort(this._chat) : super(group: testGroup());

  final TestChatGateway _chat;

  @override
  Future<CreatedGroupInfo> create({
    required String name,
    required Iterable<String> members,
    String? description,
    Uint8List? picture,
  }) async {
    final made = await super.create(
      name: name,
      members: members,
      description: description,
      picture: picture,
    );
    // The engine creates the group's conversation with the group.
    await _chat.db.conversationsDao.ensureGroup(
      made.conversationId,
      title: name,
      now: testNow,
    );
    set(testGroup(title: name));
    return made;
  }
}

/// The whole app, router included, over fakes: the chat database is a real
/// in-memory engine database (reads are the engine's queries), the people,
/// calls, groups, devices and settings gateways are the feature fakes. Which
/// is what lets a test walk across features the way a person does.
ProviderContainer? _active;

final class Journey {
  Journey._({
    required this.chat,
    required this.people,
    required this.calls,
    required this.groups,
    required this.devices,
    required this.container,
    required this.auth,
  });

  final TestChatGateway chat;
  final FakePeopleGateway people;
  final FakeCallsPort calls;
  final JourneyGroupsPort groups;
  final FakeDevicesGateway devices;
  final ProviderContainer container;
  final StreamController<AppAuthState> auth;

  GoRouter get router => container.read(appRouterProvider);

  /// Starts the app on sign-in; call [signIn] to let the engine report a
  /// session.
  static Future<Journey> start(
    WidgetTester tester, {
    List<PersonRow> known = const [],

    /// Rows written to the chat database before the app is drawn (the
    /// database cannot be written from a test body once streams watch it).
    Future<void> Function(TestChatGateway chat)? seed,

    /// Pump the whole `HelixRemoteApp` (lifecycle, call host, phone-book sync,
    /// app lock and link listener around the router), not only the router.
    bool wholeApp = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);

    final chat = (await tester.runAsync(TestChatGateway.create))!;
    if (seed != null) await tester.runAsync(() => seed(chat));
    final people = FakePeopleGateway(selfId: 'me');
    for (final row in known) {
      people.put(row);
    }
    // What the engine's `openDirect` does: the conversation, and the person.
    people.onOpenChat = (account) async {
      await chat.chatWith(account, name: people.people[account]?.phonebookName);
    };
    final calls = FakeCallsPort();
    calls.onStart = (peer, video) {
      // The engine writes the log row when the call is placed.
      calls.setLog([logRow('call-1', peer: peer, video: video, at: testNow)]);
      return CallSnapshot(
        callId: 'call-1',
        peer: peer,
        direction: CallDirection.outgoing,
        video: video,
        phase: CallPhase.calling,
        startedAt: testNow.toUtc(),
      );
    };
    final groups = JourneyGroupsPort(chat);
    final devices = FakeDevicesGateway();
    final auth = StreamController<AppAuthState>.broadcast();

    final container = newContainer([
      ...a3bOverrides(
        now: testNow,
        devices: devices,
        settingsGateway: FakeSettingsGateway(),
        backup: FakeBackupGateway(),
        profile: FakeProfileGateway(),
      ),
      authStateProvider.overrideWith((ref) async* {
        yield AppAuthState.signedOut;
        yield* auth.stream;
      }),
      chatGatewayProvider.overrideWith((ref) => chat),
      peopleGatewayProvider.overrideWith((ref) async => people),
      peopleRowsProvider.overrideWith((ref) => people.rows()),
      contactsAccessProvider.overrideWithValue(
        FakeContactsAccess(state: ContactsPermission.granted),
      ),
      qrScannerBuilderProvider.overrideWithValue(fakeScanner),
      ...callOverrides(port: calls, withNames: false),
      // The groups feature opens a group's chat on the conversation route.
      ...groupOverrides(
        port: groups,
        withNames: false,
        chatLocation: chatLocation,
      ),
      // The group chat has its roster in the database in the real app.
      groupMembersProvider.overrideWith(
        (ref, id) => Stream.value([
          GroupMemberRow(
            groupId: id.substring(6),
            accountId: 'me',
            qualifiedId: 'me',
            role: 'owner',
            isSelf: true,
            devicesJson: '[]',
          ),
        ]),
      ),
    ]);
    _active = container;
    addTearDown(() => unawaited(auth.close()));

    if (wholeApp) {
      // The remembered server is read from the keystore at start.
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const HelixRemoteApp(),
        ),
      );
      await settle(tester);
      return Journey._(
        chat: chat,
        people: people,
        calls: calls,
        groups: groups,
        devices: devices,
        container: container,
        auth: auth,
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: HelixThemes.light(),
            routerConfig: ref.watch(appRouterProvider),
          ),
        ),
      ),
    );
    await settle(tester);
    return Journey._(
      chat: chat,
      people: people,
      calls: calls,
      groups: groups,
      devices: devices,
      container: container,
      auth: auth,
    );
  }

  /// The engine reports a session: the router leaves sign-in by itself.
  Future<void> signIn(WidgetTester tester) async {
    auth.add(AppAuthState.ready);
    await settle(tester, rounds: 10);
  }
}

/// Taps [finder] and lets the real asynchronous work it started finish.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settle(tester, rounds: 10);
}

/// Lets the database and streams run, then draws.
Future<void> settleJourney(WidgetTester tester) => settle(tester, rounds: 10);

/// A people row for a person on the phone's address book.
PersonRow knownPerson(String account, String name, {String? number}) =>
    personRow(account, phonebook: name, phone: number);

/// A journey test: the app is taken down at the end, so no timer (a chat's
/// presence poll, say) is left pending when the test body returns.
void journeyTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(name, (tester) async {
  await body(tester);
  await tester.pumpWidget(const SizedBox());
  // Disposing the container is what cancels the providers' own timers.
  _active?.dispose();
  _active = null;
  await tester.pump(const Duration(seconds: 2));
});
