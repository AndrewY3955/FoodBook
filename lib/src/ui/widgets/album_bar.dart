import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../data/models/models.dart';
import '../../data/repositories/album_repository.dart';
import '../../state/album_controllers.dart';
import '../../state/library_controller.dart';
import '../../state/recipe_controllers.dart';

/// Albums are categories inside the recipe box: a scrolling row of
/// chips (All plus each album) and an Albums button for the controls.
class AlbumBar extends ConsumerWidget {
  const AlbumBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RecipeAlbum> albums =
        ref.watch(albumsProvider).valueOrNull ?? const <RecipeAlbum>[];
    final String? selected = ref.watch(recipeFilterProvider).albumId;
    final RecipeFilterController filter =
        ref.read(recipeFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: selected == null,
                      onSelected: (_) => filter.setAlbum(null),
                    ),
                  ),
                  for (final RecipeAlbum a in albums)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(a.name),
                        selected: selected == a.id,
                        onSelected: (_) => filter.setAlbum(a.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const _AlbumManager(),
            ),
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Albums'),
          ),
        ],
      ),
    );
  }
}

class _AlbumManager extends ConsumerWidget {
  const _AlbumManager();

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String initial = '',
    required String action,
  }) {
    final TextEditingController c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Album name'),
          onSubmitted: (String v) => Navigator.pop(context, v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() job,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await job();
      ref.invalidate(albumsProvider);
      ref.invalidate(recipeListProvider);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(Failure.from(error).message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RecipeAlbum> albums =
        ref.watch(albumsProvider).valueOrNull ?? const <RecipeAlbum>[];
    final String? libraryId = ref.watch(activeLibraryIdProvider);
    final AlbumRepository repo = ref.read(albumRepositoryProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Albums',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final RecipeAlbum a in albums)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(a.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Rename ${a.name}',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final String? name = await _askName(
                                context,
                                title: 'Rename album',
                                initial: a.name,
                                action: 'Save',
                              );
                              if (name == null || !context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => repo.rename(a.id, name),
                              );
                            },
                          ),
                          if (albums.length > 1)
                            IconButton(
                              tooltip: 'Delete ${a.name}',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final bool? ok = await showDialog<bool>(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      AlertDialog(
                                    title: Text('Delete "${a.name}"?'),
                                    content: const Text(
                                      'Its recipes are not deleted. They move '
                                      'to another album.',
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Keep it'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Delete album'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true || !context.mounted) return;
                                ref
                                    .read(recipeFilterProvider.notifier)
                                    .setAlbum(null);
                                await _run(
                                  context,
                                  ref,
                                  () => repo.delete(a.id),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: libraryId == null
                    ? null
                    : () async {
                        final String? name = await _askName(
                          context,
                          title: 'New album',
                          action: 'Create',
                        );
                        if (name == null || !context.mounted) return;
                        await _run(
                          context,
                          ref,
                          () => repo.create(libraryId, name),
                        );
                      },
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('New album'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
