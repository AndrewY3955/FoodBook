import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quantity_format.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../state/providers.dart';

/// Cover image for a private bucket object.
///
/// The signed URL is fetched per path and cached by the provider for
/// the life of the screen. Without the family cache every scroll would
/// mint a new signed URL for the same object.
final FutureProviderFamily<String?, String> signedCoverProvider =
    FutureProvider.family<String?, String>(
  (Ref ref, String path) =>
      ref.watch(storageRepositoryProvider).signedCoverUrl(path),
);

/// One warm tint and one glyph per meal type, so a recipe with no photo
/// reads as a finished card rather than a missing image. Each ink is
/// well above 7:1 on its paper.
class _Tint {
  const _Tint(this.paper, this.ink, this.glyph);

  final Color paper;
  final Color ink;
  final IconData glyph;
}

const Map<MealType, _Tint> _lightTints = <MealType, _Tint>{
  MealType.breakfast: _Tint(Color(0xFFFCEBC8), Color(0xFF4A2E05), Icons.free_breakfast_outlined),
  MealType.lunch: _Tint(Color(0xFFE3EBD3), Color(0xFF26361A), Icons.lunch_dining_outlined),
  MealType.dinner: _Tint(Color(0xFFF7DDD0), Color(0xFF4F1D0A), Icons.dinner_dining_outlined),
  MealType.snack: _Tint(Color(0xFFEBE0F0), Color(0xFF35203F), Icons.cookie_outlined),
  MealType.dessert: _Tint(Color(0xFFF9DCE3), Color(0xFF50182B), Icons.cake_outlined),
};

const Map<MealType, _Tint> _darkTints = <MealType, _Tint>{
  MealType.breakfast: _Tint(Color(0xFF3B2F18), Color(0xFFF6E3BC), Icons.free_breakfast_outlined),
  MealType.lunch: _Tint(Color(0xFF28321F), Color(0xFFD9E6C6), Icons.lunch_dining_outlined),
  MealType.dinner: _Tint(Color(0xFF3C241A), Color(0xFFF5D8C8), Icons.dinner_dining_outlined),
  MealType.snack: _Tint(Color(0xFF32283A), Color(0xFFE6D8EE), Icons.cookie_outlined),
  MealType.dessert: _Tint(Color(0xFF3A222A), Color(0xFFF5D6DF), Icons.cake_outlined),
};

_Tint _tintFor(BuildContext context, MealType meal) =>
    (Theme.of(context).brightness == Brightness.dark ? _darkTints : _lightTints)[meal]!;

/// "35 min · Serves 4". Essential facts wrap rather than truncate.
String recipeMeta(Recipe recipe) {
  final List<String> parts = <String>[
    if (recipe.totalMinutes != null)
      QuantityFormat.minutes(recipe.totalMinutes),
    'Serves ${recipe.baseServings}',
  ];
  return parts.join(' · ');
}

/// Typographic header for a recipe with no photo.
class RecipeNoPhoto extends StatelessWidget {
  const RecipeNoPhoto({required this.recipe, this.large = false, super.key});

  final Recipe recipe;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final _Tint tint = _tintFor(context, recipe.mealType);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      color: tint.paper,
      padding: EdgeInsets.all(large ? 24 : 14),
      child: Stack(
        children: <Widget>[
          Align(
            alignment: Alignment.topRight,
            child: ExcludeSemantics(
              child: Icon(
                tint.glyph,
                size: large ? 44 : 28,
                color: tint.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              recipe.title,
              maxLines: large ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              style: (large ? text.headlineMedium : text.titleLarge)?.copyWith(
                color: tint.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RecipeCard extends ConsumerWidget {
  const RecipeCard({
    required this.recipe,
    required this.onTap,
    this.matchPercent,
    super.key,
  });

  final Recipe recipe;
  final VoidCallback onTap;

  /// When shown inside the pantry matcher, the percentage badge.
  final int? matchPercent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool hasPhoto = recipe.coverImagePath != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  hasPhoto
                      ? _Cover(recipe: recipe)
                      : RecipeNoPhoto(recipe: recipe),
                  if (matchPercent != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _MatchBadge(percent: matchPercent!),
                    ),
                  if (recipe.isPublic)
                    const Positioned(
                      bottom: 8,
                      right: 8,
                      child: _Pill(icon: Icons.public, label: 'Shared'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (hasPhoto)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        recipe.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                        ),
                      ),
                    ),
                  Text(recipeMeta(recipe), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: <Widget>[
                      Text(
                        recipe.mealType.label,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (recipe.cuisine != null)
                        Text(
                          recipe.cuisine!.label,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (recipe.season != Season.allYear)
                        Text(
                          recipe.season.label,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (recipe.isFork)
                        Text('Copy', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-column, large-text row used by the List view.
class RecipeListTile extends ConsumerWidget {
  const RecipeListTile({
    required this.recipe,
    required this.onTap,
    super.key,
  });

  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool hasPhoto = recipe.coverImagePath != null;
    final _Tint tint = _tintFor(context, recipe.mealType);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 88,
                height: 88,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: hasPhoto
                      ? _Cover(recipe: recipe)
                      : Container(
                          color: tint.paper,
                          child: ExcludeSemantics(
                            child: Icon(tint.glyph, size: 36, color: tint.ink),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      recipe.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${recipe.mealType.label} · ${recipeMeta(recipe)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String path = recipe.coverImagePath!;

    return ref.watch(signedCoverProvider(path)).when(
          loading: () => ColoredBox(
            color: _tintFor(context, recipe.mealType).paper,
          ),
          error: (_, __) => RecipeNoPhoto(recipe: recipe),
          data: (String? url) {
            if (url == null) return RecipeNoPhoto(recipe: recipe);
            return Image.network(
              url,
              fit: BoxFit.cover,
              semanticLabel: recipe.title,
              errorBuilder: (_, __, ___) => RecipeNoPhoto(recipe: recipe),
            );
          },
        );
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final bool complete = percent >= 100;
    // All three are at least 5:1 against white text.
    final Color background = complete
        ? const Color(0xFF3F6140)
        : (percent >= 70 ? const Color(0xFF8A4B08) : const Color(0xFF455A64));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        complete ? 'Ready to cook' : 'You have $percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        // Opaque enough that white text clears AA over any photo.
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
