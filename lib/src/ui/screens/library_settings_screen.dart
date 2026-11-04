import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../data/models/models.dart';
import '../../data/models/enums.dart';
import '../../state/library_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import 'account_section.dart';
import 'invitation_dialogs.dart';

class LibrarySettingsScreen extends ConsumerWidget {
  const LibrarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Library? library = ref.watch(activeLibraryRecordProvider);

    if (library == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library settings')),
          body: const ContentWidth(
            maxWidth: 720,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('No active library is selected.'),
                  SizedBox(height: 24),
                  AccountSection(),
                ],
              ),
            ),
          ),
        );
    }

    final AsyncValue<List<Profile>> members =
        ref.watch(libraryMembersProvider(library.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Library settings')),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(library.name,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text('Your role: ${library.role.label}'),
                    if (library.role.canManageMembers) ...<Widget>[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => _rename(context, ref, library),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Rename library'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => showCreateInvitationDialog(
                                context, ref, library),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Invite someone'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('People in this library',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            members.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object error, StackTrace stack) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      'Could not load members: ${Failure.from(error).message}'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(libraryMembersProvider(library.id)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
              data: (List<Profile> people) => people.isEmpty
                  ? const ListTile(title: Text('No active members found.'))
                  : Column(
                      children: people
                          .map((Profile person) => ListTile(
                                leading: CircleAvatar(
                                  child: Text(_initials(person.displayName)),
                                ),
                                title: Text(person.displayName),
                              ))
                          .toList(growable: false),
                    ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create another cookbook'),
              onTap: () => _create(context, ref),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined),
              title: const Text('Join another library with a code'),
              onTap: () => showJoinWithCodeDialog(context, ref),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.exit_to_app),
              title: const Text('Leave this library'),
              subtitle: const Text(
                'You will lose access to its recipes, pantry, plan and list. '
                'If you are the only member, the cookbook is deleted too.',
              ),
              onTap: () => _leave(context, ref, library),
            ),
            if (library.role == MemberRole.owner)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Delete this cookbook',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                subtitle: const Text(
                    'Removes it for every member. This cannot be undone.'),
                onTap: () => _delete(context, ref, library),
              ),
            const SizedBox(height: 16),
            const Divider(),
            const AccountSection(),
          ],
        ),
      ),
    );
  }

  static Future<void> _create(BuildContext context, WidgetRef ref) async {
    final TextEditingController name = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('New cookbook'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Cookbook name'),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(name.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    name.dispose();
    if (value == null || value.isEmpty || !context.mounted) return;

    try {
      await ref.read(activeLibraryProvider.notifier).create(value);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$value".')),
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

  static Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Library library,
  ) async {
    final TextEditingController typed = TextEditingController();
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                AlertDialog(
              title: const Text('Delete this cookbook?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '"${library.name}" and all of its recipes, photos, pantry, '
                    'plans and shopping list will be deleted for every member. '
                    'This is permanent and cannot be undone.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: typed,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Type the cookbook name to confirm',
                      helperText: library.name,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Keep it'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: typed.text.trim() == library.name
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: const Text('Delete forever'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    typed.dispose();
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(activeLibraryProvider.notifier).deleteLibrary(library.id);
      if (context.mounted) {
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${library.name}".')),
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

  static String _initials(String name) {
    final List<String> words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((String word) => word[0].toUpperCase()).join();
  }

  static Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Library library,
  ) async {
    final TextEditingController name =
        TextEditingController(text: library.name);
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final String? updatedName = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Rename library'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Library name'),
            validator: (String? value) =>
                value == null || value.trim().isEmpty ? 'Enter a name' : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(name.text.trim());
              }
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(name.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    if (updatedName == null || !context.mounted) return;

    try {
      await ref
          .read(activeLibraryProvider.notifier)
          .rename(library.id, updatedName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library renamed.')),
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

  static Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    Library library,
  ) async {
    final bool alone = await ref
        .read(activeLibraryProvider.notifier)
        .isOnlyMember(library.id)
        .catchError((Object _) => false);
    if (!context.mounted) return;
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(alone ? 'Delete this cookbook?' : 'Leave this library?'),
            content: Text(
              alone
                  ? 'You are the only member, so leaving deletes "${library.name}" '
                      'and everything in it permanently. This cannot be undone.'
                  : 'You will no longer see "${library.name}". '
                      'Its content will remain available to its other members.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(alone ? 'Delete cookbook' : 'Leave library'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(activeLibraryProvider.notifier).leave(library.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Failure.from(error).message)),
        );
      }
    }
  }
}
