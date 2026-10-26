import 'enums.dart';

/// Immutable row types.
///
/// Decoding is defensive: `_str`, `_num` and friends never throw on a
/// missing or wrong-typed field. A single malformed row should degrade
/// one card, not take down the list that contains it.

String _str(Object? v, [String fallback = '']) =>
    v is String ? v : (v == null ? fallback : v.toString());

String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

double _dbl(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool _bool(Object? v, [bool fallback = false]) =>
    v is bool ? v : (v is String ? v == 'true' : fallback);

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

class Profile {
  const Profile({required this.id, required this.displayName, this.avatarPath});

  final String id;
  final String displayName;
  final String? avatarPath;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: _str(json['id']),
        displayName: _str(json['display_name'], 'Cook'),
        avatarPath: _strOrNull(json['avatar_path']),
      );
}

class Library {
  const Library({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final MemberRole role;

  /// Decoded from the membership query, which embeds the library:
  /// select member_role, libraries(id, name)
  factory Library.fromMembershipJson(Map<String, dynamic> json) {
    final Object? embedded = json['libraries'];
    final Map<String, dynamic> library =
        embedded is Map<String, dynamic> ? embedded : const <String, dynamic>{};
    return Library(
      id: _str(library['id']),
      name: _str(library['name'], 'Cookbook'),
      role: MemberRole.fromWire(_strOrNull(json['member_role'])),
    );
  }
}

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultUnit,
    this.libraryId,
  });

  final String id;
  final String name;
  final GroceryCategory category;
  final MeasureUnit defaultUnit;

  /// Null for the shared catalog, set for a library's own additions.
  final String? libraryId;

  bool get isCustom => libraryId != null;

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        id: _str(json['id']),
        name: _str(json['name']),
        category:
            GroceryCategory.fromWire(_strOrNull(json['grocery_category'])),
        defaultUnit: MeasureUnit.fromWire(_strOrNull(json['default_unit'])),
        libraryId: _strOrNull(json['library_id']),
      );
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.ingredientId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.note,
    this.isOptional = false,
    this.sortOrder = 0,
  });

  final String id;
  final String ingredientId;
  final String name;
  final double quantity;
  final MeasureUnit unit;
  final GroceryCategory category;
  final String? note;
  final bool isOptional;
  final int sortOrder;

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    final Object? embedded = json['ingredients'];
    final Map<String, dynamic> ing =
        embedded is Map<String, dynamic> ? embedded : const <String, dynamic>{};
    return RecipeIngredient(
      id: _str(json['id']),
      ingredientId: _str(json['ingredient_id']),
      name: _str(ing['name'], 'Ingredient'),
      quantity: _dbl(json['quantity'], 1),
      unit: MeasureUnit.fromWire(_strOrNull(json['unit'])),
      category: GroceryCategory.fromWire(_strOrNull(ing['grocery_category'])),
      note: _strOrNull(json['note']),
      isOptional: _bool(json['is_optional']),
      sortOrder: _int(json['sort_order']),
    );
  }

  RecipeIngredient copyWith({double? quantity}) => RecipeIngredient(
        id: id,
        ingredientId: ingredientId,
        name: name,
        quantity: quantity ?? this.quantity,
        unit: unit,
        category: category,
        note: note,
        isOptional: isOptional,
        sortOrder: sortOrder,
      );
}

class RecipeStep {
  const RecipeStep({
    required this.id,
    required this.stepNumber,
    required this.instruction,
    this.timerSeconds,
  });

  final String id;
  final int stepNumber;
  final String instruction;
  final int? timerSeconds;

  bool get hasTimer => timerSeconds != null && timerSeconds! > 0;

  Duration get timer => Duration(seconds: timerSeconds ?? 0);

  factory RecipeStep.fromJson(Map<String, dynamic> json) => RecipeStep(
        id: _str(json['id']),
        stepNumber: _int(json['step_number'], 1),
        instruction: _str(json['instruction']),
        timerSeconds: _intOrNull(json['timer_seconds']),
      );
}

class RecipeImage {
  const RecipeImage({
    required this.id,
    required this.storagePath,
    this.caption,
    this.sortOrder = 0,
  });

  final String id;
  final String storagePath;
  final String? caption;
  final int sortOrder;

