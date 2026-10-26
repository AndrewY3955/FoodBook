import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import '../data/repositories/shopping_repository.dart';
import 'library_controller.dart';
import 'providers.dart';

/// The shopping list is an AsyncNotifier rather than a FutureProvider
/// because ticking a box has to update the screen before the round trip
/// finishes. A FutureProvider exposes no writable state, so optimistic
/// updates are not expressible against one.
class ShoppingListController extends AsyncNotifier<List<ShoppingItem>> {
  @override
  Future<List<ShoppingItem>> build() async {
    final String? libraryId = ref.watch(activeLibraryIdProvider);
    if (libraryId == null) return const <ShoppingItem>[];
    return ref.watch(shoppingRepositoryProvider).list(libraryId);
  }

  Future<void> _reload() async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) {
      state = const AsyncValue<List<ShoppingItem>>.data(<ShoppingItem>[]);
      return;
    }
    state = await AsyncValue.guard<List<ShoppingItem>>(
      () => ref.read(shoppingRepositoryProvider).list(libraryId),
    );
  }

  /// Ticking a box is the most frequent interaction on this screen and
  /// often happens on one bar of signal in a supermarket. Apply locally,
  /// then reconcile — on success the reload is a no-op, on failure it
  /// snaps the checkbox back rather than leaving a lie on screen.
  Future<void> setChecked(String itemId, bool isChecked) async {
    final List<ShoppingItem>? current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue<List<ShoppingItem>>.data(
        current
            .map((ShoppingItem i) =>
                i.id == itemId ? i.copyWith(isChecked: isChecked) : i)
            .toList(growable: false),
      );
    }

    try {
      await ref.read(shoppingRepositoryProvider).setChecked(itemId, isChecked);
    } finally {
      await _reload();
    }
  }

  Future<void> addCustom({
    required String label,
    required GroceryCategory category,
    double quantity = 1,
    MeasureUnit unit = MeasureUnit.unit,
  }) async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return;
    await ref.read(shoppingRepositoryProvider).addCustom(
          libraryId: libraryId,
          label: label,
          category: category,
          quantity: quantity,
          unit: unit,
        );
    await _reload();
  }

  Future<void> setQuantity(String itemId, double quantity) async {
    await ref.read(shoppingRepositoryProvider).setQuantity(itemId, quantity);
    await _reload();
  }

  Future<void> remove(String itemId) async {
    await ref.read(shoppingRepositoryProvider).remove(itemId);
    await _reload();
  }

  Future<void> clearChecked() async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return;
    await ref.read(shoppingRepositoryProvider).clearChecked(libraryId);
    await _reload();
  }

  /// Returns how many rows were touched, for the confirmation snackbar.
  Future<int> addRecipe({required String recipeId, int? servings}) async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return 0;
    final int touched = await ref.read(shoppingRepositoryProvider).addRecipe(
          recipeId: recipeId,
          libraryId: libraryId,
          servings: servings,
        );
    await _reload();
    return touched;
  }

  Future<int> addPlannedRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return 0;
    final int touched =
        await ref.read(mealPlanRepositoryProvider).addRangeToShoppingList(
              libraryId: libraryId,
              from: from,
              to: to,
            );
    await _reload();
    return touched;
  }
}

final AsyncNotifierProvider<ShoppingListController, List<ShoppingItem>>
    shoppingListProvider =
    AsyncNotifierProvider<ShoppingListController, List<ShoppingItem>>(
        ShoppingListController.new);

final Provider<Map<GroceryCategory, List<ShoppingItem>>>
    groupedShoppingListProvider =
    Provider<Map<GroceryCategory, List<ShoppingItem>>>((Ref ref) {
  final List<ShoppingItem>? items = ref.watch(shoppingListProvider).valueOrNull;
  if (items == null) return const <GroceryCategory, List<ShoppingItem>>{};
  return ShoppingRepository.group(items);
});

final Provider<int> uncheckedCountProvider = Provider<int>((Ref ref) {
  final List<ShoppingItem>? items = ref.watch(shoppingListProvider).valueOrNull;
  if (items == null) return 0;
  return items.where((ShoppingItem i) => !i.isChecked).length;
});
