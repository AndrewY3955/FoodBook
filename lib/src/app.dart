import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/sign_in_screen.dart';

class CookistryBookApp extends ConsumerWidget {
  const CookistryBookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'CookistryBook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

/// Chooses between the signed-out and signed-in trees.
///
/// Watching the auth stream rather than checking currentSession once
/// means a token that expires, or a sign-out triggered on another
/// device, drops this user back to the sign-in screen instead of
/// leaving them on a screen whose every request now fails.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Object?> auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stack) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.wifi_off, size: 40),
                const SizedBox(height: 12),
                const Text('Could not reach the server.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(authStateProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (_) => ref.watch(isSignedInProvider)
          ? const HomeShell()
          : const SignInScreen(),
    );
  }
}
