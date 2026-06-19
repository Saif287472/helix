import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/main.dart';

void main() {
  testWidgets('HelixRemoteApp launches Remote messaging shell', (
    WidgetTester tester,
  ) async {
    // Use system temp as the database directory; initialize() is not called.
    // This smoke test only verifies that the widget tree renders correctly.
    final root = RemoteCompositionRoot.production(
      databaseDirectory: Directory.systemTemp.path,
    );
    await tester.pumpWidget(HelixRemoteApp(root: root));
    expect(find.text('Helix Remote'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Encrypted direct channel is ready.'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, 'hello remote');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.text('hello remote'), findsOneWidget);
  });

  test(
    'RemoteCompositionRoot startup state machine - idle until initialize()',
    () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
      );
      expect(root.startupState, RemoteStartupState.idle);
    },
  );

  test('RemoteCompositionRoot accessors throw before initialize()', () {
    final root = RemoteCompositionRoot.production(
      databaseDirectory: Directory.systemTemp.path,
    );
    expect(() => root.database, throwsA(isA<StateError>()));
    expect(() => root.syncEngine, throwsA(isA<StateError>()));
    expect(() => root.keyStorage, throwsA(isA<StateError>()));
  });

  test('withConfig validation rejects empty displayName', () {
    expect(
      () => RemoteCompositionRoot.withConfig(
        const RemoteProductConfig(
          displayName: '',
          packageId: 'com.test',
          secureStoragePrefix: 'helix_remote_v1_',
          methodChannelNamespace: 'ns',
          logNamespace: 'log',
          databaseDirectory: '/tmp',
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('withConfig validation rejects prefix without trailing underscore', () {
    expect(
      () => RemoteCompositionRoot.withConfig(
        const RemoteProductConfig(
          displayName: 'Test',
          packageId: 'com.test',
          secureStoragePrefix: 'helix_remote_v1',
          methodChannelNamespace: 'ns',
          logNamespace: 'log',
          databaseDirectory: '/tmp',
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
