import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import 'providers.dart';
import 'recipe_controllers.dart';

/// State of an in-progress cook.
class CookingSession {
  const CookingSession({
    required this.recipeId,
    required this.stepIndex,
    required this.totalSteps,
    required this.startedAt,
    this.servings,
  });

  final String recipeId;
  final int stepIndex;
  final int totalSteps;
  final DateTime startedAt;
  final int? servings;

  bool get isFirst => stepIndex == 0;
  bool get isLast => totalSteps == 0 || stepIndex >= totalSteps - 1;

  double get progress => totalSteps == 0 ? 0 : (stepIndex + 1) / totalSteps;

  Duration get elapsed => DateTime.now().difference(startedAt);

  CookingSession copyWith({int? stepIndex}) => CookingSession(
        recipeId: recipeId,
        stepIndex: stepIndex ?? this.stepIndex,
        totalSteps: totalSteps,
        startedAt: startedAt,
        servings: servings,
      );
}

/// Drives Cooking Mode.
///
/// The elapsed time is measured from when the session starts and is
/// what gets offered to the anonymous cook-time log at the end. It is
/// never submitted automatically — the user is asked, because a session
/// left open on a counter for three hours would otherwise poison the
/// community average.
class CookingSessionController extends Notifier<CookingSession?> {
  @override
  CookingSession? build() => null;

  void start(Recipe recipe, {int? servings}) {
    state = CookingSession(
      recipeId: recipe.id,
      stepIndex: 0,
      totalSteps: recipe.steps.length,
      startedAt: DateTime.now(),
      servings: servings,
    );
  }

  void next() {
    final CookingSession? current = state;
    if (current == null || current.isLast) return;
    state = current.copyWith(stepIndex: current.stepIndex + 1);
  }

  void previous() {
    final CookingSession? current = state;
    if (current == null || current.isFirst) return;
    state = current.copyWith(stepIndex: current.stepIndex - 1);
  }

  void jumpTo(int index) {
    final CookingSession? current = state;
    if (current == null) return;
    state = current.copyWith(
      stepIndex:
          index.clamp(0, current.totalSteps == 0 ? 0 : current.totalSteps - 1),
    );
  }

  void cancel() => state = null;

  /// Ends the session and, if the user agreed, records how long it
  /// actually took. Durations outside 1..1440 minutes are dropped: they
  /// are a session someone forgot to close, not a cook time.
  Future<void> finish({required bool logDuration}) async {
    final CookingSession? current = state;
    state = null;
    if (current == null || !logDuration) return;

    final int minutes = current.elapsed.inMinutes;
    if (minutes < 1 || minutes > 1440) return;

    await ref.read(recipeRepositoryProvider).logCookTime(
          recipeId: current.recipeId,
          minutes: minutes,
        );
    ref.invalidate(averageCookMinutesProvider(current.recipeId));
  }
}

final NotifierProvider<CookingSessionController, CookingSession?>
    cookingSessionProvider =
    NotifierProvider<CookingSessionController, CookingSession?>(
        CookingSessionController.new);
