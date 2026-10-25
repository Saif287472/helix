import 'package:flutter/material.dart' hide Page;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/app.dart';
import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_admin/src/services/admin_services.dart';
import 'package:helix_admin/src/services/token_vault.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show Page, PageRequest;

import 'support/fake_admin_server.dart';
import 'support/harness.dart';

/// Operators who could not get in, and a code that could not be got back
/// (B18).
final class _BrokenVault implements TokenVault {
  @override
  Future<StoredSession?> read() async =>
      throw PlatformException(code: 'keystore', message: 'cannot be opened');

  @override
  Future<void> write(StoredSession stored) async {}

  @override
  Future<void> clear() async =>
      throw PlatformException(code: 'keystore', message: 'cannot be opened');
}

/// A list of numbers whose pages the test controls.
final class _Numbers extends PagedController<int> {
  _Numbers(super.ctx, this.pages) : super(pageSize: 2);

  final List<List<int>> pages;

  @override
  Future<Page<int>> fetch(PageRequest page) async {
    final at = page.cursor == null ? 0 : int.parse(page.cursor!);
    return Page(
      items: pages[at],
      nextCursor: at + 1 < pages.length ? '${at + 1}' : null,
    );
  }
}

void main() {
  late AdminHarness h;
  setUp(() => h = AdminHarness());

  group('a console that cannot read its storage', () {
    testWidgets('lands on the sign-in form with the reason (AUD-17a-1)', (
      tester,
    ) async {
      h.configured();
      final base = h.services();
      await tester.pumpWidget(
        HelixAdminApp(
          services: AdminServices(
            loadSettings: base.loadSettings,
            vault: _BrokenVault(),
            deviceLock: base.deviceLock,
            now: base.now,
            apiFactory: base.apiFactory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The console could not read its saved sign-in. Sign in again.',
        ),
        findsWidgets,
      );
      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    });

    testWidgets('settings that cannot be read do the same', (tester) async {
      final base = h.services();
      await tester.pumpWidget(
        HelixAdminApp(
          services: AdminServices(
            loadSettings: () async => throw PlatformException(code: 'prefs'),
            vault: h.vault,
            deviceLock: base.deviceLock,
            now: base.now,
            apiFactory: base.apiFactory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    });
  });

  testWidgets('a saved session survives a failed launch check and can be '
      'used again (AUD-17a-2)', (tester) async {
    h.saveSession();
    h.server.unreachable = true;
    await h.pumpApp(tester);
    expect(find.byKey(const Key('retry-saved-session')), findsOneWidget);
    expect(h.vault.stored, isNotNull);

    h.server.unreachable = false;
    await tester.tap(find.byKey(const Key('retry-saved-session')));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsWidgets);
    expect(find.byKey(const Key('retry-saved-session')), findsNothing);
  });

  test('signing out forgets the token even when the server cannot be '
      'reached (AUD-11c-2)', () async {
    h.configured();
    final api = h.services().apiFactory(
      FakeAdminServer.host,
      session: h.server.issue(),
    );
    expect(api.auth.session, isNotNull);
    h.server.unreachable = true;
    await expectLater(api.admin.signOut(), throwsA(anything));
    expect(api.auth.session, isNull);
    await api.close();
  });

  testWidgets('a segment is a 48 px tap target (AUD-17a-3)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleSegmented(
            segments: const [ConsoleSegment('One'), ConsoleSegment('Two')],
            selected: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(InkWell).first);
    expect(size.height, greaterThanOrEqualTo(48));
  });

  group('the code that is shown once (AUD-17b-2)', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCodeOnceDialog(
                context,
                title: 'Recovery code',
                code: 'HLX-REC-ONLYONCE',
                expiresAt: DateTime.utc(2030),
                explanation: 'Give it to the owner.',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('survives the back gesture', (tester) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shown-once-code')), findsOneWidget);
      expect(find.text('HLX-REC-ONLYONCE'), findsOneWidget);
    });

    testWidgets('leaves by a button, on purpose', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('discard-code')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shown-once-code')), findsNothing);
      await open(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shown-once-code')), findsNothing);
    });
  });

  testWidgets('a filter that hides every loaded row still offers more '
      '(AUD-17b-3)', (tester) async {
    h.saveSession();
    final api = h.services().apiFactory(Uri.parse('http://localhost'));
    final numbers = _Numbers(
      AdminContext(api: api, report: (_) {}, now: h.clock.call),
      [
        [1, 3],
        [2, 4],
      ],
    );
    addTearDown(numbers.dispose);
    await numbers.refresh();
    expect(numbers.hasMore, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedListView<int>(
            controller: numbers,
            // The page holds no even number yet; page two does.
            shown: [
              for (final n in numbers.items)
                if (n.isEven) n,
            ],
            itemBuilder: (context, n) => Text('even $n'),
            emptyIcon: Icons.filter_alt,
            emptyTitle: 'None loaded',
          ),
        ),
      ),
    );
    expect(find.text('None loaded'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(numbers.items, [1, 3, 2, 4]);
  });
}
