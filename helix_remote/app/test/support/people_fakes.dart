import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote/features/people/people_routes.dart';
import 'package:helix_remote/shared/navigation/conversation_seams.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show PhoneBookSyncResult;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ReportCategory;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// 2026-10-03 12:00 UTC: the clock every people test runs on.
final DateTime testNow = DateTime.utc(2026, 10, 3, 12);

/// A people row with only the fields a test cares about.
PersonRow personRow(
  String id, {
  String? phonebook,
  String? nickname,
  String? phone,
  String? helix,
  String? profile,
  bool blocked = false,
  bool verified = false,
  Uint8List? identityKey,
  DateTime? keyChangedAt,
  Uint8List? avatar,
}) => PersonRow(
  accountId: id,
  helixName: helix,
  phoneNumber: phone,
  phonebookName: phonebook,
  nickname: nickname,
  profileName: profile,
  avatarBlob: avatar,
  identityKey: identityKey,
  identityVerified: verified,
  identityChangedAt: keyChangedAt,
  blocked: blocked,
  updatedAt: testNow,
);

Uint8List key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i) & 0xff));

/// The address book, in memory. Records what the app wrote to it.
final class FakeContactsAccess implements ContactsAccess {
  FakeContactsAccess({
    this.state = ContactsPermission.notAsked,
    this.supported = true,
    List<AddressBookContact> contacts = const [],
    this.grantOnRequest = true,
  }) : contacts = [...contacts];

  ContactsPermission state;
  bool supported;

  /// What the system dialog answers when asked.
  bool grantOnRequest;
  final List<AddressBookContact> contacts;
  final List<String> events = [];
  final _changes = StreamController<void>.broadcast();

  /// A write the phone refuses (a read-only account).
  bool refuseWrites = false;

  /// What [saveName] was last asked: the contact (null = create), the number
  /// and the name.
  ({String? id, String number, String name})? lastWrite;

  void touch() => _changes.add(null);

  @override
  bool get isSupported => supported;

  @override
  Future<ContactsPermission> permission() async =>
      supported ? state : ContactsPermission.unsupported;

  @override
  Future<ContactsPermission> request() async {
    events.add('request');
    if (!supported) return ContactsPermission.unsupported;
    state = grantOnRequest
        ? ContactsPermission.granted
        : ContactsPermission.denied;
    return state;
  }

  @override
  Future<void> openSettings() async => events.add('openSettings');

  @override
  Future<List<AddressBookContact>> readAll() async =>
      state == ContactsPermission.granted ? [...contacts] : const [];

  @override
  Future<bool> saveName({
    String? contactId,
    required String number,
    required String name,
  }) async {
    events.add('saveName');
    if (state != ContactsPermission.granted || refuseWrites) return false;
    lastWrite = (id: contactId, number: number, name: name);
    if (contactId == null) {
      contacts.add(
        AddressBookContact(
          id: 'new-${contacts.length}',
          name: name,
          numbers: [number],
        ),
      );
    } else {
      final i = contacts.indexWhere((c) => c.id == contactId);
      contacts[i] = AddressBookContact(
        id: contactId,
        name: name,
        numbers: contacts[i].numbers,
      );
    }
    return true;
  }

  @override
  Stream<void> get changes => _changes.stream;
}

/// Records the hand-overs to other features.
final class FakeSeams implements ConversationSeams {
  final List<String> opened = [];
  final List<String> calls = [];
  final List<String> media = [];

  /// Whether the calls and shared-media screens "exist".
  bool callsAvailable = true;
  bool mediaAvailable = true;

  @override
  Future<void> openChat(String conversationId) async =>
      opened.add(conversationId);

  @override
  Future<bool> openSharedMedia(String conversationId) async {
    media.add(conversationId);
    return mediaAvailable;
  }

  @override
  Future<bool> startCall(String accountId, {required bool video}) async {
    calls.add('${video ? 'video' : 'voice'}:$accountId');
    return callsAvailable;
  }
}

