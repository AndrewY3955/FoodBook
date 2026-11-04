import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure the user can be shown.
///
/// Database and network errors are translated here rather than at the
/// widget layer, so that a Postgres error code never reaches the screen.
/// Leaking `new row violates row-level security policy for table
/// "pantry_items"` tells an attacker both the table name and that a
/// policy exists on it.
class Failure implements Exception {
  const Failure(this.message,
      {this.isAuth = false, this.accountExists = false, this.debug});

  final String message;
  final bool isAuth;

  /// Signup hit an address that already has an account. Deliberately
  /// distinguishable so the UI can steer the user to sign-in or reset.
  final bool accountExists;

  /// Never rendered. Present so logs keep the original cause.
  final Object? debug;

  @override
  String toString() => 'Failure($message)';

  static Failure from(Object error) {
    if (error is Failure) return error;

    if (error is AuthException) {
      if (error.message.toLowerCase().contains('already registered')) {
        return Failure(accountExistsMessage,
            isAuth: true, accountExists: true, debug: error);
      }
      return Failure(_authMessage(error), isAuth: true, debug: error);
    }

    if (error is PostgrestException) {
      return Failure(_postgrestMessage(error), debug: error);
    }

    if (error is StorageException) {
      return Failure(
        'That image could not be saved. Try a different photo.',
        debug: error,
      );
    }

    return Failure('Something went wrong. Please try again.', debug: error);
  }

  static const String accountExistsMessage =
      'An account with this email already exists. Sign in, verify your '
      'email if you haven\'t yet, or reset your password.';

  static String _authMessage(AuthException error) {
    final String raw = error.message.toLowerCase();
    if (raw.contains('invalid login')) {
      // Deliberately does not distinguish "no such account" from "wrong
      // password". The difference is an account-enumeration oracle.
      return 'That email and password combination was not recognised.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Your email is not verified yet. Use "Resend confirmation email" below.';
    }
    if (raw.contains('rate') ||
        raw.contains('too many') ||
        error.statusCode == '429' ||
        (error is AuthApiException &&
            error.code?.contains('rate_limit') == true)) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return 'Sign-in failed. Please try again.';
  }

  static String _postgrestMessage(PostgrestException error) {
    switch (error.code) {
      case '42501': // insufficient_privilege - an RLS policy refused it
        return 'You do not have access to that cookbook.';
      case '23505': // unique_violation
        return 'That item is already on the list.';
      case '23503': // foreign_key_violation
        return 'That item no longer exists.';
      case '23514': // check_violation
        return 'Some of those details are not valid. Check the highlighted fields.';
      case 'PGRST301':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'The server rejected that change.';
    }
  }
}
