import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/failure.dart';
import '../../core/quantity_format.dart';
import '../../core/security/input_sanitizer.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../state/library_controller.dart';
import '../../state/pantry_controllers.dart';
import '../../state/providers.dart';
import '../../state/recipe_controllers.dart';
import '../responsive/adaptive_scaffold.dart';
import '../responsive/breakpoints.dart';

/// Multi-step manual entry.
///
/// Three panes — the basics, the ingredients, the method — presented as
/// a Stepper on a phone and side by side on a wide screen. The draft
/// lives in RecipeFormController, so rotating the device or switching
/// panes never loses input.
class RecipeFormScreen extends ConsumerStatefulWidget {
  const RecipeFormScreen({this.recipeId, super.key});

  /// Null for a new recipe. When set, the controller has already been
  /// loaded with that recipe by the caller.
  final String? recipeId;

  @override
  ConsumerState<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends ConsumerState<RecipeFormScreen> {
  int _pane = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.recipeId == null) {
      // A fresh form. Deferred so it does not mutate a provider during
      // the first build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final RecipeDraft draft = ref.read(recipeFormProvider);
        // Leave an imported draft alone; only clear a stale manual one.
        if (draft.importSource == ImportSource.manual &&
            draft.title.isEmpty &&
            draft.ingredients.isEmpty) {
          return;
        }
        if (draft.importSource == ImportSource.manual) {
          ref.read(recipeFormProvider.notifier).reset();
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String id = await ref.read(recipeFormProvider.notifier).save();
      if (!mounted) return;

      final RecipeDraft draft = ref.read(recipeFormProvider);
      if (_pendingCover != null) {
        final String? libraryId = ref.read(activeLibraryIdProvider);
        if (libraryId != null) {
          await ref.read(storageRepositoryProvider).uploadCover(
                libraryId: libraryId,
                recipeId: id,
                bytes: _pendingCover!,
              );
          ref.invalidate(recipeDetailProvider(id));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(draft.isEditing ? 'Recipe updated.' : 'Recipe saved.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = Failure.from(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Uint8List? _pendingCover;

  @override
  Widget build(BuildContext context) {
    final RecipeDraft draft = ref.watch(recipeFormProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(draft.isEditing ? 'Edit recipe' : 'New recipe'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ResponsiveBuilder(
        builder: (BuildContext context, LayoutScope scope) {
          final Widget basics = _BasicsPane(
            onCoverPicked: (Uint8List bytes) =>
                setState(() => _pendingCover = bytes),
            hasPendingCover: _pendingCover != null,
          );
          const Widget ingredients = _IngredientsPane();
          const Widget steps = _StepsPane();

          final Widget error = _error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                );

          if (scope.isPhone) {
            return Column(
              children: <Widget>[
                error,
                Expanded(
                  child: Stepper(
                    currentStep: _pane,
                    onStepTapped: (int i) => setState(() => _pane = i),
                    onStepContinue:
                        _pane < 2 ? () => setState(() => _pane++) : _save,
                    onStepCancel:
                        _pane > 0 ? () => setState(() => _pane--) : null,
                    controlsBuilder:
                        (BuildContext context, ControlsDetails details) =>
                            Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: <Widget>[
                          FilledButton(
                            onPressed: details.onStepContinue,
                            child: Text(_pane < 2 ? 'Next' : 'Save'),
                          ),
                          const SizedBox(width: 8),
                          if (_pane > 0)
                            TextButton(
                              onPressed: details.onStepCancel,
                              child: const Text('Back'),
                            ),
                        ],
                      ),
                    ),
                    steps: <Step>[
                      Step(
                        title: const Text('The basics'),
                        isActive: _pane == 0,
                        content: basics,
                      ),
                      Step(
                        title: const Text('Ingredients'),
                        isActive: _pane == 1,
                        content: ingredients,
                      ),
                      Step(
                        title: const Text('Method'),
                        isActive: _pane == 2,
                        content: steps,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            children: <Widget>[
              error,
              Expanded(
                child: ContentWidth(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 4, child: basics),
                        const SizedBox(width: 28),
                        const Expanded(flex: 4, child: ingredients),
                        const SizedBox(width: 28),
                        const Expanded(flex: 5, child: steps),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BasicsPane extends ConsumerWidget {
  const _BasicsPane({
    required this.onCoverPicked,
    required this.hasPendingCover,
  });

  final ValueChanged<Uint8List> onCoverPicked;
  final bool hasPendingCover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecipeDraft draft = ref.watch(recipeFormProvider);
    final RecipeFormController controller =
        ref.read(recipeFormProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          initialValue: draft.title,
          decoration: const InputDecoration(labelText: 'Title'),
          textCapitalization: TextCapitalization.sentences,
          maxLength: 160,
          onChanged: controller.setTitle,
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: draft.description,
          decoration: const InputDecoration(
            labelText: 'Description',
            alignLabelWithHint: true,
          ),
          maxLines: 4,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: controller.setDescription,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<MealType>(
          initialValue: draft.mealType,
          decoration: const InputDecoration(labelText: 'Meal'),
          items: MealType.values
              .map((MealType m) =>
                  DropdownMenuItem<MealType>(value: m, child: Text(m.label)))
              .toList(growable: false),
          onChanged: (MealType? v) {
            if (v != null) controller.setMealType(v);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<Season>(
          initialValue: draft.season,
          decoration: const InputDecoration(labelText: 'Season'),
          items: Season.values
              .map((Season s) =>
                  DropdownMenuItem<Season>(value: s, child: Text(s.label)))
              .toList(growable: false),
          onChanged: (Season? v) {
            if (v != null) controller.setSeason(v);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                initialValue: '${draft.baseServings}',
                decoration: const InputDecoration(labelText: 'Serves'),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (String v) =>
                    controller.setBaseServings(int.tryParse(v) ?? 4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: draft.prepMinutes?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Prep (min)'),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (String v) =>
                    controller.setPrepMinutes(int.tryParse(v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: draft.cookMinutes?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Cook (min)'),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (String v) =>
                    controller.setCookMinutes(int.tryParse(v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: draft.externalVideoUrl ?? '',
          decoration: const InputDecoration(
            labelText: 'Video link (optional)',
            hintText: 'https://www.youtube.com/watch?v=…',
            helperText: 'Opens outside the app. Nothing is hosted here.',
          ),
          keyboardType: TextInputType.url,
          onChanged: (String v) =>
              controller.setVideoUrl(v.trim().isEmpty ? null : v),
          validator: (String? v) {
            if (v == null || v.trim().isEmpty) return null;
            return InputSanitizer.videoUrl(v) == null
                ? 'Use a full https link from a supported site.'
                : null;
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final XFile? picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 2400,
            );
            if (picked == null) return;
            onCoverPicked(await picked.readAsBytes());
          },
          icon: const Icon(Icons.image_outlined),
          label: Text(
            hasPendingCover ? 'Cover photo chosen' : 'Choose a cover photo',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'One photo per recipe. It is resized and re-encoded on this '
            'device, which strips the location data your camera embedded.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: draft.isPublic,
          onChanged: controller.setPublic,
          title: const Text('Share publicly'),
          subtitle: const Text(
            'Anyone can find and fork it. Your pantry and plan stay private.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _IngredientsPane extends ConsumerStatefulWidget {
  const _IngredientsPane();

  @override
  ConsumerState<_IngredientsPane> createState() => _IngredientsPaneState();
}

class _IngredientsPaneState extends ConsumerState<_IngredientsPane> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RecipeDraft draft = ref.watch(recipeFormProvider);
    final RecipeFormController controller =
        ref.read(recipeFormProvider.notifier);
    final AsyncValue<List<Ingredient>> results =
        ref.watch(ingredientSearchProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Add an ingredient',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (String v) => setState(() => _query = v),
        ),
        if (_query.trim().isNotEmpty)
          SizedBox(
            height: 180,
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Search failed.')),
              data: (List<Ingredient> list) => ListView(
                children: <Widget>[
                  for (final Ingredient i in list)
                    ListTile(
                      dense: true,
                      title: Text(i.name),
                      subtitle: Text(i.category.label),
                      trailing: const Icon(Icons.add),
                      onTap: () {
                        controller.addIngredient(DraftIngredient(
                          ingredientId: i.id,
                          name: i.name,
                          unit: i.defaultUnit,
                        ));
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
                  if (list.isEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add_circle_outline),
                      title: Text('Create "${_search.text.trim()}"'),
                      subtitle: const Text('Only your library will see it'),
                      onTap: () async {
                        final String? libraryId =
                            ref.read(activeLibraryIdProvider);
                        if (libraryId == null) return;
                        final Ingredient created = await ref
                            .read(ingredientRepositoryProvider)
                            .findOrCreate(
                              libraryId: libraryId,
                              name: _search.text,
                            );
                        controller.addIngredient(DraftIngredient(
                          ingredientId: created.id,
                          name: created.name,
                          unit: created.defaultUnit,
                        ));
                        _search.clear();
                        if (mounted) setState(() => _query = '');
                      },
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (draft.ingredients.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Nothing added yet.', textAlign: TextAlign.center),
          ),
        for (int i = 0; i < draft.ingredients.length; i++)
          _IngredientRow(
            key: ValueKey<String>(
              '${draft.ingredients[i].ingredientId}-$i',
            ),
            index: i,
            item: draft.ingredients[i],
          ),
      ],
    );
  }
}

class _IngredientRow extends ConsumerWidget {
  const _IngredientRow({required this.index, required this.item, super.key});

  final int index;
  final DraftIngredient item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecipeFormController controller =
        ref.read(recipeFormProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 68,
            child: TextFormField(
              initialValue: QuantityFormat.amount(item.quantity),
              decoration:
                  const InputDecoration(isDense: true, labelText: 'Qty'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (String v) {
                final double? parsed = InputSanitizer.quantity(v);
                if (parsed == null) return;
                item.quantity = parsed;
                controller.updateIngredient(index, item);
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<MeasureUnit>(
              initialValue: item.unit,
              decoration: const InputDecoration(isDense: true),
              items: MeasureUnit.values
                  .map((MeasureUnit u) => DropdownMenuItem<MeasureUnit>(
                        value: u,
                        child: Text(u.label.isEmpty ? 'each' : u.label),
                      ))
                  .toList(growable: false),
              onChanged: (MeasureUnit? u) {
                if (u == null) return;
                item.unit = u;
                controller.updateIngredient(index, item);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(item.name),
            ),
          ),
          IconButton(
            tooltip: item.isOptional ? 'Optional' : 'Required',
            icon: Icon(
              item.isOptional ? Icons.star_border : Icons.star,
              size: 20,
            ),
            onPressed: () {
              item.isOptional = !item.isOptional;
              controller.updateIngredient(index, item);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => controller.removeIngredient(index),
          ),
        ],
      ),
    );
  }
}

class _StepsPane extends ConsumerWidget {
  const _StepsPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecipeDraft draft = ref.watch(recipeFormProvider);
    final RecipeFormController controller =
        ref.read(recipeFormProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < draft.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 14, right: 8),
                  child: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: draft.steps[i].instruction,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'What happens now?',
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (String v) => controller.updateStep(
                        i, v, draft.steps[i].timerSeconds),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 92,
                  child: TextFormField(
                    initialValue: draft.steps[i].timerSeconds == null
                        ? ''
                        : '${draft.steps[i].timerSeconds! ~/ 60}',
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Timer',
                      suffixText: 'min',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (String v) {
                      final int? minutes = int.tryParse(v);
                      controller.updateStep(
                        i,
                        draft.steps[i].instruction,
                        minutes == null || minutes <= 0 ? null : minutes * 60,
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => controller.removeStep(i),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: controller.addStep,
          icon: const Icon(Icons.add),
          label: const Text('Add a step'),
        ),
      ],
    );
  }
}
