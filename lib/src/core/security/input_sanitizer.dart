import '../env.dart';

/// Client-side input hygiene.
///
/// IMPORTANT FRAMING. Nothing in this file is a security boundary.
/// Anyone can obtain the anon key from the shipped binary and call
/// PostgREST directly, skipping every line below. The real controls are
/// the CHECK constraints and RLS policies in the database.
///
/// What this file is for: keeping malformed data out of the round trip,
/// giving the user an error in the form rather than from the server,
/// and making sure the strings the app renders are the strings the user
/// meant. It mirrors the server rules deliberately — if you loosen one
/// side, loosen both, or the user gets a rejection they cannot explain.
class InputSanitizer {
  const InputSanitizer._();

  /// Control characters, and the bidirectional override characters that
  /// let a string render in an order different from the order it is
  /// stored in. A recipe titled with an embedded RLO can be made to
  /// display as something other than what it is.
  static final RegExp _dangerous = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F'
    r'\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  static final RegExp _whitespaceRun = RegExp(r'[ \t]{2,}');
  static final RegExp _blankLineRun = RegExp(r'\n{3,}');

  /// Single-line free text: names, titles, tags.
  static String singleLine(String input, {int maxLength = 160}) {
    final String cleaned = input
        .replaceAll(_dangerous, '')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(_whitespaceRun, ' ')
        .trim();
    return cleaned.length <= maxLength
        ? cleaned
        : cleaned.substring(0, maxLength).trimRight();
  }

  /// Multi-line free text: descriptions, step instructions, notes.
  static String multiLine(String input, {int maxLength = 4000}) {
    final String cleaned = input
        .replaceAll(_dangerous, '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_whitespaceRun, ' ')
        .replaceAll(_blankLineRun, '\n\n')
        .trim();
    return cleaned.length <= maxLength
        ? cleaned
        : cleaned.substring(0, maxLength).trimRight();
  }

  /// Returns a normalised https URL, or null if the input is not one.
  ///
  /// Mirrors public.is_safe_http_url in migration 0001. Rejected:
  /// every non-https scheme (javascript:, data:, vbscript:, file:),
  /// protocol-relative //host, embedded credentials, whitespace,
  /// quotes, angle brackets, backslashes, and anything over 2048 chars.
  static String? safeUrl(String input, {Set<String>? allowedHosts}) {
    final String trimmed = input.trim().replaceAll(_dangerous, '');
    if (trimmed.isEmpty || trimmed.length > 2048) return null;

    // Reject the breakout characters before parsing. Uri.parse is
    // permissive about some of them and will happily percent-encode a
    // quote rather than refuse it.
    if (RegExp(r'''[\s<>"'`\\{}|^]''').hasMatch(trimmed)) return null;

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null;

    final Set<String> hosts = allowedHosts ?? const <String>{};
    if (hosts.isNotEmpty && !hosts.contains(uri.host.toLowerCase())) {
      return null;
    }

    return uri.toString();
  }

  /// The step-by-step video field. Same rules, plus the host allowlist.
  static String? videoUrl(String input) =>
      safeUrl(input, allowedHosts: Env.allowedVideoHosts);

  /// The import field. Any https host is permitted, because the point
  /// of the feature is pasting a link from wherever the user found it.
  /// The Edge Function re-validates before it fetches anything.
  static String? importUrl(String input) => safeUrl(input);

  /// Accepts `2`, `2.5`, `2,5`, `1/2`, `1 1/2`. Returns null if the
  /// text is not a positive quantity within the server's bounds.
  static double? quantity(String input) {
    final String text = input.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;

    final RegExpMatch? mixed =
        RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(text);
    if (mixed != null) {
      final double whole = double.parse(mixed.group(1)!);
      final double numerator = double.parse(mixed.group(2)!);
      final double denominator = double.parse(mixed.group(3)!);
      if (denominator == 0) return null;
      return _bounded(whole + numerator / denominator);
    }

    final RegExpMatch? fraction =
        RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(text);
    if (fraction != null) {
      final double denominator = double.parse(fraction.group(2)!);
      if (denominator == 0) return null;
      return _bounded(double.parse(fraction.group(1)!) / denominator);
    }

    final double? value = double.tryParse(text);
    return value == null ? null : _bounded(value);
  }

  static double? _bounded(double value) {
    if (value <= 0 || value > 100000) return null;
    if (value.isNaN || value.isInfinite) return null;
    return double.parse(value.toStringAsFixed(3));
  }

  /// Trimmed and lowercased. Format is checked, deliverability is not —
  /// that is what the confirmation email is for.
  static String? email(String input) {
    final String value = input.trim().toLowerCase().replaceAll(_dangerous, '');
    if (value.length < 3 || value.length > 254) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$').hasMatch(value)) {
      return null;
    }
    return value;
  }
}
