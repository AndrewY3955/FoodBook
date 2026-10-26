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

  /// Longest edge, in pixels, that a cover image is resized to before
  /// upload. Uploading a 12 MP phone photo to show a 400 px card wastes
  /// the user's data and the project's storage quota.
  static const int coverMaxEdge = 1280;

  static const int coverJpegQuality = 82;

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