/// The people gateway, in memory. Behaves like the engine where it matters
/// (a rename writes the phone-book name when the phone takes it) and records
/// every call.
final class FakePeopleGateway implements PeopleGateway {
  FakePeopleGateway({
    this.selfId = 'self-account',
    this.ownNumberValue = '+8801711000000',
  });

  final String selfId;
  final String? ownNumberValue;

  final Map<String, PersonRow> people = {};
  final Map<String, String?> abouts = {};
  final Map<String, ConversationRow> chats = {};
  final Map<String, SafetyNumberData> safety = {};
  final List<GroupSummary> groups = [];

  /// group id -> members, for the groups in common.
  final Map<String, Set<String>> members = {};

  /// Lookups answer from these (absent = not on Helix).
  final Map<String, PersonRow> byNumber = {};
  final Map<String, PersonRow> byHelixName = {};

  /// Thrown by lookups when set.
  Object? lookupError;

  /// Holds lookups until completed, to observe the "searching" state.
  Completer<void>? lookupGate;

  /// The phone the engine writes renames to (the real adapter over a fake
  /// address book), as `PeopleService.setNickname` does.
  FakeContactsAccess? phone;

  /// Used when [phone] is not set: whether the phone takes a rename.
  bool phoneAccepts = true;

  PhoneBookSyncResult syncResult = const PhoneBookSyncResult(
    checked: 3,
    found: 2,
    remainingToday: 4997,
  );
  Object? syncError;
  PhoneBookSyncLog? syncLog;
  final List<String> calls = [];
  final _changes = StreamController<void>.broadcast(sync: true);

  void put(PersonRow row) {
    people[row.accountId] = row;
    _changes.add(null);
  }

  void changed() => _changes.add(null);

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  /// What `peopleRowsProvider` is overridden with.
  Stream<List<PersonRow>> rows() => _live(() => people.values.toList());

  @override
  String? get selfAccountId => selfId;

  @override
  Future<String?> ownNumber() async => ownNumberValue;

  @override
  Stream<PersonRow?> watchPerson(String accountId) =>
      _live(() => people[accountId]);

  @override
  Stream<String?> watchAbout(String accountId) =>
      _live(() => abouts[accountId]);

  @override
  Stream<ConversationRow?> watchDirectChat(String accountId) =>
      _live(() => chats[directConversationId(accountId)]);

  @override
  Stream<List<GroupSummary>> watchGroups() => _live(() => [...groups]);

  @override
  Stream<List<GroupSummary>> watchCommonGroups(String accountId) => _live(
    () => [
      for (final group in groups)
        if (members[group.id]?.contains(accountId) ?? false) group,
    ],
  );

  @override
  Future<SafetyNumberData?> safetyNumber(String accountId) async =>
      safety[accountId];

  @override
  Future<void> refreshProfile(String accountId) async =>
      calls.add('refreshProfile:$accountId');

  @override
  Future<void> setNickname(String accountId, String? nickname) async {
    calls.add('setNickname:$accountId:$nickname');
    final row = people[accountId] ?? personRow(accountId);
    final value = nickname?.trim().isEmpty ?? true ? null : nickname!.trim();
    var next = row.copyWith(nickname: Value(value));
    if (value != null && row.phoneNumber != null) {
      final book = phone;
      final took = book == null
          ? phoneAccepts
          : await DevicePhoneBook(
              access: book,
              country: PhoneCountry()..callingCode = '880',
            ).saveName(row.phoneNumber!, value);
      // The engine stores the name the phone took, which outranks the
      // nickname in the naming order.
      if (took) next = next.copyWith(phonebookName: Value(value));
    }
    put(next);
  }

  @override
  Future<void> setVerified(String accountId, {required bool verified}) async {
    calls.add('setVerified:$accountId:$verified');
    put(people[accountId]!.copyWith(identityVerified: verified));
  }

