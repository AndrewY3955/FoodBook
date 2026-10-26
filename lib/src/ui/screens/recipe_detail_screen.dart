import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quantity_format.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../platform/native_timer.dart';
import '../../state/cooking_session_controller.dart';
import '../../state/discover_controller.dart';
import '../../state/library_controller.dart';
import '../../state/portion_scaler.dart';
import '../../state/providers.dart';
import '../../state/recipe_controllers.dart';
import '../../state/shopping_controller.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';
import '../widgets/diet_nutrition_section.dart' show NutritionFactsPanel;
import '../widgets/recipe_appearance_section.dart' show parseAccent;
import '../widgets/recipe_card.dart';
import 'cooking_mode_screen.dart';
import 'recipe_form_screen.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({required this.recipeId, super.key});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Recipe> recipe = ref.watch(recipeDetailProvider(recipeId));

    return Scaffold(
      body: recipe.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace s) => Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('That recipe is not available.')),
        ),
        data: (Recipe r) => _Loaded(recipe: r),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int servings = ref.watch(servingsProvider(recipe.id));
    final String? activeLibrary = ref.watch(activeLibraryIdProvider);
    final bool isOwn = recipe.libraryId == activeLibrary;

    final List<RecipeIngredient> scaled = PortionScaler.forServings(
      lines: recipe.sortedIngredients,
      baseServings: recipe.baseServings,
      targetServings: servings,
    );

    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        final Widget ingredients = _IngredientPanel(
          recipe: recipe,
          scaled: scaled,
          servings: servings,
        );
        final Widget steps = _StepPanel(recipe: recipe);

        final Widget scroll = CustomScrollView(
          slivers: <Widget>[
            SliverAppBar.large(
              pinned: true,
              expandedHeight: scope.isPhone ? 220 : 280,
              actions: <Widget>[
                if (isOwn)
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      ref.read(recipeFormProvider.notifier).loadFrom(recipe);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecipeFormScreen(recipeId: recipe.id),
                        ),
                      );
                    },
                  ),
                _OverflowMenu(recipe: recipe, isOwn: isOwn),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: Text(recipe.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 56,
                  end: 96,
                  bottom: 14,
                ),
                background: recipe.coverImagePath == null
                    ? Builder(
                        builder: (BuildContext inner) => Container(
                          color: Theme.of(inner)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      )
                    : _HeaderImage(path: recipe.coverImagePath!),
              ),
            ),
            SliverToBoxAdapter(
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _Header(recipe: recipe),
                ),
              ),
            ),
            if (recipe.images.isNotEmpty)
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _Gallery(images: recipe.images),
                  ),
                ),
              ),
            if (!recipe.nutrition.isEmpty)
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: NutritionFactsPanel(
                        nutrition: recipe.nutrition,
                        servings: recipe.baseServings,
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  // Tablet and desktop read ingredients and method side
                  // by side; a phone stacks them.
                  child: scope.isPhone
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ingredients,
                            const SizedBox(height: 24),
                            steps,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 4, child: ingredients),
                            const SizedBox(width: 28),
                            Expanded(flex: 6, child: steps),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );

        return _Themed(recipe: recipe, child: scroll);
      },
    );
  }
}

/// Applies the recipe's theme, accent colour and background picture to
/// everything beneath it. A recipe with none of those set is left on the
/// app theme untouched.
class _Themed extends ConsumerWidget {
  const _Themed({required this.recipe, required this.child});

  final Recipe recipe;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool styled = recipe.theme != RecipeTheme.plain ||
        recipe.accentColor != null ||
        recipe.backgroundImagePath != null;
    if (!styled) return child;

