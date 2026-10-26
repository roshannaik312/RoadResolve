import 'package:clear_roads/screens/auth_screen.dart';
import 'package:clear_roads/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakeAuth extends AuthService {
  final calls = <String>[];
  AuthFailure? failWith;

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _record('signIn:$email:$password');

  @override
  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) => _record('signUp:$name:$email');

  @override
  Future<void> sendPasswordReset(String email) => _record('reset:$email');
}

Future<FakeAuth> pumpAuth(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = FakeAuth();
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: const MaterialApp(home: AuthScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('sign in validates, then submits trimmed email', (tester) async {
    final auth = await pumpAuth(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(auth.calls, isEmpty);

    await tester.enterText(field('Email'), ' driver@example.com ');
    await tester.enterText(field('Password'), 'hunter22');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['signIn: driver@example.com :hunter22']);
  });

  testWidgets('shows the service error message', (tester) async {
    final auth = await pumpAuth(tester);
    auth.failWith = const AuthFailure('Email or password is incorrect.');

    await tester.enterText(field('Email'), 'driver@example.com');
    await tester.enterText(field('Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('sign up checks password length and match', (tester) async {
    final auth = await pumpAuth(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Create account'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Name'), 'Sam');
    await tester.enterText(field('Email'), 'sam@example.com');
    await tester.enterText(field('Password'), 'short');
    await tester.enterText(field('Confirm password'), 'other');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords don’t match'), findsOneWidget);

    await tester.enterText(field('Password'), 'longenough');
    await tester.enterText(field('Confirm password'), 'longenough');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['signUp:Sam:sam@example.com']);
  });

  testWidgets('forgot password carries the email and confirms', (tester) async {
    final auth = await pumpAuth(tester);
    await tester.enterText(field('Email'), 'driver@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset:driver@example.com']);
    expect(find.text('Check your email'), findsOneWidget);

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  test('maps Firebase error codes to readable messages', () {
    expect(
      AuthService.messageFor('invalid-credential'),
      'Email or password is incorrect.',
    );
    expect(AuthService.messageFor('email-already-in-use'), contains('exists'));
    expect(AuthService.messageFor('weird', 'fallback'), 'fallback');
  });
}
