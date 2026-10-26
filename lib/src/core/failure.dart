import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure the user can be shown.
///
/// Database and network errors are translated here rather than at the
/// widget layer, so that a Postgres error code never reaches the screen.
/// Leaking `new row violates row-level security policy for table
/// "pantry_items"` tells an attacker both the table name and that a
/// policy exists on it.
class Failure implements Exception {
  const Failure(this.message, {this.isAuth = false, this.debug});

  final String message;
  final bool isAuth;

  /// Never rendered. Present so logs keep the original cause.
  final Object? debug;

  @override
  String toString() => 'Failure($message)';

  static Failure from(Object error) {
    if (error is Failure) return error;

    if (error is AuthException) {
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

  static String _authMessage(AuthException error) {
    final String raw = error.message.toLowerCase();
    if (raw.contains('invalid login')) {
      // Deliberately does not distinguish "no such account" from "wrong
      // password". The difference is an account-enumeration oracle.
      return 'That email and password combination was not recognised.';
    }
    if (raw.contains('already registered')) {
      return 'If that address can be used, a confirmation email is on its way.';
    }
    if (raw.contains('rate') || raw.contains('too many')) {
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
