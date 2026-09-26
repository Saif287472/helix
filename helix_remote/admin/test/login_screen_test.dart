import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/login_screen.dart';
import 'package:helix_admin/theme/app_theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  testWidgets('renders direct login form fields and header when needsSetup is false', (tester) async {
    final urlController = TextEditingController(
      text: 'https://helix.agiletechbd.com',
    );
    final passwordController = TextEditingController();

    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: urlController,
          passwordController: passwordController,
          isConnecting: false,
          errorMessage: null,
          needsSetup: false,
          onSignIn: () {},
        ),
      ),
    );

    expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
    expect(find.byKey(const Key('login_url_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('renders first-time setup prompt when needsSetup is true', (tester) async {
    final urlController = TextEditingController(
      text: 'https://helix.agiletechbd.com',
    );
    final passwordController = TextEditingController();

    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: urlController,
          passwordController: passwordController,
          isConnecting: false,
          errorMessage: null,
          needsSetup: true,
          onSignIn: () {},
        ),
      ),
    );

    expect(find.text('CREATE ADMIN PASSWORD'), findsOneWidget);
    expect(find.byKey(const Key('login_url_field')), findsOneWidget);
    expect(find.byKey(const Key('setup_password_field')), findsOneWidget);
    expect(find.byKey(const Key('setup_confirm_password_field')), findsOneWidget);
    expect(find.byKey(const Key('setup_submit_button')), findsOneWidget);
    expect(find.text('SET PASSWORD & SIGN IN'), findsOneWidget);
  });

  testWidgets('validates password length and match in setup mode', (tester) async {
    String? submittedPassword;
    final passwordController = TextEditingController();

    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: TextEditingController(text: 'https://helix.test'),
          passwordController: passwordController,
          isConnecting: false,
          errorMessage: null,
          needsSetup: true,
          onSignIn: () {},
          onSetupPassword: (pass) => submittedPassword = pass,
        ),
      ),
    );

    // 1. Password too short (< 6 chars)
    passwordController.text = '12345';
    await tester.enterText(find.byKey(const Key('setup_confirm_password_field')), '12345');
    await tester.ensureVisible(find.byKey(const Key('setup_submit_button')));
    await tester.tap(find.byKey(const Key('setup_submit_button')));
    await tester.pump();

    expect(find.text('Password must be at least 6 characters long.'), findsOneWidget);
    expect(submittedPassword, isNull);

    // 2. Passwords mismatch
    passwordController.text = 'password123';
    await tester.enterText(find.byKey(const Key('setup_confirm_password_field')), 'different123');
    await tester.ensureVisible(find.byKey(const Key('setup_submit_button')));
    await tester.tap(find.byKey(const Key('setup_submit_button')));
    await tester.pump();

    expect(find.text('Passwords do not match. Please re-enter.'), findsOneWidget);
    expect(submittedPassword, isNull);

    // 3. Valid matching passwords
    passwordController.text = 'super_secret_admin_99';
    await tester.enterText(find.byKey(const Key('setup_confirm_password_field')), 'super_secret_admin_99');
    await tester.ensureVisible(find.byKey(const Key('setup_submit_button')));
    await tester.tap(find.byKey(const Key('setup_submit_button')));
    await tester.pump();

    expect(submittedPassword, equals('super_secret_admin_99'));
  });

  testWidgets('toggles password visibility on eye icon tap', (tester) async {
    final passwordController = TextEditingController(text: 'secret_pass_123');

    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: TextEditingController(),
          passwordController: passwordController,
          isConnecting: false,
          errorMessage: null,
          onSignIn: () {},
        ),
      ),
    );

    TextField passField = tester.widget<TextField>(
      find.byKey(const Key('login_password_field')),
    );
    expect(passField.obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    passField = tester.widget<TextField>(
      find.byKey(const Key('login_password_field')),
    );
    expect(passField.obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();

    passField = tester.widget<TextField>(
      find.byKey(const Key('login_password_field')),
    );
    expect(passField.obscureText, isTrue);
  });

  testWidgets('triggers onSignIn on button tap', (tester) async {
    var signedIn = false;
    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: TextEditingController(text: 'https://helix.test'),
          passwordController: TextEditingController(text: 'pass'),
          isConnecting: false,
          errorMessage: null,
          onSignIn: () => signedIn = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pump();

    expect(signedIn, isTrue);
  });

  testWidgets('renders error banner when errorMessage is set', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: TextEditingController(),
          passwordController: TextEditingController(),
          isConnecting: false,
          errorMessage: 'Invalid server URL or admin password.',
          onSignIn: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('login_error_text')), findsOneWidget);
    expect(
      find.text('Invalid server URL or admin password.'),
      findsOneWidget,
    );
  });

  testWidgets('disables button and shows progress indicator when connecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: TextEditingController(),
          passwordController: TextEditingController(),
          isConnecting: true,
          errorMessage: null,
          onSignIn: () {},
        ),
      ),
    );

    final btn = tester.widget<ElevatedButton>(
      find.byKey(const Key('login_button')),
    );
    expect(btn.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // The self-hosting guide belongs to the helix-remote welcome / sign-in
  // flow, not to this console. The button that used to sit here opened a
  // second copy that had drifted from it.
  testWidgets('offers no self-hosting guide link', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LoginScreen(
          urlController: TextEditingController(),
          passwordController: TextEditingController(),
          isConnecting: false,
          errorMessage: null,
          onSignIn: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('login_guide_button')), findsNothing);
    expect(find.text('How do I own a personal server?'), findsNothing);
  });
}
