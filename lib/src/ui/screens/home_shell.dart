import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';
import '../../state/shopping_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';
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
    'Planner & Pantry',
    'Shopping List',
  ];

  @override
  Widget build(BuildContext context) {
    final int unchecked = ref.watch(uncheckedCountProvider);
    final AsyncValue<List<Library>> libraries =
        ref.watch(myLibrariesProvider);

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
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ],
          destinations: <AdaptiveDestination>[
            const AdaptiveDestination(
              label: 'Recipes',
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book,
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
                  'You can invite the people you cook with later.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Cookbook name',
                    hintText: 'The Rivera Family Cookbook',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await ref
                                .read(activeLibraryProvider.notifier)
                                .create(_name.text);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Create'),
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
