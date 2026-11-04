import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../state/providers.dart';

/// Account actions: change password (by email link), sign out, and delete
/// the account. Kept apart from the per-cookbook settings above it.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? email = ref.watch(authRepositoryProvider).currentUser?.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Account', style: Theme.of(context).textTheme.titleLarge),
        if (email != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Signed in as $email'),
          ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_reset_outlined),
          title: const Text('Change password'),
          subtitle: const Text(
              'We email you a confirmation link; the password only changes '
              'after you open it.'),
          onTap:
              email == null ? null : () => _changePassword(context, ref, email),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () async {
            Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
            await ref.read(authRepositoryProvider).signOut();
          },
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.person_remove_outlined,
              color: Theme.of(context).colorScheme.error),
          title: Text('Delete account',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          subtitle: const Text(
              'Permanently removes your account and everything only you own.'),
          onTap: () => _confirmDeleteAccount(context, ref),
        ),
      ],
    );
  }

  static Future<void> _changePassword(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Change your password?'),
            content: Text(
                'We will send a confirmation link to $email. Your password '
                'stays the same until you open the link and choose a new one.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Email me the link'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;

    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check $email for the confirmation link.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Failure.from(error).message)),
        );
      }
    }
  }

  static Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Delete your account?'),
            content: const Text(
                'Your recipes, photos, pantry and plans are removed for good. '
                'Anyone who forked or saved one of your recipes keeps their '
                'own copy. This cannot be undone.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep my account'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete everything'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;

    try {
      await ref.read(storageRepositoryProvider).deleteAccount();
      if (context.mounted) {
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Failure.from(error).message)),
      );
    }
  }
}