  factory RecipeImage.fromJson(Map<String, dynamic> json) => RecipeImage(
        id: _str(json['id']),
        storagePath: _str(json['storage_path']),
        caption: _strOrNull(json['caption']),
        sortOrder: _int(json['sort_order'], 0),
      );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.libraryId,
    required this.title,
    required this.mealType,
    required this.season,
    required this.baseServings,
    required this.isPublic,
    required this.importSource,
    this.description,
    this.prepMinutes,
    this.cookMinutes,
    this.coverImagePath,
    this.sourceUrl,
    this.externalVideoUrl,
    this.forkedFromRecipeId,
    this.ingredients = const <RecipeIngredient>[],
    this.steps = const <RecipeStep>[],
    this.tags = const <String>[],
    this.createdAt,
    this.cuisine,
    this.theme = RecipeTheme.plain,
    this.accentColor,
    this.backgroundImagePath,
    this.images = const <RecipeImage>[],
  });

  final Cuisine? cuisine;
  final RecipeTheme theme;

  /// `#RRGGBB`, validated by the database.
  final String? accentColor;
  final String? backgroundImagePath;
  final List<RecipeImage> images;

  final String id;
  final String libraryId;
  final String title;
  final String? description;
  final MealType mealType;
  final Season season;
  final int baseServings;
  final int? prepMinutes;
  final int? cookMinutes;
  final String? coverImagePath;
  final String? sourceUrl;
  final String? externalVideoUrl;
  final ImportSource importSource;
  final bool isPublic;
  final String? forkedFromRecipeId;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;
  final List<String> tags;
  final DateTime? createdAt;

  bool get isFork => forkedFromRecipeId != null;

  int? get totalMinutes {
    if (prepMinutes == null && cookMinutes == null) return null;
    return (prepMinutes ?? 0) + (cookMinutes ?? 0);
  }

  List<RecipeIngredient> get sortedIngredients {
    final List<RecipeIngredient> copy = List<RecipeIngredient>.of(ingredients);
    copy.sort((RecipeIngredient a, RecipeIngredient b) {
      final int byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });
    return copy;
  }

  List<RecipeStep> get sortedSteps {
    final List<RecipeStep> copy = List<RecipeStep>.of(steps);
    copy.sort(
        (RecipeStep a, RecipeStep b) => a.stepNumber.compareTo(b.stepNumber));
    return copy;
  }

  factory Recipe.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(Object? raw, T Function(Map<String, dynamic>) decode) {
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map<T>(decode)
          .toList(growable: false);
    }

    final Object? rawTags = json['recipe_tags'];
    final List<String> tagNames = rawTags is List
        ? rawTags
            .whereType<Map<String, dynamic>>()
            .map<String>((Map<String, dynamic> t) {
              final Object? tag = t['tags'];
              return tag is Map<String, dynamic> ? _str(tag['name']) : '';
            })
            .where((String s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return Recipe(
      id: _str(json['id']),
      libraryId: _str(json['library_id']),
      title: _str(json['title'], 'Untitled'),
      description: _strOrNull(json['description']),
      mealType: MealType.fromWire(_strOrNull(json['meal_type'])),
      season: Season.fromWire(_strOrNull(json['season'])),
      baseServings: _int(json['base_servings'], 4),
      prepMinutes: _intOrNull(json['prep_minutes']),
      cookMinutes: _intOrNull(json['cook_minutes']),
      coverImagePath: _strOrNull(json['cover_image_path']),
      sourceUrl: _strOrNull(json['source_url']),
      externalVideoUrl: _strOrNull(json['external_video_url']),
      importSource: ImportSource.fromWire(_strOrNull(json['import_source'])),
      isPublic: _bool(json['is_public']),
      forkedFromRecipeId: _strOrNull(json['forked_from_recipe_id']),
      ingredients: listOf<RecipeIngredient>(
          json['recipe_ingredients'], RecipeIngredient.fromJson),
      steps: listOf<RecipeStep>(json['recipe_steps'], RecipeStep.fromJson),
      tags: tagNames,
      createdAt: _date(json['created_at']),
      cuisine: Cuisine.fromWire(_strOrNull(json['cuisine'])),
      theme: RecipeTheme.fromWire(_strOrNull(json['theme'])),
      accentColor: _strOrNull(json['accent_color']),
      backgroundImagePath: _strOrNull(json['background_image_path']),
      images: (listOf<RecipeImage>(json['recipe_images'], RecipeImage.fromJson)
            ..sort((RecipeImage a, RecipeImage b) =>
                a.sortOrder.compareTo(b.sortOrder)))
          .toList(growable: false),
    );
  }
}

class PantryItem {
  const PantryItem({
    required this.id,
    required this.ingredientId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
  });

  final String id;
  final String ingredientId;
  final String name;
  final GroceryCategory category;
  final double quantity;
  final MeasureUnit unit;

