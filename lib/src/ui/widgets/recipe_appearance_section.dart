import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/failure.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../state/providers.dart';
import '../../state/recipe_controllers.dart';
import 'recipe_card.dart';

/// Accent colours offered in the form. Stored as `#RRGGBB`.
const List<String> kAccentChoices = <String>[
  '#C0392B',
  '#E67E22',
  '#B7950B',
  '#27AE60',
  '#1ABC9C',
  '#2980B9',
  '#8E44AD',
  '#34495E',
];

Color? parseAccent(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final int? value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

Future<Uint8List?> _pickImage() async {
  final XFile? picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
  );
  return picked?.readAsBytes();
}

/// Theme, accent colour, background image and extra photos.
///
/// New images are staged in the parent (`pendingBackground`,
/// `pendingPhotos`) and uploaded after the recipe row exists, because the
/// storage path embeds the recipe id. Images that already exist on the
/// server are removed immediately, after a confirmation.
class RecipeAppearanceSection extends ConsumerWidget {
  const RecipeAppearanceSection({
    required this.recipeId,
    required this.pendingBackground,
    required this.pendingPhotos,
    required this.onBackgroundPicked,
    required this.onBackgroundCleared,
    required this.onPhotosAdded,
    required this.onPendingPhotoRemoved,
    super.key,
  });

  final String? recipeId;
  final Uint8List? pendingBackground;
  final List<Uint8List> pendingPhotos;
  final ValueChanged<Uint8List> onBackgroundPicked;
  final VoidCallback onBackgroundCleared;
  final ValueChanged<Uint8List> onPhotosAdded;
  final ValueChanged<int> onPendingPhotoRemoved;

  static const int maxPhotos = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final RecipeDraft draft = ref.watch(recipeFormProvider);
    final RecipeFormController controller =
        ref.read(recipeFormProvider.notifier);
    final Recipe? saved = recipeId == null
        ? null
        : ref.watch(recipeDetailProvider(recipeId!)).valueOrNull;
    final List<RecipeImage> existing = saved?.images ?? const <RecipeImage>[];
    final String? existingBackground = saved?.backgroundImagePath;
    final int photoCount = existing.length + pendingPhotos.length;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Failure.from(error).message)),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Look and feel', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final RecipeTheme t in RecipeTheme.values)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: Color(t.background),
                  radius: 8,
                ),
                label: Text(t.label),
                selected: draft.theme == t,
                onSelected: (_) => controller.setTheme(t),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Accent colour', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Semantics(
              button: true,
              selected: draft.accentColor == null,
              label: 'Default accent colour',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => controller.setAccentColor(null),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: draft.accentColor == null
                      ? const Icon(Icons.check, size: 16)
                      : const Icon(Icons.format_color_reset, size: 16),
                ),
              ),
            ),
            for (final String hex in kAccentChoices)
              Semantics(
                button: true,
                selected: draft.accentColor == hex,
                label: 'Accent colour $hex',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => controller.setAccentColor(hex),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: parseAccent(hex),
                    child: draft.accentColor == hex
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Background picture', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => run(() async {
                final Uint8List? bytes = await _pickImage();
                if (bytes != null) onBackgroundPicked(bytes);
              }),
              icon: const Icon(Icons.wallpaper_outlined),
              label: Text(
                pendingBackground != null || existingBackground != null
                    ? 'Change background'
                    : 'Add a background',
              ),
            ),
            const SizedBox(width: 8),
            if (pendingBackground != null)
              TextButton(
                onPressed: onBackgroundCleared,
                child: const Text('Undo'),
              )
            else if (existingBackground != null)
              TextButton(
                onPressed: () => run(() async {
                  await ref.read(storageRepositoryProvider).removeBackground(
                        recipeId: recipeId!,
                        path: existingBackground,
                      );
                  ref.invalidate(recipeDetailProvider(recipeId!));
                }),
                child: const Text('Remove'),
              ),
          ],
        ),
        if (pendingBackground != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 80,
                child: Image.memory(pendingBackground!, fit: BoxFit.cover),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('More photos ($photoCount of $maxPhotos)',
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final RecipeImage image in existing)
              _Thumb(
                image: _SignedThumb(path: image.storagePath),
                label: 'Remove photo',
                onRemove: () => run(() async {
                  await ref.read(storageRepositoryProvider).removePhoto(image);
                  ref.invalidate(recipeDetailProvider(recipeId!));
                }),
              ),
            for (int i = 0; i < pendingPhotos.length; i++)
              _Thumb(
                image: Image.memory(pendingPhotos[i], fit: BoxFit.cover),
                label: 'Remove new photo',
                onRemove: () => onPendingPhotoRemoved(i),
              ),
            if (photoCount < maxPhotos)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => run(() async {
                  final Uint8List? bytes = await _pickImage();
                  if (bytes != null) onPhotosAdded(bytes);
                }),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Tooltip(
                    message: 'Add a photo',
                    child: Icon(Icons.add_a_photo_outlined),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Every picture is resized and re-encoded on this device, which '
            'strips the location data your camera embedded.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.image,
    required this.label,
    required this.onRemove,
  });

  final Widget image;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: label,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: const Size(24, 24),
              ),
              icon: const Icon(Icons.close, size: 14),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedThumb extends ConsumerWidget {
  const _SignedThumb({required this.path});

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
