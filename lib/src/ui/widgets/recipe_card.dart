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

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _Cover(path: recipe.coverImagePath),
                  if (matchPercent != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _MatchBadge(percent: matchPercent!),
                    ),
                  if (recipe.isPublic)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _Pill(
                        icon: Icons.public,
                        label: 'Shared',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    recipe.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _Meta(text: recipe.mealType.label),
                      if (recipe.season != Season.allYear)
                        _Meta(text: recipe.season.label),
                      if (recipe.totalMinutes != null)
                        _Meta(
                          text: QuantityFormat.minutes(recipe.totalMinutes),
                          icon: Icons.schedule,
                        ),
                      if (recipe.isFork)
                        const _Meta(text: 'Fork', icon: Icons.call_split),
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

class _Cover extends ConsumerWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (path == null) {
      return Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.restaurant_menu,
          size: 36,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return ref.watch(signedCoverProvider(path!)).when(
          loading: () => Container(color: scheme.surfaceContainerHighest),
          error: (_, __) => Container(
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant),
          ),
          data: (String? url) {
            if (url == null) {
              return Container(color: scheme.surfaceContainerHighest);
            }
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: scheme.surfaceContainerHighest),
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
    final Color background = complete
        ? Colors.green.shade700
        : (percent >= 70 ? Colors.orange.shade800 : Colors.blueGrey.shade700);

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
          fontSize: 12,
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
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.bodySmall;
    if (text.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 13, color: style?.color),
          const SizedBox(width: 3),
        ],
        Text(text, style: style),
      ],
    );
  }
}
