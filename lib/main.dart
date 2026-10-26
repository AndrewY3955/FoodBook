import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/core/env.dart';
import 'src/core/security/secure_token_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail here rather than at the first query with an opaque network
  // error.
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      // Native builds keep the session in the platform keystore.
      //
      // Web does not get persistence at all. A browser has no keystore;
      // any "secure" storage there is obfuscated localStorage, and a
      // refresh token in localStorage is readable by any successful XSS.
      // Ending the session with the tab is the honest behaviour.
      localStorage: kIsWeb ? null : SecureTokenStorage(),
      autoRefreshToken: true,
      detectSessionInUri: !kIsWeb,
    ),
    postgrestOptions: const PostgrestClientOptions(schema: 'public'),
    realtimeClientOptions: const RealtimeClientOptions(
      // Realtime is not used. Leaving it unconfigured would still open a
      // socket per session; for 1,000 users that is 1,000 idle
      // connections bought for nothing.
      eventsPerSecond: 1,
    ),
  );

  runApp(const ProviderScope(child: CookistryBookApp()));
}
