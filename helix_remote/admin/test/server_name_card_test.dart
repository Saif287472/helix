import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/widgets/server_name_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The card is collapsed by default: it shows the stored name and an
/// "Edit Name" button, and only reveals the field once that is tapped. These
/// tests drive that flow rather than assuming a permanently visible field,
/// which is what the pre-redesign widget looked like.
Future<void> _enterEditMode(WidgetTester tester) async {
  await tester.tap(find.text('Edit Name'));
  await tester.pumpAndSettle();
}

Finder get _saveButton => find.widgetWithText(FilledButton, 'Save Name');

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
    // Collapsed: no field until the editor is opened.
    expect(find.byType(TextField), findsNothing);
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

    await _enterEditMode(tester);
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.pump();

    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });

  testWidgets('opening the editor and cancelling writes nothing', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: 'Existing',
          maxLength: 60,
          onSave: (name) async {
            saves++;
            return name;
          },
        ),
      ),
    );

    await _enterEditMode(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Existing'), findsOneWidget);
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

    await _enterEditMode(tester);
    await tester.enterText(find.byType(TextField), 'Rahman Family Server');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(sent, 'Rahman Family Server');
    // Collapses back to the stored name on success, which is the confirmation.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Rahman Family Server'), findsOneWidget);
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

    await _enterEditMode(tester);
    await tester.enterText(find.byType(TextField), '  Home    Server  ');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Home Server'), findsOneWidget);
    // Back to a clean state - re-opening the editor starts from the stored
    // name, so Save is disabled again rather than offering a redundant write.
    await _enterEditMode(tester);
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

    await _enterEditMode(tester);
    await tester.enterText(find.byType(TextField), 'way too long');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('server_name must be 60 characters or fewer'),
      findsOneWidget,
    );
    // Stays open on failure so the typed name is not lost.
    expect(find.byType(TextField), findsOneWidget);
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

    await _enterEditMode(tester);
    await tester.enterText(find.byType(TextField), 'Anything');
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't reach server."), findsOneWidget);
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

    await _enterEditMode(tester);
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

  // The empty-name hint names the *server's* computed fallback name, not a
  // host. `serverHost` was accepted here and never read, so the card had no
  // way to show a host; the parameter is gone rather than left inert.
  testWidgets('the empty-name hint names the server fallback instead', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ServerNameCard(
          initialName: '',
          maxLength: 60,
          fallbackName: 'Private Server #4242',
          onSave: (name) async => name,
        ),
      ),
    );

    expect(find.textContaining('Private Server #4242'), findsOneWidget);
  });

  testWidgets('with no name and no fallback it shows a neutral placeholder', (
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

    // A plausible-looking invented server name would be a lie; this says what
    // it is.
    expect(find.text('Helix Server'), findsOneWidget);
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
    await _enterEditMode(tester);
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

    await _enterEditMode(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 60);
  });
}
