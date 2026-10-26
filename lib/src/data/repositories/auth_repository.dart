import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../../core/security/password_policy.dart';

/// Everything that talks to Supabase Auth.
///
/// OAuth for Apple and Google is wired but not enabled: the methods
/// exist and are correct, and turning the providers on in the Supabase
/// dashboard is the only remaining step. They are not stubs.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.id;

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    final String? cleanEmail = InputSanitizer.email(email);
    if (cleanEmail == null) {
      throw const Failure('Enter a valid email address.', isAuth: true);
    }
    if (password.isEmpty) {
      throw const Failure('Enter your password.', isAuth: true);
    }
    try {
      await _auth.signInWithPassword(email: cleanEmail, password: password);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final String? cleanEmail = InputSanitizer.email(email);
    if (cleanEmail == null) {
      throw const Failure('Enter a valid email address.', isAuth: true);
    }

    final List<String> problems = PasswordPolicy.violations(password);
    if (problems.isNotEmpty) {
      throw Failure('Password needs: ${problems.join(', ').toLowerCase()}.',
          isAuth: true);
    }

    final String name = InputSanitizer.singleLine(displayName, maxLength: 64);
    if (name.isEmpty) {
      throw const Failure('Tell us what to call you.', isAuth: true);
    }

    try {
      // display_name goes into user_metadata, which the database trigger
      // reads to create the profile and the personal library. Note that
      // user_metadata is client-writable — it is safe for a display name
      // and must never be used for authorisation.
      await _auth.signUp(
        email: cleanEmail,
        password: password,
        data: <String, dynamic>{'display_name': name},
      );
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final String? cleanEmail = InputSanitizer.email(email);
    if (cleanEmail == null) {
      throw const Failure('Enter a valid email address.', isAuth: true);
    }
    try {
      await _auth.resetPasswordForEmail(cleanEmail);
    } catch (error) {
      throw Failure.from(error);
    }
    // The caller shows the same confirmation whether or not the address
    // exists. Anything else is an account-enumeration oracle.
  }

  Future<void> updatePassword(String newPassword) async {
    final List<String> problems = PasswordPolicy.violations(newPassword);
    if (problems.isNotEmpty) {
      throw Failure('Password needs: ${problems.join(', ').toLowerCase()}.',
          isAuth: true);
    }
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Structural readiness for Apple and Google. Enable the provider in
  /// the Supabase dashboard and add the redirect scheme to the native
  /// manifests; no code change is needed here.
  Future<void> signInWithApple() => _oauth(OAuthProvider.apple);

  Future<void> signInWithGoogle() => _oauth(OAuthProvider.google);

  Future<void> _oauth(OAuthProvider provider) async {
    try {
      await _auth.signInWithOAuth(
        provider,
        redirectTo: 'app.cookistrybook://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> signOut() async {
    try {
      // Revokes the refresh token server-side as well as clearing the
      // local copy. A local-only sign-out leaves a token that still
      // works if it is ever recovered from the device.
      await _auth.signOut(scope: SignOutScope.global);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Forces a new JWT. Needed after the active library claim changes if
  /// the optional migration 0006 hardening is applied.
  Future<void> refreshSession() async {
    try {
      await _auth.refreshSession();
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
