/// Password rules, enforced in the UI and mirrored in the Supabase Auth
/// project settings.
///
/// Both halves are required. The UI copy tells the user what is wrong
/// while they type; the project setting is what actually holds, because
/// the Auth endpoint can be called without this app.
class PasswordPolicy {
  const PasswordPolicy._();

  static const int minLength = 12;

  /// bcrypt silently ignores everything past 72 bytes. A user who sets
  /// a 200-character passphrase would otherwise be authenticated by its
  /// first 72 bytes without ever being told.
  static const int maxLength = 72;

  static List<String> violations(String password) {
    final List<String> problems = <String>[];

    if (password.length < minLength) {
      problems.add('At least $minLength characters');
    }
    if (password.length > maxLength) {
      problems.add('No more than $maxLength characters');
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      problems.add('One lowercase letter');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      problems.add('One uppercase letter');
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      problems.add('One number');
    }
    if (!RegExp(r'''[!@#$%^&*()_+\-=\[\]{};:'",.<>/?\\|`~]''')
        .hasMatch(password)) {
      problems.add('One symbol');
    }
    if (RegExp(r'\s').hasMatch(password)) {
      problems.add('No spaces or tabs');
    }
    if (_looksCommon(password)) {
      problems.add('Not a common or guessable password');
    }

    return problems;
  }

  static bool isValid(String password) => violations(password).isEmpty;

  /// A short local screen for the passwords that show up first in every
  /// credential-stuffing list. It is not a substitute for Supabase's
  /// HaveIBeenPwned check — turn that on in Auth settings as well.
  static bool _looksCommon(String password) {
    final String lower = password.toLowerCase();
    const List<String> seeds = <String>[
      'password',
      'qwerty',
      'letmein',
      'welcome',
      'admin',
      'iloveyou',
      'monkey',
      'dragon',
      'football',
      'baseball',
      'sunshine',
      'princess',
      'abc123',
      'trustno1',
      'recipe',
      'library',
      'kitchen',
      'cookbook',
      'cookistrybook',
      'cookistry',
      'recipebook',
      'foodbook',
    ];
    for (final String seed in seeds) {
      if (lower.contains(seed)) return true;
    }
    if (RegExp(r'^(.)\1+$').hasMatch(password)) return true;
    if (lower.contains('123456') || lower.contains('654321')) return true;
    return false;
  }

  /// 0.0 to 1.0, for the strength bar. Presentational only; never used
  /// to decide whether a password is acceptable.
  static double strength(String password) {
    if (password.isEmpty) return 0;
    double score = 0;
    score += (password.length.clamp(0, 24)) / 24 * 0.45;
    if (RegExp(r'[a-z]').hasMatch(password)) score += 0.1;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 0.1;
    if (RegExp(r'\d').hasMatch(password)) score += 0.1;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score += 0.15;
    final int distinct = password.split('').toSet().length;
    score += (distinct.clamp(0, 12)) / 12 * 0.1;
    if (_looksCommon(password)) score = score.clamp(0.0, 0.25);
    return score.clamp(0.0, 1.0);
  }
}
