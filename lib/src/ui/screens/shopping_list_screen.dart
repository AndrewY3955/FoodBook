import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quantity_format.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../state/shopping_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';

/// The categorised grocery sorter.
///
/// Headers come from the enum order in the database, not from anything
/// learned about a particular shop. The brief rules out store layout
/// mapping, and the fixed order is the point: it is the same every
/// week, so it becomes muscle memory.
class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ShoppingItem>> items =
        ref.watch(shoppingListProvider);
    final Map<GroceryCategory, List<ShoppingItem>> grouped =
        ref.watch(groupedShoppingListProvider);

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        return Column(
          children: <Widget>[
            _Toolbar(),
            Expanded(
              child: items.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace s) => Center(
                  child: FilledButton(
                    onPressed: () => ref.invalidate(shoppingListProvider),
                    child: const Text('Retry'),
                  ),
                ),
                data: (List<ShoppingItem> list) {
                  if (list.isEmpty) return const _Empty();

                  final List<GroceryCategory> categories =
                      grouped.keys.toList(growable: false);

                  // Wide screens get the categories as columns, so a
                  // full week's list is visible without scrolling.
                  if (scope.isDesktop && categories.length > 2) {
                    return ContentWidth(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          children: <Widget>[
                            for (final GroceryCategory c in categories)
                              SizedBox(
                                width: 330,
                                child: _CategoryBlock(
                                  category: c,
                                  items: grouped[c]!,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ContentWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      children: <Widget>[
                        for (final GroceryCategory c in categories)
                          _CategoryBlock(category: c, items: grouped[c]!),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int remaining = ref.watch(uncheckedCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: ContentWidth(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                remaining == 0
                    ? 'Nothing left to get'
                    : '$remaining still to get',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showAdd(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
            PopupMenuButton<String>(
              onSelected: (String value) async {
                if (value == 'clear') {
                  await ref.read(shoppingListProvider.notifier).clearChecked();
                }
                if (value == 'week') {
                  final DateTime now = DateTime.now();
                  final DateTime monday =
                      now.subtract(Duration(days: now.weekday - 1));
                  final int touched = await ref
                      .read(shoppingListProvider.notifier)
                      .addPlannedRange(
                        from: monday,
                        to: monday.add(const Duration(days: 6)),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          touched == 0
                              ? 'Your pantry already covers this week.'
                              : '$touched item${touched == 1 ? '' : 's'} added from the plan.',
                        ),
                      ),
                    );
                  }
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'week',
                  child: ListTile(
                    leading: Icon(Icons.calendar_month_outlined),
                    title: Text("Add this week's plan"),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.cleaning_services_outlined),
                    title: Text('Clear ticked items'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdd(BuildContext context, WidgetRef ref) async {
    final TextEditingController label = TextEditingController();
    GroceryCategory category = GroceryCategory.other;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: label,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'What do you need?'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GroceryCategory>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Aisle'),
                items: GroceryCategory.values
                    .map((GroceryCategory c) =>
                        DropdownMenuItem<GroceryCategory>(
                          value: c,
                          child: Text(c.label),
                        ))
                    .toList(growable: false),
                onChanged: (GroceryCategory? c) {
                  if (c != null) setSheetState(() => category = c);
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await ref.read(shoppingListProvider.notifier).addCustom(
                        label: label.text,
                        category: category,
                      );
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Add to list'),
              ),
            ],
          ),
        ),
      ),
    );

    label.dispose();
  }
}

class _CategoryBlock extends ConsumerWidget {
  const _CategoryBlock({required this.category, required this.items});

  final GroceryCategory category;
  final List<ShoppingItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int remaining = items.where((ShoppingItem i) => !i.isChecked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
          child: Row(
            children: <Widget>[
              Text(
                category.label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$remaining of ${items.length}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        for (final ShoppingItem item in items)
          Dismissible(
            key: ValueKey<String>(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: theme.colorScheme.errorContainer,
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) =>
                ref.read(shoppingListProvider.notifier).remove(item.id),
            child: CheckboxListTile(
              value: item.isChecked,
              // 56 px row: comfortable to hit one-handed while pushing
              // a trolley.
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (bool? v) => ref
                  .read(shoppingListProvider.notifier)
                  .setChecked(item.id, v ?? false),
              title: Text(
                item.label,
                style: TextStyle(
                  decoration:
                      item.isChecked ? TextDecoration.lineThrough : null,
                  color: item.isChecked
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
              subtitle: item.unit == MeasureUnit.unit && item.quantity == 1
                  ? null
                  : Text(QuantityFormat.withUnit(item.quantity, item.unit)),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.shopping_basket_outlined, size: 44),
              const SizedBox(height: 12),
              Text(
                'The list is empty',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Add something by hand, or send a recipe here from its page.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
