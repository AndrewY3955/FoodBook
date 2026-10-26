import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands a countdown to the operating system's own clock app.
///
/// Why not an in-app timer: an in-app countdown dies when the OS
/// suspends the app, needs a notification channel and a background
/// execution exemption on both platforms to survive, and competes with
/// a timer the user already trusts. Handing off costs one intent and
/// keeps ringing when the app is closed.
///
/// The trade-off is honest: handoff support is uneven, so every call
/// site must handle `false` and fall back to showing the duration as
/// text for the user to set themselves.
class NativeTimer {
  const NativeTimer._();

  /// Returns true only if a handler actually accepted the request.
  static Future<bool> start({
    required Duration duration,
    required String label,
  }) async {
    final int seconds = duration.inSeconds;
    if (seconds < 1 || seconds > 86400) return false;

    for (final Uri candidate in _candidates(seconds, label)) {
      try {
        if (await canLaunchUrl(candidate)) {
          final bool launched = await launchUrl(
            candidate,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return true;
        }
      } catch (_) {
        // Try the next scheme rather than failing the whole attempt.
        continue;
      }
    }
    return false;
  }

  static List<Uri> _candidates(int seconds, String label) {
    final String encoded = Uri.encodeComponent(label);

    if (defaultTargetPlatform == TargetPlatform.android) {
      // AlarmClock.ACTION_SET_TIMER, expressed as an intent: URI. The
      // stock Clock app and most OEM replacements register for it.
      return <Uri>[
        Uri.parse(
          'intent://timer/#Intent;'
          'action=android.intent.action.SET_TIMER;'
          'i.android.intent.extra.alarm.LENGTH=$seconds;'
          'S.android.intent.extra.alarm.MESSAGE=$encoded;'
          'B.android.intent.extra.alarm.SKIP_UI=false;'
          'end',
        ),
      ];
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS has no public timer URL scheme. clock-timer: opens the
      // Clock app's timer tab on current versions but does not preset a
      // duration, so the caller still shows the number to dial in.
      return <Uri>[Uri.parse('clock-timer://')];
    }

    // Desktop and web: nothing to hand off to.
    return const <Uri>[];
  }

  /// Whether a handoff is even plausible on this platform, so the UI can
  /// label the button honestly instead of offering something that will
  /// silently do nothing.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Opens an external link — the step-by-step video. Always external:
  /// an in-app webview would run third-party script inside the app's
  /// process and undo the point of not embedding video.
  static Future<bool> openExternal(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
