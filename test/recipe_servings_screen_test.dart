import 'package:cookistrybook/src/data/models/enums.dart';
import 'package:cookistrybook/src/data/models/models.dart';
import 'package:cookistrybook/src/state/library_controller.dart';
import 'package:cookistrybook/src/state/recipe_controllers.dart';
import 'package:cookistrybook/src/ui/screens/recipe_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('serving controls scale amounts embedded in ingredient names',
      (WidgetTester tester) async {
    const Recipe recipe = Recipe(
      id: 'recipe-1',
      libraryId: 'library-1',
      title: 'Test recipe',
      mealType: MealType.dinner,
      season: Season.allYear,
      baseServings: 4,
      isPublic: false,
      importSource: ImportSource.manual,
      ingredients: <RecipeIngredient>[
        RecipeIngredient(
          id: 'line-1',
          ingredientId: 'ingredient-1',
          name: '1 cup plain yogurt',
          quantity: 1,
          unit: MeasureUnit.unit,
          category: GroceryCategory.dairy,
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        recipeDetailProvider(recipe.id).overrideWith((ref) async => recipe),
        activeLibraryIdProvider.overrideWith((ref) => 'library-1'),
      ],
      child: const MaterialApp(home: RecipeDetailScreen(recipeId: 'recipe-1')),
    ));
    await tester.pumpAndSettle();

    Finder amount(String text) => find.textContaining(text, findRichText: true);
    expect(amount('1  cup plain yogurt'), findsOneWidget);

    await tester.tap(find.byTooltip('Fewer servings'));
    await tester.pumpAndSettle();
    expect(amount('3/4  cup plain yogurt'), findsOneWidget);

    await tester.tap(find.byTooltip('More servings'));
    await tester.tap(find.byTooltip('More servings'));
    await tester.pumpAndSettle();
    expect(amount('1 1/4  cup plain yogurt'), findsOneWidget);
  });
}
