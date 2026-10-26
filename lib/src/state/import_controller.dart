import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/failure.dart';
import '../data/models/enums.dart';
import '../data/models/models.dart';
import '../data/repositories/recipe_repository.dart';
import 'library_controller.dart';
import 'providers.dart';
import 'recipe_controllers.dart';

sealed class ImportState {
  const ImportState();
}

class ImportIdle extends ImportState {
  const ImportIdle();
}

class ImportRunning extends ImportState {
  const ImportRunning(this.message);
  final String message;
}

class ImportFailed extends ImportState {
  const ImportFailed(this.message);
  final String message;
}

class ImportReady extends ImportState {
  const ImportReady(this.parsed, this.matchedCount, this.createdCount);
  final ParsedImport parsed;

  /// How many lines matched an existing catalog ingredient, and how many
  /// had to be created as library-private entries. Shown to the user so
  /// they know which lines are worth checking.
  final int matchedCount;
  final int createdCount;
}

/// Runs a URL through the Edge Function, then resolves the returned
/// ingredient lines into real ingredient rows and loads the recipe form.
///
/// Nothing is saved. The parse of a social-media caption is a guess, and
/// a guess should land in an editable form, not in the recipe box.
class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportIdle();

  void reset() => state = const ImportIdle();

  Future<void> run(String rawUrl) async {
    state = const ImportRunning('Reading that link…');

    final String? libraryId = ref.read(activeLibraryIdProvider);
    if (libraryId == null) {
      state = const ImportFailed('Pick a library first.');
      return;
    }

    try {
      final ParsedImport parsed =
          await ref.read(importRepositoryProvider).parse(rawUrl);

      state = const ImportRunning('Matching ingredients…');

      final List<DraftIngredient> draft = <DraftIngredient>[];
      int matched = 0;
      int created = 0;

      for (final String line in parsed.ingredientLines) {
        final _ParsedLine parsedLine = _ParsedLine.from(line);

        final Ingredient ingredient =
            await ref.read(ingredientRepositoryProvider).findOrCreate(
                  libraryId: libraryId,
                  name: parsedLine.name,
                );

        if (ingredient.isCustom) {
          created++;
        } else {
          matched++;
        }

        draft.add(DraftIngredient(
          ingredientId: ingredient.id,
          name: ingredient.name,
          quantity: parsedLine.quantity ?? 1,
          unit: parsedLine.unit ?? ingredient.defaultUnit,
          note: parsedLine.note,
        ));
      }

      ref.read(recipeFormProvider.notifier).loadFromImport(parsed, draft);
      state = ImportReady(parsed, matched, created);
    } catch (error) {
      state = ImportFailed(Failure.from(error).message);
    }
  }
}

final NotifierProvider<ImportController, ImportState> importProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);

/// Splits "2 tbsp olive oil, finely warmed" into quantity, unit, name
/// and note.
///
/// This runs on the device rather than in the Edge Function on purpose:
/// it needs the unit vocabulary, and duplicating that vocabulary across
/// two languages is how the two halves drift apart. The function's job
/// is to fetch and sanitise; interpreting is done here.
class _ParsedLine {
  const _ParsedLine({required this.name, this.quantity, this.unit, this.note});

  final String name;
  final double? quantity;
  final MeasureUnit? unit;
  final String? note;

  static final RegExp _leading = RegExp(
    r'^\s*(\d+\s+\d+\s*/\s*\d+|\d+\s*/\s*\d+|\d+(?:[.,]\d+)?)\s*',
  );

  static const Map<String, MeasureUnit> _units = <String, MeasureUnit>{
    'g': MeasureUnit.g,
    'gram': MeasureUnit.g,
    'grams': MeasureUnit.g,
    'kg': MeasureUnit.kg,
    'kilo': MeasureUnit.kg,
    'kilos': MeasureUnit.kg,
    'oz': MeasureUnit.oz,
    'ounce': MeasureUnit.oz,
    'ounces': MeasureUnit.oz,
    'lb': MeasureUnit.lb,
    'lbs': MeasureUnit.lb,
    'pound': MeasureUnit.lb,
    'ml': MeasureUnit.ml,
    'l': MeasureUnit.l,
    'litre': MeasureUnit.l,
    'liter': MeasureUnit.l,
    'tsp': MeasureUnit.tsp,
    'teaspoon': MeasureUnit.tsp,
    'teaspoons': MeasureUnit.tsp,
    'tbsp': MeasureUnit.tbsp,
    'tablespoon': MeasureUnit.tbsp,
    'tablespoons': MeasureUnit.tbsp,
    'cup': MeasureUnit.cup,
    'cups': MeasureUnit.cup,
    'clove': MeasureUnit.clove,
    'cloves': MeasureUnit.clove,
    'slice': MeasureUnit.slice,
    'slices': MeasureUnit.slice,
    'pinch': MeasureUnit.pinch,
    'bunch': MeasureUnit.bunch,
    'can': MeasureUnit.can,
    'tin': MeasureUnit.can,
    'pack': MeasureUnit.package,
    'packet': MeasureUnit.package,
  };

  static _ParsedLine from(String raw) {
    String text = raw.trim();
    double? quantity;
    MeasureUnit? unit;
    String? note;

    final int comma = text.indexOf(',');
    if (comma > 0 && comma < text.length - 1) {
      note = text.substring(comma + 1).trim();
      text = text.substring(0, comma).trim();
    }

    final RegExpMatch? amount = _leading.firstMatch(text);
    if (amount != null) {
      quantity = _toDouble(amount.group(1)!);
      text = text.substring(amount.end).trim();
    }

    final int space = text.indexOf(' ');
    if (space > 0) {
      final String candidate =
          text.substring(0, space).toLowerCase().replaceAll('.', '');
      final MeasureUnit? found = _units[candidate];
      if (found != null) {
        unit = found;
        text = text.substring(space + 1).trim();
      }
    }

    return _ParsedLine(
      name: text.isEmpty ? raw.trim() : text,
      quantity: quantity,
      unit: unit,
      note: note,
    );
  }

  static double? _toDouble(String token) {
    final String t = token.replaceAll(',', '.').trim();

    final RegExpMatch? mixed =
        RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(t);
    if (mixed != null) {
      final double d = double.parse(mixed.group(3)!);
      if (d == 0) return null;
      return double.parse(mixed.group(1)!) + double.parse(mixed.group(2)!) / d;
    }

    final RegExpMatch? frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(t);
    if (frac != null) {
      final double d = double.parse(frac.group(2)!);
      if (d == 0) return null;
      return double.parse(frac.group(1)!) / d;
    }

    return double.tryParse(t);
  }
}