  factory PantryItem.fromJson(Map<String, dynamic> json) {
    final Object? embedded = json['ingredients'];
    final Map<String, dynamic> ing =
        embedded is Map<String, dynamic> ? embedded : const <String, dynamic>{};
    return PantryItem(
      id: _str(json['id']),
      ingredientId: _str(json['ingredient_id']),
      name: _str(ing['name'], 'Ingredient'),
      category: GroceryCategory.fromWire(_strOrNull(ing['grocery_category'])),
      quantity: _dbl(json['quantity'], 1),
      unit: MeasureUnit.fromWire(_strOrNull(json['unit'])),
    );
  }
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.label,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.isChecked,
    this.ingredientId,
  });

  final String id;
  final String label;
  final GroceryCategory category;
  final double quantity;
  final MeasureUnit unit;
  final bool isChecked;
  final String? ingredientId;

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    final Object? embedded = json['ingredients'];
    final Map<String, dynamic> ing =
        embedded is Map<String, dynamic> ? embedded : const <String, dynamic>{};
    final String label =
        _strOrNull(ing['name']) ?? _strOrNull(json['custom_name']) ?? 'Item';
    return ShoppingItem(
      id: _str(json['id']),
      label: label,
      category: GroceryCategory.fromWire(_strOrNull(json['grocery_category'])),
      quantity: _dbl(json['quantity'], 1),
      unit: MeasureUnit.fromWire(_strOrNull(json['unit'])),
      isChecked: _bool(json['is_checked']),
      ingredientId: _strOrNull(json['ingredient_id']),
    );
  }

  ShoppingItem copyWith({bool? isChecked, double? quantity}) => ShoppingItem(
        id: id,
        label: label,
        category: category,
        quantity: quantity ?? this.quantity,
        unit: unit,
        isChecked: isChecked ?? this.isChecked,
        ingredientId: ingredientId,
      );
}

class MealPlanEntry {
  const MealPlanEntry({
    required this.id,
    required this.recipeId,
    required this.recipeTitle,
    required this.planDate,
    required this.mealType,
    this.servingsOverride,
    this.note,
    this.coverImagePath,
  });

  final String id;
  final String recipeId;
  final String recipeTitle;
  final DateTime planDate;
  final MealType mealType;
  final int? servingsOverride;
  final String? note;
  final String? coverImagePath;

  factory MealPlanEntry.fromJson(Map<String, dynamic> json) {
    final Object? embedded = json['recipes'];
    final Map<String, dynamic> recipe =
        embedded is Map<String, dynamic> ? embedded : const <String, dynamic>{};
    return MealPlanEntry(
      id: _str(json['id']),
      recipeId: _str(json['recipe_id']),
      recipeTitle: _str(recipe['title'], 'Recipe'),
      planDate: _date(json['plan_date']) ?? DateTime.now(),
      mealType: MealType.fromWire(_strOrNull(json['meal_type'])),
      servingsOverride: _intOrNull(json['servings_override']),
      note: _strOrNull(json['note']),
      coverImagePath: _strOrNull(recipe['cover_image_path']),
    );
  }
}

/// A row from the public.pantry_match() function.
class PantryMatch {
  const PantryMatch({
    required this.recipeId,
    required this.title,
    required this.mealType,
    required this.season,
    required this.requiredCount,
    required this.matchedCount,
    required this.matchPct,
  });

  final String recipeId;
  final String title;
  final MealType mealType;
  final Season season;
  final int requiredCount;
  final int matchedCount;
  final int matchPct;

  int get missingCount => requiredCount - matchedCount;

  bool get isCookable => missingCount == 0;

  factory PantryMatch.fromJson(Map<String, dynamic> json) => PantryMatch(
        recipeId: _str(json['recipe_id']),
        title: _str(json['title'], 'Recipe'),
        mealType: MealType.fromWire(_strOrNull(json['meal_type'])),
        season: Season.fromWire(_strOrNull(json['season'])),
        requiredCount: _int(json['required_count']),
        matchedCount: _int(json['matched_count']),
        matchPct: _int(json['match_pct']),
      );
}

/// The structured result the Edge Function returns for an imported URL.
class ParsedImport {
  const ParsedImport({
    required this.title,
    required this.ingredientLines,
    required this.stepLines,
    required this.sourceUrl,
    required this.source,
    this.description,
    this.servings,
  });

  final String title;
  final List<String> ingredientLines;
  final List<String> stepLines;
  final String sourceUrl;
  final ImportSource source;
  final String? description;
  final int? servings;

  bool get isEmpty => ingredientLines.isEmpty && stepLines.isEmpty;

  factory ParsedImport.fromJson(Map<String, dynamic> json) {
    List<String> lines(Object? raw) => raw is List
        ? raw
            .whereType<String>()
            .where((String s) => s.trim().isNotEmpty)
            .toList()
        : <String>[];
    return ParsedImport(
      title: _str(json['title'], 'Imported recipe'),
      description: _strOrNull(json['description']),
      ingredientLines: lines(json['ingredients']),
      stepLines: lines(json['steps']),
      sourceUrl: _str(json['source_url']),
      source: ImportSource.fromWire(_strOrNull(json['source'])),
      servings: _intOrNull(json['servings']),
    );
  }
}
