import 'package:flutter/foundation.dart';

/// Compile-time configuration.
///
/// Values arrive through --dart-define, never from a checked-in file.
/// The publishable key is public by design — it identifies the project
/// and carries the `anon` role, nothing more. Every authority decision is
/// made by Row-Level Security in the database. The service_role key
/// must never appear in this application; it bypasses RLS entirely and
/// belongs only in Edge Functions and server-side jobs.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Prefers SUPABASE_PUBLISHABLE_KEY and falls back to the older
  /// SUPABASE_ANON_KEY define, so existing build invocations keep
  /// working while the name catches up with Supabase's own.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  /// Where the link in the signup / password-reset email sends the user.
  /// Without it Supabase falls back to the project's "Site URL", which is
  /// how users ended up on a GitHub 404. Override with
  /// --dart-define=AUTH_REDIRECT_URL=... ; it must also be listed under
  /// Authentication > URL Configuration > Redirect URLs in Supabase.
  static const String _authRedirectOverride =
      String.fromEnvironment('AUTH_REDIRECT_URL');

  static const String mobileAuthRedirect = 'io.cookistrybook://login-callback';

  static String? get authRedirectUrl {
    if (_authRedirectOverride.isNotEmpty) return _authRedirectOverride;
    // Keep the path: the app is served from /FoodBook/ on GitHub Pages and
    // the allow-list entry is scoped to that path.
    if (kIsWeb) {
      final Uri u = Uri.base;
      return Uri(
        scheme: u.scheme,
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: u.path,
      ).toString();
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return mobileAuthRedirect;
    }
    return null;
  }

  /// Hosts accepted for the external step-by-step video link. Empty
  /// means "any https host". Keeping it populated narrows the surface
  /// for embed-based attacks and for users pasting tracking links.
  static const Set<String> allowedVideoHosts = <String>{
    'youtube.com',
    'www.youtube.com',
    'youtu.be',
    'm.youtube.com',
    'vimeo.com',
    'player.vimeo.com',
    'www.instagram.com',
    'instagram.com',
    'www.tiktok.com',
    'tiktok.com',
    'vm.tiktok.com',
  };

  static const String coverBucket = 'recipe-covers';

  /// Longest edge, in pixels, that a recipe image is resized to before
  /// upload. A 12 MP phone photo only needs around 900 px at the full
  /// recipe detail size, and aggressively downsizing it cuts storage and
  /// upload time without harming the UI.
  static const int coverMaxEdge = 900;

  static const int coverJpegQuality = 68;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Fails loudly at startup rather than producing an unexplained
  /// network error on the first query.
  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) '
        'must be provided via --dart-define. '
        'See README.md for the exact build invocation.',
      );
    }
  }
}
