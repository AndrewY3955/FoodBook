import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  cleanupUsers,
  createLibrary,
  createRecipe,
  createUser,
  expectOk,
  recipeQuery,
  request,
} from './support.mjs';

test('a member saves a private recipe, searches it, and reads it back', async (t) => {
  const user = await createUser('Recipe Search Tester');
  t.after(() => cleanupUsers([user]));
  const library = await createLibrary(user);
  const marker = user.id.slice(0, 8);
  const recipe = await createRecipe({
    user,
    library,
    title: `SearchFlow ${marker} Garlic Skillet`,
  });

  const found = expectOk(
    await request(
      recipeQuery({
        libraryId: library.id,
        titlePattern: `SearchFlow ${marker}`,
      }),
      { token: user.token },
    ),
    'search recipe by title',
  );
  assert.deepEqual(found.map((row) => row.id), [recipe.id]);

  const readBack = expectOk(
    await request(
      `/recipes?select=id,title,recipe_ingredients(ingredient_id,quantity,unit),recipe_steps(step_number,instruction)&id=eq.${recipe.id}`,
      { token: user.token },
    ),
    'read saved recipe',
  );
  assert.equal(readBack[0].recipe_ingredients.length, 2);
  assert.equal(readBack[0].recipe_steps.length, 2);

  const anonymousRead = await request(`/recipes?select=id&id=eq.${recipe.id}`);
  assert.deepEqual(expectOk(anonymousRead, 'anonymous private read'), []);

  const anonymousWrite = await request('/recipes', {
    method: 'POST',
    body: {
      library_id: library.id,
      title: `Unauthenticated ${marker}`,
      meal_type: 'dinner',
      season: 'all_year',
    },
  });
  assert.ok([401, 403].includes(anonymousWrite.status));
});
