import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/energy_model.dart';
import '../data/repositories/nutrition_repository.dart';
import 'providers.dart';

final Provider<NutritionRepository> nutritionRepositoryProvider =
    Provider<NutritionRepository>(
        (Ref ref) => NutritionRepository(ref.watch(supabaseClientProvider)));

final FutureProvider<NutritionGoals> nutritionGoalsProvider =
    FutureProvider<NutritionGoals>((Ref ref) {
  ref.watch(sessionProvider);
  return ref.watch(nutritionRepositoryProvider).goals();
});

final FutureProvider<BodyProfile?> bodyProfileProvider =
    FutureProvider<BodyProfile?>((Ref ref) {
  ref.watch(sessionProvider);
  return ref.watch(nutritionRepositoryProvider).bodyProfile();
});

/// Weigh-ins for the 90 days ending today. Invalidate after a change.
final FutureProvider<List<WeighIn>> weighInsProvider =
    FutureProvider<List<WeighIn>>((Ref ref) {
  ref.watch(sessionProvider);
  final DateTime n = DateTime.now();
  final DateTime today = DateTime(n.year, n.month, n.day);
  return ref
      .watch(nutritionRepositoryProvider)
      .weighIns(today.subtract(const Duration(days: 89)), today);
});

/// The day shown on the Today tab (date only).
final StateProvider<DateTime> selectedDayProvider =
    StateProvider<DateTime>((Ref ref) {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
});

/// Diary entries for the 90 days ending today, loaded once and shared by
/// Today and Trends. Invalidate after adding or deleting an entry.
final FutureProvider<List<FoodLogEntry>> foodLogProvider =
    FutureProvider<List<FoodLogEntry>>((Ref ref) {
  ref.watch(sessionProvider);
  final DateTime n = DateTime.now();
  final DateTime today = DateTime(n.year, n.month, n.day);
  return ref
      .watch(nutritionRepositoryProvider)
      .entries(today.subtract(const Duration(days: 89)), today);
});