  @override
  Future<void> block(String accountId) async {
    calls.add('block:$accountId');
    put(people[accountId]!.copyWith(blocked: true));
  }

  @override
  Future<void> unblock(String accountId) async {
    calls.add('unblock:$accountId');
    put(people[accountId]!.copyWith(blocked: false));
  }

  @override
  Future<void> report(
    String accountId,
    ReportCategory category, {
    String? note,
  }) async => calls.add('report:$accountId:${category.name}:$note');

  @override
  Future<void> setMutedUntil(String accountId, DateTime? until) async {
    calls.add('mute:$accountId:${until?.toIso8601String()}');
    final id = directConversationId(accountId);
    chats[id] = _chat(id).copyWith(mutedUntil: Value(until));
    _changes.add(null);
  }

  @override
  Future<void> setDisappearing(String accountId, int? seconds) async {
    calls.add('disappearing:$accountId:$seconds');
    final id = directConversationId(accountId);
    chats[id] = _chat(id).copyWith(disappearingSeconds: Value(seconds));
    _changes.add(null);
  }

  ConversationRow _chat(String id) =>
      chats[id] ??
      ConversationRow(
        id: id,
        kind: ConversationKind.direct,
        archived: false,
        unreadCount: 0,
        mentionCount: 0,
        createdAt: testNow,
      );

  @override
  Future<String> openChat(String accountId) async {
    calls.add('openChat:$accountId');
    return directConversationId(accountId);
  }

  Future<T> _lookup<T>(T Function() answer) async {
    await lookupGate?.future;
    if (lookupError != null) throw lookupError!;
    return answer();
  }

  @override
  Future<PersonRow?> findByNumber(String e164) {
    calls.add('findByNumber:$e164');
    return _lookup(() {
      final row = byNumber[e164];
      if (row != null) put(row);
      return row;
    });
  }

  @override
  Future<PersonRow?> findByHelixName(String name) {
    calls.add('findByHelixName:$name');
    return _lookup(() {
      final row = byHelixName[name];
      if (row != null) put(row);
      return row;
    });
  }

  @override
  Future<PhoneBookSyncResult> syncPhoneBook() async {
    calls.add('syncPhoneBook');
    if (syncError != null) throw syncError!;
    return syncResult;
  }

  @override
  Future<PhoneBookSyncLog?> readSyncLog() async => syncLog;

  @override
  Future<void> writeSyncLog(PhoneBookSyncLog log) async => syncLog = log;
}

/// A scanner that is a button: pressing it "reads" [code].
Widget fakeScanner(BuildContext context, ValueChanged<String> onText) => Align(
  // Not in the middle: the scan frame paints there and takes the taps.
  alignment: Alignment.topCenter,
  child: ElevatedButton(
    onPressed: () => onText(scannedCode),
    child: const Text('Pretend to scan'),
  ),
);

/// What [fakeScanner] reads.
String scannedCode = '';

/// Pumps [child] at `/` of a router that also has the people routes, under
/// the Helix light theme, with the fakes wired in.
Future<ProviderContainer> pumpPeople(
  WidgetTester tester,
  Widget child, {
  required FakePeopleGateway gateway,
  FakeContactsAccess? contacts,
  FakeSeams? seams,
  double textScale = 1,
  double width = 400,
  double height = 800,
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: child),
      ),
      ...peopleRoutes,
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      peopleGatewayProvider.overrideWith((ref) async => gateway),
      peopleRowsProvider.overrideWith((ref) => gateway.rows()),
      contactsAccessProvider.overrideWithValue(
        contacts ?? FakeContactsAccess(state: ContactsPermission.granted),
      ),
      conversationSeamsProvider.overrideWithValue(seams ?? FakeSeams()),
      peopleClockProvider.overrideWithValue(() => testNow),
      qrScannerBuilderProvider.overrideWithValue(fakeScanner),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: HelixThemes.light(),
        routerConfig: router,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: app!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}
