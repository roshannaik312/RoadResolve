import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_options.dart';

/// A sign-in failure with a message that can be shown to the driver as-is.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Firebase Authentication: email/password, Google and Sign in with Apple.
///
/// Every method throws [AuthFailure] with a readable message, and returns
/// `false` (instead of throwing) when the user cancels a Google/Apple sheet.
class AuthService extends ChangeNotifier {
  AuthService([FirebaseAuth? auth]) : _authOverride = auth;

  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  StreamSubscription<User?>? _sub;
  User? _user;
  bool _ready = false;
  bool _googleInitialized = false;

  /// Runs after the user re-confirms and before the account is deleted,
  /// while they are still signed in (e.g. to delete their Firestore data).
  Future<void> Function(String uid)? beforeDelete;

  User? get user => _user;
  bool get signedIn => _user != null;

  /// False until Firebase reports the restored session (if any).
  bool get ready => _ready;

  String get displayLabel {
    final u = _user;
    if (u == null) return '';
    final name = u.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return u.email ?? 'Signed in';
  }

  /// Provider ids linked to the account, e.g. `password`, `google.com`, `apple.com`.
  List<String> get providers =>
      _user?.providerData.map((p) => p.providerId).toList() ?? const [];

  void start() {
    _user = _auth.currentUser;
    _ready = _user != null;
    _sub = _auth.userChanges().listen((u) {
      _user = u;
      _ready = true;
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------- email

  Future<void> signInWithEmail(String email, String password) => _run(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) => _run(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) return;
    if (name.trim().isNotEmpty) await user.updateDisplayName(name.trim());
    // Best effort: a failed verification email shouldn't block sign-up.
    unawaited(user.sendEmailVerification().catchError((_) {}));
    await user.reload();
  });

  Future<void> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> resendVerificationEmail() =>
      _run(() async => _auth.currentUser?.sendEmailVerification());

  // --------------------------------------------------------------- google

  Future<void> _initGoogle() async {
    if (_googleInitialized) return;
    final clientId = DefaultFirebaseOptions.currentPlatform.iosClientId;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        (clientId == null || clientId.isEmpty)) {
      throw const AuthFailure(
        'Google sign-in isn’t set up yet. Enable Google in the Firebase '
        'console, then run `flutterfire configure` again.',
      );
    }
    await GoogleSignIn.instance.initialize(clientId: clientId);
    _googleInitialized = true;
  }

  Future<GoogleSignInAccount?> _googleAccount() async {
    await _initGoogle();
    try {
      return await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw AuthFailure(
        'Google sign-in failed${e.description == null ? '' : ': ${e.description}'}',
      );
    }
  }

  AuthCredential _googleCredential(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google didn’t return an ID token.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Returns false if the user closed the Google sheet.
  Future<bool> signInWithGoogle() async {
    var completed = false;
    await _run(() async {
      final account = await _googleAccount();
      if (account == null) return;
      await _auth.signInWithCredential(_googleCredential(account));
      completed = true;
    });
    return completed;
  }

  // ---------------------------------------------------------------- apple

  /// Apple identity token plus the one-time authorization code (needed to
  /// revoke the token when the account is deleted).
  Future<(OAuthCredential, AuthorizationCredentialAppleID)?>
  _appleCredential() async {
    final rawNonce = _nonce();
    try {
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final idToken = apple.identityToken;
      if (idToken == null) {
        throw const AuthFailure('Apple didn’t return an identity token.');
      }
      final cred = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      );
      return (cred, apple);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      if (e.code == AuthorizationErrorCode.unknown) {
        // Error 1000: the build lacks the Sign in with Apple capability
        // (personal teams can't use it), or no Apple ID is signed in.
        throw const AuthFailure(
          'Sign in with Apple isn’t available in this build. '
          'Use email or Google for now.',
        );
      }
      throw AuthFailure('Sign in with Apple failed: ${e.message}');
    }
  }

  /// Returns false if the user closed the Apple sheet.
  Future<bool> signInWithApple() async {
    var completed = false;
    await _run(() async {
      final result = await _appleCredential();
      if (result == null) return;
      final (cred, apple) = result;
      final userCred = await _auth.signInWithCredential(cred);
      // Apple only shares the name on the very first sign-in.
      final user = userCred.user;
      final name = [
        apple.givenName,
        apple.familyName,
      ].whereType<String>().join(' ').trim();
      if (user != null && name.isNotEmpty && user.displayName == null) {
        await user.updateDisplayName(name);
        await user.reload();
      }
      completed = true;
    });
    return completed;
  }

  static Future<bool> appleAvailable() =>
      SignInWithApple.isAvailable().catchError((_) => false);

  // -------------------------------------------------------------- account

  Future<void> signOut() async {
    if (_googleInitialized) {
      await GoogleSignIn.instance.signOut().catchError((_) {});
    }
    await _auth.signOut();
  }

  /// Deletes the Firebase account. Firebase requires a recent sign-in, so the
  /// user re-confirms first: [password] for email accounts, otherwise the
  /// Google/Apple sheet. Returns false if they cancel that sheet.
  Future<bool> deleteAccount({String? password}) async {
    var completed = false;
    await _run(() async {
      final user = _auth.currentUser;
      if (user == null) return;
      final ids = providers;
      String? appleAuthCode;

      if (ids.contains('apple.com')) {
        final result = await _appleCredential();
        if (result == null) return;
        await user.reauthenticateWithCredential(result.$1);
        appleAuthCode = result.$2.authorizationCode;
      } else if (ids.contains('google.com')) {
        final account = await _googleAccount();
        if (account == null) return;
        await user.reauthenticateWithCredential(_googleCredential(account));
      } else if (ids.contains('password')) {
        if (password == null || password.isEmpty) {
          throw const AuthFailure('Enter your password to confirm.');
        }
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        );
      }

      await beforeDelete?.call(user.uid);

      // Apple requires apps to revoke Sign in with Apple tokens on deletion.
      if (appleAuthCode != null) {
        await _auth.revokeTokenWithAuthorizationCode(appleAuthCode);
      }
      await user.delete();
      if (_googleInitialized) {
        await GoogleSignIn.instance.disconnect().catchError((_) {});
      }
      completed = true;
    });
    return completed;
  }

  // -------------------------------------------------------------- helpers

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(messageFor(e.code, e.message));
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure('Something went wrong. Please try again. ($e)');
    }
  }

  @visibleForTesting
  static String messageFor(String code, [String? fallback]) => switch (code) {
    'invalid-email' => 'That email address doesn’t look right.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' ||
    'INVALID_LOGIN_CREDENTIALS' => 'Email or password is incorrect.',
    'email-already-in-use' =>
      'An account already exists for that email. Try signing in instead.',
    'weak-password' => 'Choose a stronger password (at least 8 characters).',
    'account-exists-with-different-credential' =>
      'This email is already registered with a different sign-in method. '
          'Sign in that way first.',
    'too-many-requests' =>
      'Too many attempts. Wait a few minutes and try again.',
    'network-request-failed' => 'No connection. Check your internet and retry.',
    'operation-not-allowed' =>
      'This sign-in method isn’t enabled for Clear Roads yet.',
    'requires-recent-login' => 'Please sign in again to continue.',
    'user-mismatch' => 'That’s a different account from the one signed in.',
    _ => fallback ?? 'Sign-in failed ($code).',
  };

  static String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
