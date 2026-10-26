import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quantity_format.dart';
import '../../data/models/models.dart';
import '../../state/cooking_session_controller.dart';
import '../../state/portion_scaler.dart';
import '../../state/recipe_controllers.dart';
import '../../theme/app_theme.dart';
import '../responsive/breakpoints.dart';
import 'recipe_detail_screen.dart';

/// Cooking Mode.
///
/// Design constraints that drove this screen:
///   * the hand that advances a step is wet, greasy, or is an elbow, so
///     the advance target is the whole lower half of the screen and is
///     never smaller than 96 px;
///   * the text is read from across a worktop, so it is set at
///     headline size regardless of form factor;
///   * the screen must not sleep mid-step;
///   * on a tablet or desktop there is room to keep the ingredient list
///     visible beside the steps, which is the split-pane layout the
///     brief asks for.
class CookingModeScreen extends ConsumerStatefulWidget {
  const CookingModeScreen({required this.recipeId, super.key});

  final String recipeId;

  @override
  ConsumerState<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends ConsumerState<CookingModeScreen> {
  @override
  void initState() {
    super.initState();
    // Keeping the display awake is the difference between a usable
    // cooking screen and one that locks while the user's hands are in a
    // bowl. Restored in dispose.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Recipe> recipe =
        ref.watch(recipeDetailProvider(widget.recipeId));
    final CookingSession? session = ref.watch(cookingSessionProvider);

    return recipe.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, StackTrace s) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('That recipe is not available.')),
      ),
      data: (Recipe r) {
        if (session == null || r.steps.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This recipe has no steps yet.')),
          );
        }
        return _CookingView(recipe: r, session: session);
      },
    );
  }
}

class _CookingView extends ConsumerWidget {
  const _CookingView({required this.recipe, required this.session});

  final Recipe recipe;
  final CookingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<RecipeStep> steps = recipe.sortedSteps;
    final int index = session.stepIndex.clamp(0, steps.length - 1);
    final RecipeStep step = steps[index];

    final List<RecipeIngredient> scaled = PortionScaler.forServings(
      lines: recipe.sortedIngredients,
      baseServings: recipe.baseServings,
      targetServings: session.servings ?? recipe.baseServings,
    );

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        final bool split = Breakpoints.splitCookingPane(scope.width);

        final Widget stepPane = _StepPane(
          recipe: recipe,
          step: step,
          index: index,
          total: steps.length,
          session: session,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(recipe.title, overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Stop cooking',
              onPressed: () => _confirmExit(context, ref),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: session.progress,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          body: split
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: scope.isDesktop ? 380 : 320,
                      child: _IngredientPane(lines: scaled),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: stepPane),
                  ],
                )
              : stepPane,
        );
      },
    );
  }

  Future<void> _confirmExit(BuildContext context, WidgetRef ref) async {
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Finished cooking?'),
        content: Text(
          'You have been at it for '
          '${QuantityFormat.minutes(session.elapsed.inMinutes)}. '
          'Adding that helps everyone see how long this really takes. '
          'It is recorded without your name.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Keep cooking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('quit'),
            child: const Text('Just stop'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('log'),
            child: const Text('Done, add my time'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    await ref
        .read(cookingSessionProvider.notifier)
        .finish(logDuration: choice == 'log');

    if (context.mounted) Navigator.of(context).pop();
  }
}

class _StepPane extends ConsumerWidget {
  const _StepPane({
    required this.recipe,
    required this.step,
    required this.index,
    required this.total,
    required this.session,
  });

  final Recipe recipe;
  final RecipeStep step;
  final int index;
  final int total;
  final CookingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final CookingSessionController controller =
        ref.read(cookingSessionProvider.notifier);

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step ${index + 1} of $total',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  step.instruction,
                  style: AppTheme.cookingStepStyle(context),
                ),
                if (step.hasTimer) ...<Widget>[
                  const SizedBox(height: 24),
                  TimerButton(step: step),
                ],
              ],
            ),
          ),
        ),

        // Tap-to-advance. The primary target is deliberately enormous:
        // the whole width, 96 px tall minimum, with no competing
        // controls inside it.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            children: <Widget>[
              if (session.isLast)
                FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(cookingSessionProvider.notifier)
                        .finish(logDuration: true);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: AppTheme.cookingButtonStyle(theme.colorScheme),
                  icon: const Icon(Icons.check_circle_outline, size: 30),
                  label: const Text('Done'),
                )
              else
                FilledButton.icon(
                  onPressed: controller.next,
                  style: AppTheme.cookingButtonStyle(theme.colorScheme),
                  icon: const Icon(Icons.arrow_forward, size: 30),
                  label: const Text('Next step'),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: session.isFirst ? null : controller.previous,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IngredientPane extends StatelessWidget {
  const _IngredientPane({required this.lines});

  final List<RecipeIngredient> lines;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: <Widget>[
          Text('Ingredients', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final RecipeIngredient line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                PortionScaler.describe(line),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: line.isOptional
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
