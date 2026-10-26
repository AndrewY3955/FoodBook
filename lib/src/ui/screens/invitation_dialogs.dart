import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/library_repository.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';

/// Asks an admin for the invitation details, creates it, and shows the
/// one-time code.
Future<void> showCreateInvitationDialog(
  BuildContext context,
  WidgetRef ref,
  Library library,
) async {
  final TextEditingController email = TextEditingController();
  MemberRole role = MemberRole.member;
  String? error;
  bool busy = false;
  InvitationToken? created;

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        if (created != null) {
          return AlertDialog(
            title: const Text('Invitation code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(
                  created!.token,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Single use. Expires '
                  '${created!.expiresAt.toLocal().toString().split('.').first}. '
                  'This code is shown only once, so copy it now and share it '
                  'privately.',
                ),
              ],
            ),
            actions: <Widget>[
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: created!.token));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: const Text('Invite someone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Their email (optional)',
                  helperText: 'If set, only that account can use the code.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemberRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const <DropdownMenuItem<MemberRole>>[
                  DropdownMenuItem<MemberRole>(
                    value: MemberRole.member,
                    child: Text('Member'),
                  ),
                  DropdownMenuItem<MemberRole>(
                    value: MemberRole.admin,
                    child: Text('Admin'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (MemberRole? value) =>
                        setState(() => role = value ?? MemberRole.member),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final InvitationToken token = await ref
                            .read(libraryRepositoryProvider)
                            .createInvitation(
                              library.id,
                              role: role,
                              email: email.text,
                            );
                        setState(() => created = token);
                      } catch (e) {
                        setState(() {
                          error = Failure.from(e).message;
                          busy = false;
                        });
                      }
                    },
              child: Text(busy ? 'Creating…' : 'Create code'),
            ),
          ],
        );
      },
    ),
  );
  email.dispose();
}

/// Prompts for an invitation code and joins the library it belongs to.
Future<void> showJoinWithCodeDialog(BuildContext context, WidgetRef ref) async {
  final TextEditingController code = TextEditingController();
  String? error;
  bool busy = false;

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: const Text('Join with a code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: code,
              enabled: !busy,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Invitation code'),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await ref
                          .read(activeLibraryProvider.notifier)
                          .joinWithInvitation(code.text);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e) {
                      setState(() {
                        error = Failure.from(e).message;
                        busy = false;
                      });
                    }
                  },
            child: Text(busy ? 'Joining…' : 'Join'),
          ),
        ],
      ),
    ),
  );
  code.dispose();
}
