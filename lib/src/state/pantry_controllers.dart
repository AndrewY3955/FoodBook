import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import 'library_controller.dart';
import 'providers.dart';

final FutureProvider<List<PantryItem>> pantryListProvider =
    FutureProvider<List<PantryItem>>((Ref ref) async {
  final String? libraryId = ref.watch(activeLibraryIdProvider);
  if (libraryId == null) return const <PantryItem>[];
  return ref.watch(pantryRepositoryProvider).list(libraryId);
});

/// Pantry grouped under the same headers the shopping list uses, so the
/// two screens read the same way.
final Provider<Map<GroceryCategory, List<PantryItem>>>
    pantryByCategoryProvider =
    Provider<Map<GroceryCategory, List<PantryItem>>>((Ref ref) {
  return ref.watch(pantryListProvider).maybeWhen(
        data: (List<PantryItem> items) {
          final Map<GroceryCategory, List<PantryItem>> grouped =
              <GroceryCategory, List<PantryItem>>{};
          for (final GroceryCategory c in GroceryCategory.values) {
            final List<PantryItem> inCategory = items
                .where((PantryItem i) => i.category == c)
                .toList()
              ..sort((PantryItem a, PantryItem b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            if (inCategory.isNotEmpty) grouped[c] = inCategory;
          }
          return grouped;
        },
        orElse: () => const <GroceryCategory, List<PantryItem>>{},
      );
});

/// The floor for "what can I cook". 0 shows everything; 100 shows only
/// what is fully cookable right now.
class MatchThresholdController extends Notifier<int> {
  @override
  int build() => 60;

  void set(int value) => state = value.clamp(0, 100);
}

final NotifierProvider<MatchThresholdController, int> matchThresholdProvider =
    NotifierProvider<MatchThresholdController, int>(
        MatchThresholdController.new);

/// The matcher result. Depends on the pantry list so that adding a jar
/// of something re-ranks the suggestions without a manual refresh.
final FutureProvider<List<PantryMatch>> pantryMatchProvider =
    FutureProvider<List<PantryMatch>>((Ref ref) async {
  final String? libraryId = ref.watch(activeLibraryIdProvider);
  if (libraryId == null) return const <PantryMatch>[];

  ref.watch(pantryListProvider);

  final int threshold = ref.watch(matchThresholdProvider);
  return ref.watch(pantryRepositoryProvider).match(
        libraryId: libraryId,
        minimumPercent: threshold,
      );
});

class PantryController extends Notifier<void> {
  @override
  void build() {}

  Future<void> upsert({
    required String ingredientId,
    required double quantity,
    required MeasureUnit unit,
  }) async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return;
    await ref.read(pantryRepositoryProvider).upsert(
          libraryId: libraryId,
          ingredientId: ingredientId,
          quantity: quantity,
          unit: unit,
        );
    ref.invalidate(pantryListProvider);
  }

  Future<void> remove(String pantryItemId) async {
    await ref.read(pantryRepositoryProvider).remove(pantryItemId);
    ref.invalidate(pantryListProvider);
  }
}

final NotifierProvider<PantryController, void> pantryControllerProvider =
    NotifierProvider<PantryController, void>(PantryController.new);

/// Ingredient autocomplete, debounced by the caller.
final FutureProviderFamily<List<Ingredient>, String> ingredientSearchProvider =
    FutureProvider.family<List<Ingredient>, String>((Ref ref, String q) async {
  final String? libraryId = ref.watch(activeLibraryIdProvider);
  if (libraryId == null) return const <Ingredient>[];
  return ref
      .watch(ingredientRepositoryProvider)
      .search(libraryId: libraryId, query: q);
});
