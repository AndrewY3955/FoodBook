import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/import_repository.dart';
import '../data/repositories/ingredient_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/meal_plan_repository.dart';
import '../data/repositories/pantry_repository.dart';
import '../data/repositories/recipe_repository.dart';
import '../data/repositories/shopping_repository.dart';
import '../data/repositories/storage_repository.dart';

/// Dependency graph root.
///
/// Every repository is reachable only through a provider, so a widget
/// test can override any one of them without the app ever constructing
/// a real SupabaseClient.

final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((Ref ref) => Supabase.instance.client);

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
        (Ref ref) => AuthRepository(ref.watch(supabaseClientProvider)));

final Provider<LibraryRepository> libraryRepositoryProvider =
    Provider<LibraryRepository>(
        (Ref ref) => LibraryRepository(ref.watch(supabaseClientProvider)));

final Provider<RecipeRepository> recipeRepositoryProvider =
    Provider<RecipeRepository>(
        (Ref ref) => RecipeRepository(ref.watch(supabaseClientProvider)));

final Provider<PantryRepository> pantryRepositoryProvider =
    Provider<PantryRepository>(
        (Ref ref) => PantryRepository(ref.watch(supabaseClientProvider)));

final Provider<ShoppingRepository> shoppingRepositoryProvider =
    Provider<ShoppingRepository>(
        (Ref ref) => ShoppingRepository(ref.watch(supabaseClientProvider)));

final Provider<MealPlanRepository> mealPlanRepositoryProvider =
    Provider<MealPlanRepository>(
        (Ref ref) => MealPlanRepository(ref.watch(supabaseClientProvider)));

final Provider<IngredientRepository> ingredientRepositoryProvider =
    Provider<IngredientRepository>(
        (Ref ref) => IngredientRepository(ref.watch(supabaseClientProvider)));

final Provider<StorageRepository> storageRepositoryProvider =
    Provider<StorageRepository>(
        (Ref ref) => StorageRepository(ref.watch(supabaseClientProvider)));

final Provider<ImportRepository> importRepositoryProvider =
    Provider<ImportRepository>(
        (Ref ref) => ImportRepository(ref.watch(supabaseClientProvider)));

/// Auth state as a stream. Everything downstream keys off this, so a
/// token expiry or a sign-out on another device tears the session down
/// everywhere rather than leaving a stale screen holding dead data.
final StreamProvider<AuthState> authStateProvider = StreamProvider<AuthState>(
    (Ref ref) => ref.watch(authRepositoryProvider).onAuthStateChange);

final Provider<Session?> sessionProvider = Provider<Session?>((Ref ref) {
  final AsyncValue<AuthState> state = ref.watch(authStateProvider);
  return state.maybeWhen(
    data: (AuthState s) => s.session,
    orElse: () => ref.watch(authRepositoryProvider).currentSession,
  );
});

final Provider<bool> isSignedInProvider =
    Provider<bool>((Ref ref) => ref.watch(sessionProvider) != null);

final Provider<String?> currentUserIdProvider =
    Provider<String?>((Ref ref) => ref.watch(sessionProvider)?.user.id);
