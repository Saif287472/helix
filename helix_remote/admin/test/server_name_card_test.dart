import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/widgets/server_name_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder get _saveButton => find.widgetWithText(FilledButton, 'Save name');

void main() {
  testWidgets('pre-fills the name the server already has', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: 'Rahman Family Server',
          maxLength: 60,
          onSave: (name) async => name,
        ),
      ),
    );

    expect(find.text('Rahman Family Server'), findsOneWidget);
  });

  testWidgets('Save is disabled until the name actually changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: 'Existing',
          maxLength: 60,
          onSave: (name) async => name,
        ),
      ),
    );

    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.pump();

    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });

  testWidgets('saving sends the typed name and confirms', (tester) async {
    String? sent;
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          onSave: (name) async {
            sent = name;
            return name.trim();
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Rahman Family Server');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(sent, 'Rahman Family Server');
    expect(find.textContaining('Saved.'), findsOneWidget);
  });

  testWidgets('shows the normalized name the server actually stored', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          // The backend collapses whitespace; the field must end up
          // showing what users will really see.
          onSave: (name) async => 'Home Server',
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  Home    Server  ');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Home Server'), findsOneWidget);
    // Back to a clean state - nothing left unsaved.
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
  });

  testWidgets("surfaces the server's own rejection message", (tester) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          onSave: (_) async => throw const AdminRequestException(
            'server_name must be 60 characters or fewer',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'way too long');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('server_name must be 60 characters or fewer'),
      findsOneWidget,
    );
  });

  testWidgets('a transport failure reports plainly, not as a raw exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          onSave: (_) async => throw Exception('SocketException: refused'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Anything');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('editing after an error clears it', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          onSave: (_) async => throw const AdminRequestException('nope'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Bad');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(find.text('nope'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Better');
    // pumpAndSettle, not pump: InputDecorator fades the error text out, so
    // the old label lingers in the tree for the length of that animation.
    await tester.pumpAndSettle();

    expect(find.text('nope'), findsNothing);
  });

  testWidgets('the empty-name hint names the host users would see instead', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          serverHost: 'hr.agiletechbd.com',
          onSave: (name) async => name,
        ),
      ),
    );

    expect(find.textContaining('hr.agiletechbd.com'), findsOneWidget);
    expect(find.textContaining('Leave empty'), findsOneWidget);
  });

  // A poll or manual refresh landing mid-edit must not wipe what is being
  // typed.
  testWidgets('a background refresh does not overwrite an unsaved edit', (
    tester,
  ) async {
    Widget card(String name) => _wrap(
      ServerNameCard(
        initialName: name,
        maxLength: 60,
        onSave: (value) async => value,
      ),
    );

    await tester.pumpWidget(card('Original'));
    await tester.enterText(find.byType(TextField), 'Half-typed edit');
    await tester.pump();

    await tester.pumpWidget(card('Changed Elsewhere'));
    await tester.pump();

    expect(find.text('Half-typed edit'), findsOneWidget);
  });

  testWidgets('a background refresh does update a clean field', (tester) async {
    Widget card(String name) => _wrap(
      ServerNameCard(
        initialName: name,
        maxLength: 60,
        onSave: (value) async => value,
      ),
    );

    await tester.pumpWidget(card('Original'));
    await tester.pumpWidget(card('Changed Elsewhere'));
    await tester.pump();

    expect(find.text('Changed Elsewhere'), findsOneWidget);
  });

  testWidgets('the field enforces the length limit the server reported', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          onSave: (name) async => name,
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 60);
  });
}
