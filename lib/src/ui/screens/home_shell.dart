import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../data/models/models.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';
import '../../state/shopping_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';
import 'discover_screen.dart';
import 'library_settings_screen.dart';
import 'invitation_dialogs.dart';
import 'pantry_planner_screen.dart';
import 'recipe_box_screen.dart';
import 'shopping_list_screen.dart';

/// The three-section shell.
///
/// Phone gets a bottom bar, tablet a rail, desktop a sidebar — one
/// destination list, three presentations, per the brief.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const List<String> _titles = <String>[
    'Recipe Box',
    'Discover',
    'Planner & Pantry',
    'Shopping List',
  ];

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'Your recipes, photos, pantry and plans are removed for good. '
            'Anyone who forked or saved one of your recipes keeps their own copy.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(storageRepositoryProvider).deleteAccount();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final int unchecked = ref.watch(uncheckedCountProvider);
    final AsyncValue<List<Library>> libraries = ref.watch(myLibrariesProvider);

    return libraries.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, StackTrace s) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Could not load your libraries.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(myLibrariesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (List<Library> list) {
        if (list.isEmpty) return const _NoLibrary();

        return AdaptiveScaffold(
          title: _titles[_index],
          selectedIndex: _index,
          onDestinationSelected: (int i) => setState(() => _index = i),
          leadingSidebar: const LibrarySwitcher(),
          actions: <Widget>[
            IconButton(
              tooltip: 'Library settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LibrarySettingsScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
            IconButton(
              tooltip: 'Delete account',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: () => _confirmDeleteAccount(context),
            ),
          ],
          destinations: <AdaptiveDestination>[
            const AdaptiveDestination(
              label: 'Recipes',
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book,
            ),
            const AdaptiveDestination(
              label: 'Discover',
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
            ),
            const AdaptiveDestination(
              label: 'Plan & Pantry',
              icon: Icons.calendar_month_outlined,
              selectedIcon: Icons.calendar_month,
            ),
            AdaptiveDestination(
              label: 'Shopping',
              icon: Icons.shopping_basket_outlined,
              selectedIcon: Icons.shopping_basket,
              badgeCount: unchecked,
            ),
          ],
          body: IndexedStack(
            index: _index,
            children: const <Widget>[
              RecipeBoxScreen(),
              DiscoverScreen(),
              PantryPlannerScreen(),
              ShoppingListScreen(),
            ],
          ),
        );
      },
    );
  }
}

/// Shown when a user somehow belongs to no library — for instance after
/// leaving their last one.
class _NoLibrary extends ConsumerStatefulWidget {
  const _NoLibrary();

  @override
  ConsumerState<_NoLibrary> createState() => _NoLibraryState();
}

class _NoLibraryState extends ConsumerState<_NoLibrary> {
  final TextEditingController _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.menu_book_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Start a library',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'A library holds your recipes, pantry and plan. '
                  'Create one, or join one you were invited to.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Cookbook name',
                    hintText: 'The Rivera Family Cookbook',
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          try {
                            await ref
                                .read(activeLibraryProvider.notifier)
                                .create(_name.text);
                          } catch (error) {
                            if (mounted) {
                              setState(
                                () => _error = Failure.from(error).message,
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Creating…' : 'Create'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed:
                      _busy ? null : () => showJoinWithCodeDialog(context, ref),
                  child: const Text('I have an invitation code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Library picker. Appears in the rail and sidebar; on phone it is
/// reachable from the recipe box app bar.
class LibrarySwitcher extends ConsumerWidget {
  const LibrarySwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Library> libraries =
        ref.watch(myLibrariesProvider).valueOrNull ?? const <Library>[];
    final Library? active = ref.watch(activeLibraryRecordProvider);
    final LayoutScope? scope = LayoutScope.maybeOf(context);
    final bool compact = scope?.isTablet ?? false;

    if (libraries.isEmpty) return const SizedBox.shrink();

    if (compact) {
      return PopupMenuButton<String>(
        tooltip: active?.name ?? 'Cookbook',
        icon: const Icon(Icons.menu_book_outlined),
        onSelected: (String id) =>
            ref.read(activeLibraryProvider.notifier).select(id),
        itemBuilder: (BuildContext context) => libraries
            .map((Library k) => PopupMenuItem<String>(
                  value: k.id,
                  child: Text(k.name),
                ))
            .toList(growable: false),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: active?.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Cookbook',
        prefixIcon: Icon(Icons.menu_book_outlined),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: libraries
          .map((Library k) => DropdownMenuItem<String>(
                value: k.id,
                child: Text(k.name, overflow: TextOverflow.ellipsis),
              ))
          .toList(growable: false),
      onChanged: (String? id) {
        if (id != null) ref.read(activeLibraryProvider.notifier).select(id);
      },
    );
  }
}
