import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cookistrybook/src/data/models/enums.dart';
import 'package:cookistrybook/src/data/repositories/recipe_repository.dart';
import 'package:cookistrybook/src/state/discover_controller.dart';
import 'package:cookistrybook/src/state/recipe_controllers.dart';

void main() {
  test('addStep notifies listeners with a new draft', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    int notifications = 0;
    container.listen<RecipeDraft>(
      recipeFormProvider,
      (RecipeDraft? _, RecipeDraft __) => notifications++,
    );

    container.read(recipeFormProvider.notifier).addStep();
    container.read(recipeFormProvider.notifier).addStep('Boil water');

    expect(notifications, 2);
    expect(container.read(recipeFormProvider).steps.length, 2);
    expect(container.read(recipeFormProvider).steps.last.instruction,
        'Boil water');
  });

  test('presentation fields survive edits', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final RecipeFormController form =
        container.read(recipeFormProvider.notifier);

    form.setTheme(RecipeTheme.night);
    form.setAccentColor('#C0392B');
    form.setCuisine(Cuisine.thai);
    form.setTitle('Pad see ew');

    final RecipeDraft draft = container.read(recipeFormProvider);
    expect(draft.theme, RecipeTheme.night);
    expect(draft.accentColor, '#C0392B');
    expect(draft.cuisine, Cuisine.thai);
    expect(draft.title, 'Pad see ew');
  });

  test('changing a discovery category resets paging', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final DiscoverController discover =
        container.read(discoverFilterProvider.notifier);

    discover.loadMore();
    expect(container.read(discoverFilterProvider).limit,
        DiscoverFilter.pageSize * 2);

    discover.setCuisine(Cuisine.italian);
    final DiscoverFilter filter = container.read(discoverFilterProvider);
    expect(filter.limit, DiscoverFilter.pageSize);
    expect(filter.cuisine, Cuisine.italian);
    expect(filter.isActive, isTrue);

    discover.setMealType(MealType.dessert);
    expect(container.read(discoverFilterProvider).cuisine, Cuisine.italian);
  });
}
