import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import 'library_controller.dart';
import 'providers.dart';

/// Date helpers kept here rather than in the widget so the week the
/// planner shows and the week the shopping list aggregates are computed
/// by the same code.
class PlannerWeek {
  const PlannerWeek(this.start);

  /// Monday of the week containing [start].
  factory PlannerWeek.containing(DateTime date) {
    final DateTime d = DateTime(date.year, date.month, date.day);
    return PlannerWeek(d.subtract(Duration(days: d.weekday - 1)));
  }

  final DateTime start;

  DateTime get end => start.add(const Duration(days: 6));

  List<DateTime> get days => List<DateTime>.generate(
        7,
        (int i) => start.add(Duration(days: i)),
        growable: false,
      );

  PlannerWeek get next => PlannerWeek(start.add(const Duration(days: 7)));

  PlannerWeek get previous =>
      PlannerWeek(start.subtract(const Duration(days: 7)));

  bool contains(DateTime date) =>
      !date.isBefore(start) && !date.isAfter(end.add(const Duration(days: 1)));

  @override
  bool operator ==(Object other) =>
      other is PlannerWeek && other.start == start;

  @override
  int get hashCode => start.hashCode;
}

class PlannerWeekController extends Notifier<PlannerWeek> {
  @override
  PlannerWeek build() => PlannerWeek.containing(DateTime.now());

  void next() => state = state.next;
  void previous() => state = state.previous;
  void thisWeek() => state = PlannerWeek.containing(DateTime.now());
  void jumpTo(DateTime date) => state = PlannerWeek.containing(date);
}

final NotifierProvider<PlannerWeekController, PlannerWeek> plannerWeekProvider =
    NotifierProvider<PlannerWeekController, PlannerWeek>(
        PlannerWeekController.new);

class MealPlanController extends AsyncNotifier<List<MealPlanEntry>> {
  @override
  Future<List<MealPlanEntry>> build() async {
    final String? libraryId = ref.watch(activeLibraryIdProvider);
    if (libraryId == null) return const <MealPlanEntry>[];
    final PlannerWeek week = ref.watch(plannerWeekProvider);
    return ref.watch(mealPlanRepositoryProvider).range(
          libraryId: libraryId,
          from: week.start,
          to: week.end,
        );
  }

  Future<void> _reload() async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return;
    final PlannerWeek week = ref.read(plannerWeekProvider);
    state = await AsyncValue.guard<List<MealPlanEntry>>(
      () => ref.read(mealPlanRepositoryProvider).range(
            libraryId: libraryId,
            from: week.start,
            to: week.end,
          ),
    );
  }

  Future<void> add({
    required String recipeId,
    required DateTime date,
    required MealType mealType,
    int? servingsOverride,
    String? note,
  }) async {
    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) return;
    await ref.read(mealPlanRepositoryProvider).add(
          libraryId: libraryId,
          recipeId: recipeId,
          date: date,
          mealType: mealType,
          servingsOverride: servingsOverride,
          note: note,
        );
    await _reload();
  }

  Future<void> move({
    required String entryId,
    required DateTime date,
    required MealType mealType,
  }) async {
    await ref.read(mealPlanRepositoryProvider).move(
          entryId: entryId,
          date: date,
          mealType: mealType,
        );
    await _reload();
  }

  Future<void> remove(String entryId) async {
    await ref.read(mealPlanRepositoryProvider).remove(entryId);
    await _reload();
  }
}

final AsyncNotifierProvider<MealPlanController, List<MealPlanEntry>>
    mealPlanProvider =
    AsyncNotifierProvider<MealPlanController, List<MealPlanEntry>>(
        MealPlanController.new);

/// Entries indexed by day then meal, which is the shape the calendar
/// grid iterates. Computing it once here avoids an O(days x meals x
/// entries) scan inside the build method.
final Provider<Map<String, Map<MealType, List<MealPlanEntry>>>>
    plannerGridProvider =
    Provider<Map<String, Map<MealType, List<MealPlanEntry>>>>((Ref ref) {
  final List<MealPlanEntry>? entries = ref.watch(mealPlanProvider).valueOrNull;
  final Map<String, Map<MealType, List<MealPlanEntry>>> grid =
      <String, Map<MealType, List<MealPlanEntry>>>{};
  if (entries == null) return grid;

  for (final MealPlanEntry entry in entries) {
    final String key = dayKey(entry.planDate);
    final Map<MealType, List<MealPlanEntry>> byMeal =
        grid.putIfAbsent(key, () => <MealType, List<MealPlanEntry>>{});
    byMeal.putIfAbsent(entry.mealType, () => <MealPlanEntry>[]).add(entry);
  }
  return grid;
});

String dayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
