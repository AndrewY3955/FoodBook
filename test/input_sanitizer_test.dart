// Run: flutter test
//
// NOTE FOR REVIEWERS: these tests have never been executed. They were
// written in an environment with no Dart toolchain. Treat a green run
// as the first evidence they work, not a confirmation.
//
// The URL corpus below is the same corpus that was run against the
// server-side CHECK function public.is_safe_http_url, which did pass
// 26/26. If a case here disagrees with the server, the server is the
// authority and this file is wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:cookistrybook/src/core/security/input_sanitizer.dart';
import 'package:cookistrybook/src/core/security/password_policy.dart';

void main() {
  group('safeUrl', () {
    const List<String> accepted = <String>[
      'https://www.youtube.com/watch?v=abc123',
      'https://youtu.be/abc123',
      'https://www.instagram.com/reel/C0000000000/',
      'https://vimeo.com/123456789',
      'https://example.test',
      'https://example.test:8443/path/to/x',
    ];

    const List<String> rejected = <String>[
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      '  javascript:alert(1)  ',
      'data:text/html;base64,PHNjcmlwdD4=',
      'vbscript:msgbox(1)',
      'file:///etc/passwd',
      'http://example.test/v',
      '//evil.test/v',
      'https://user:pass@evil.test/v',
      'https://example.test/"><script>alert(1)</script>',
      "https://example.test/'onload='alert(1)",
      'https://example.test/ onerror=alert(1)',
      'https://example.test/a\\b',
      'https://example.test/<img>',
      'https://',
      'https:///nohost',
      '',
      'not a url at all',
      'https://example.test/`backtick`',
    ];

    for (final String url in accepted) {
      test('accepts $url', () {
        expect(InputSanitizer.safeUrl(url), isNotNull);
      });
    }

    for (final String url in rejected) {
      test('rejects $url', () {
        expect(InputSanitizer.safeUrl(url), isNull);
      });
    }

    test('enforces the host allowlist when one is given', () {
      expect(
        InputSanitizer.safeUrl(
          'https://evil.test/v',
          allowedHosts: <String>{'youtube.com'},
        ),
        isNull,
      );
      expect(
        InputSanitizer.safeUrl(
          'https://youtube.com/v',
          allowedHosts: <String>{'youtube.com'},
        ),
        isNotNull,
      );
    });

    test('rejects anything over 2048 characters', () {
      expect(
        InputSanitizer.safeUrl('https://a.test/${'x' * 2100}'),
        isNull,
      );
    });
  });

  group('text hygiene', () {
    test('strips control characters', () {
      expect(InputSanitizer.singleLine('a\u0000b\u0007c'), 'abc');
    });

    test('strips bidi override characters', () {
      expect(
        InputSanitizer.singleLine('safe\u202Etxt.exe').contains('\u202E'),
        isFalse,
      );
    });

    test('collapses a newline into a space on single-line input', () {
      expect(InputSanitizer.singleLine('a\nb'), 'a b');
    });

    test('keeps paragraph breaks on multi-line input', () {
      expect(InputSanitizer.multiLine('a\n\nb'), 'a\n\nb');
    });

    test('caps at the requested length', () {
      expect(InputSanitizer.singleLine('x' * 500, maxLength: 20).length, 20);
    });
  });

  group('quantity', () {
    test('parses decimals with either separator', () {
      expect(InputSanitizer.quantity('2.5'), 2.5);
      expect(InputSanitizer.quantity('2,5'), 2.5);
    });

    test('parses simple fractions', () {
      expect(InputSanitizer.quantity('1/2'), 0.5);
    });

    test('parses mixed numbers', () {
      expect(InputSanitizer.quantity('1 1/2'), 1.5);
    });

    test('rejects zero, negatives and nonsense', () {
      expect(InputSanitizer.quantity('0'), isNull);
      expect(InputSanitizer.quantity('-3'), isNull);
      expect(InputSanitizer.quantity('1/0'), isNull);
      expect(InputSanitizer.quantity('lots'), isNull);
    });

    test('rejects values beyond the numeric(10,3) column bound', () {
      expect(InputSanitizer.quantity('999999'), isNull);
    });
  });

  group('password policy', () {
    test('accepts a compliant password', () {
      expect(PasswordPolicy.isValid('Shakshuka!2026x'), isTrue);
    });

    test('rejects one that is too short', () {
      expect(PasswordPolicy.isValid('Sh0rt!aa'), isFalse);
    });

    test('rejects past the bcrypt truncation point', () {
      expect(PasswordPolicy.isValid('Aa1!${'x' * 80}'), isFalse);
    });

    test('rejects common seeds even when otherwise compliant', () {
      expect(PasswordPolicy.isValid('Password123!xy'), isFalse);
    });

    test('rejects whitespace', () {
      expect(PasswordPolicy.isValid('Abcdef 1234!x'), isFalse);
    });
  });
}