    final ThemeData parent = Theme.of(context);
    final bool dark = recipe.theme == RecipeTheme.night;
    final Color background = Color(recipe.theme.background);
    final Color foreground = Color(recipe.theme.foreground);
    final Color? accent = parseAccent(recipe.accentColor);

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent ?? parent.colorScheme.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      surface: background,
      onSurface: foreground,
      surfaceContainerHighest:
          Color.alphaBlend(foreground.withValues(alpha: 0.08), background),
    );

    final ThemeData themed = parent.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: parent.textTheme
          .apply(bodyColor: foreground, displayColor: foreground),
      iconTheme: parent.iconTheme.copyWith(color: foreground),
      appBarTheme: parent.appBarTheme.copyWith(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: parent.chipTheme.copyWith(
        labelStyle: TextStyle(color: foreground),
        backgroundColor: Color.alphaBlend(
          foreground.withValues(alpha: 0.10),
          background,
        ),
        side: BorderSide(color: foreground.withValues(alpha: 0.25)),
      ),
    );

    // Text outside a Material ancestor inherits the app's default style,
    // so the themed colours are re-applied for the whole subtree.
    return Theme(
      data: themed,
      child: DefaultTextStyle(
        style: themed.textTheme.bodyMedium ?? const TextStyle(),
        child: IconTheme(
          data: themed.iconTheme,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: ColoredBox(color: background)),
              if (recipe.backgroundImagePath != null)
                Positioned.fill(
                  child: _BackdropImage(
                    path: recipe.backgroundImagePath!,
                    background: background,
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropImage extends ConsumerWidget {
  const _BackdropImage({required this.path, required this.background});

  final String path;
  final Color background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(signedCoverProvider(path)).maybeWhen(
          data: (String? url) => url == null
              ? const SizedBox.shrink()
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    // A scrim keeps body text readable over any picture.
                    ColoredBox(color: background.withValues(alpha: 0.86)),
                  ],
                ),
          orElse: () => const SizedBox.shrink(),
        );
  }
}

class _Gallery extends ConsumerWidget {
  const _Gallery({required this.images});

  final List<RecipeImage> images;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final RecipeImage image = images[i];
          return Semantics(
            button: true,
            label: image.caption ?? 'Recipe photo ${i + 1}',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showDialog<void>(
                context: context,
                builder: (BuildContext context) => Dialog(
                  child: Consumer(
                    builder: (BuildContext context, WidgetRef ref, _) => ref
                        .watch(signedCoverProvider(image.storagePath))
                        .maybeWhen(
                          data: (String? url) => url == null
                              ? const SizedBox(
                                  height: 200,
                                  child: Center(child: Text('Not available')),
                                )
                              : InteractiveViewer(
                                  child: Image.network(url),
                                ),
                          orElse: () => const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ref
                      .watch(signedCoverProvider(image.storagePath))
                      .maybeWhen(
                        data: (String? url) => url == null
                            ? const SizedBox.shrink()
                            : Image.network(url, fit: BoxFit.cover),
                        orElse: () => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderImage extends ConsumerWidget {
  const _HeaderImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(signedCoverProvider(path)).maybeWhen(
          data: (String? url) => url == null
              ? const SizedBox.shrink()
              : Image.network(url, fit: BoxFit.cover),
          orElse: () => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<int?> average =
        ref.watch(averageCookMinutesProvider(recipe.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            Chip(label: Text(recipe.mealType.label)),
            if (recipe.season != Season.allYear)
              Chip(label: Text(recipe.season.label)),
            for (final Diet d in recipe.diets)
              Chip(
                avatar: const Icon(Icons.spa_outlined, size: 16),
                label: Text(d.label),
              ),
            for (final String tag in recipe.tags) Chip(label: Text(tag)),
            if (recipe.importSource != ImportSource.manual)
              Chip(
                avatar: const Icon(Icons.link, size: 16),
                label: Text(recipe.importSource.label),
              ),
          ],
        ),
        if (recipe.description != null) ...<Widget>[
          const SizedBox(height: 14),
          Text(recipe.description!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            if (recipe.totalMinutes != null) ...<Widget>[
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 6),
              Text('${QuantityFormat.minutes(recipe.totalMinutes)} as written'),
            ],
            average.maybeWhen(
              data: (int? minutes) => minutes == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.groups_outlined, size: 18),
                          const SizedBox(width: 6),
                          // Anonymous, aggregated, and only shown once
                          // enough people have logged one to be worth
                          // anything.
                          Text(
                              '${QuantityFormat.minutes(minutes)} in practice'),
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        if (recipe.externalVideoUrl != null) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => NativeTimer.openExternal(recipe.externalVideoUrl!),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch the original'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Opens outside the app. Nothing is hosted here.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

class _IngredientPanel extends ConsumerWidget {
  const _IngredientPanel({
    required this.recipe,
    required this.scaled,
    required this.servings,
  });

  final Recipe recipe;
  final List<RecipeIngredient> scaled;
  final int servings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Ingredients', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),

        // Dynamic portion scaler. Quantities below update live; the
        // recipe itself is never rewritten.
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: servings <= 1
                      ? null
                      : () => ref
                          .read(servingsProvider(recipe.id).notifier)
                          .decrement(),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      QuantityFormat.servings(servings),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: servings >= 100
                      ? null
                      : () => ref
                          .read(servingsProvider(recipe.id).notifier)
                          .increment(),
                ),
              ],
            ),
          ),
        ),
        if (servings != recipe.baseServings)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Scaled from ${QuantityFormat.servings(recipe.baseServings)}',
              style: theme.textTheme.bodySmall,
            ),
          ),

        const SizedBox(height: 8),
        for (final RecipeIngredient line in scaled)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 10),
                  child: Icon(Icons.circle, size: 6),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: QuantityFormat.withUnit(
                                line.quantity,
                                line.unit,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (line.unit != MeasureUnit.toTaste)
                              TextSpan(text: '  ${line.name}'),
                            if (line.unit == MeasureUnit.toTaste)
                              TextSpan(text: '  ${line.name}'),
                            if (line.isOptional)
                              const TextSpan(text: '  (optional)'),
                          ],
                        ),
                      ),
                      if (line.note != null)
                        Text(
                          line.note!,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () async {
            final int touched = await ref
                .read(shoppingListProvider.notifier)
                .addRecipe(recipeId: recipe.id, servings: servings);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    touched == 0
                        ? 'Your pantry already covers this one.'
                        : '$touched item${touched == 1 ? '' : 's'} added to the shopping list.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Add what I am missing'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

class _StepPanel extends ConsumerWidget {
  const _StepPanel({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<RecipeStep> steps = recipe.sortedSteps;
    final int servings = ref.watch(servingsProvider(recipe.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Method', style: theme.textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: steps.isEmpty
                  ? null
                  : () {
                      ref
                          .read(cookingSessionProvider.notifier)
                          .start(recipe, servings: servings);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CookingModeScreen(recipeId: recipe.id),
                        ),
                      );
                    },
              icon: const Icon(Icons.local_fire_department_outlined),
              label: const Text('Start cooking'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final RecipeStep step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    '${step.stepNumber}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(step.instruction, style: theme.textTheme.bodyLarge),
                      if (step.hasTimer)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TimerButton(step: step),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Hands the duration to the OS clock app. Where that is not possible
/// the button says so rather than pretending.
class TimerButton extends StatelessWidget {
  const TimerButton({required this.step, super.key});

  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    final String label = QuantityFormat.minutes(step.timer.inMinutes);

    if (!NativeTimer.isSupported) {
      return Chip(
        avatar: const Icon(Icons.timer_outlined, size: 16),
        label: Text('$label — set a timer'),
      );
    }

    return OutlinedButton.icon(
      onPressed: () async {
        final bool started = await NativeTimer.start(
          duration: step.timer,
          label: 'Step ${step.stepNumber}',
        );
        if (!started && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Set a $label timer on your clock app.'),
            ),
          );
        }
      },
      icon: const Icon(Icons.timer_outlined, size: 18),
      label: Text('Start $label timer'),
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.recipe, required this.isOwn});

  final Recipe recipe;
  final bool isOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (String value) async {
        final String? libraryId = ref.read(activeLibraryIdProvider);
        switch (value) {
          case 'fork':
            if (libraryId == null) return;
            final String newId = await ref
                .read(recipeRepositoryProvider)
                .fork(recipeId: recipe.id, libraryId: libraryId);
            final int failed = await ref
                .read(storageRepositoryProvider)
                .copyImagesForFork(
                    sourceRecipeId: recipe.id,
                    newRecipeId: newId,
                    libraryId: libraryId);
            ref.invalidate(recipeListProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(failed == 0
                      ? 'Forked into your library with its photos and style.'
                      : 'Forked, but $failed image(s) could not be copied.'),
                ),
              );
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => RecipeDetailScreen(recipeId: newId),
                ),
              );
            }
          case 'share':
            await ref
                .read(recipeRepositoryProvider)
                .setPublic(recipe.id, !recipe.isPublic);
            ref.invalidate(recipeDetailProvider(recipe.id));
            ref.invalidate(recipeListProvider);
            ref.invalidate(discoverFeedProvider);
          case 'delete':
            final bool? ok = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('Delete this recipe?'),
                content: const Text('This cannot be undone.'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep it'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok ?? false) {
              await ref.read(recipeRepositoryProvider).delete(recipe.id);
              ref.invalidate(recipeListProvider);
              ref.invalidate(discoverFeedProvider);
              if (context.mounted) Navigator.of(context).pop();
            }
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'fork',
          child: ListTile(
            leading: Icon(Icons.call_split),
            title: Text('Fork into my library'),
            subtitle: Text('Text, notes, photos and style'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (isOwn)
          PopupMenuItem<String>(
            value: 'share',
            child: ListTile(
              leading:
                  Icon(recipe.isPublic ? Icons.lock_outline : Icons.public),
              title: Text(recipe.isPublic ? 'Make private' : 'Share publicly'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (isOwn)
          const PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
