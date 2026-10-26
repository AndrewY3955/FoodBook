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

test('a second user and anonymous visitor see public but not private recipes', async (t) => {
  const owner = await createUser('Sharing Owner');
  const guest = await createUser('Sharing Guest');
  t.after(() => cleanupUsers([owner, guest]));
  const ownerLibrary = await createLibrary(owner);
  await createLibrary(guest);
  const marker = owner.id.slice(0, 8);
  const publicRecipe = await createRecipe({
    user: owner,
    library: ownerLibrary,
    title: `PublicFlow ${marker}`,
    isPublic: true,
  });
  const privateRecipe = await createRecipe({
    user: owner,
    library: ownerLibrary,
    title: `PrivateFlow ${marker}`,
  });
  const ids = [publicRecipe.id, privateRecipe.id];

  const guestRows = expectOk(
    await request(recipeQuery({ ids }), { token: guest.token }),
    'guest recipe lookup',
  );
  assert.deepEqual(guestRows.map((row) => row.id), [publicRecipe.id]);

  const anonymousRows = expectOk(
    await request(recipeQuery({ ids })),
    'anonymous recipe lookup',
  );
  assert.deepEqual(anonymousRows.map((row) => row.id), [publicRecipe.id]);

  const publicSteps = expectOk(
    await request(
      `/recipe_steps?select=step_number&recipe_id=eq.${publicRecipe.id}`,
      { token: guest.token },
    ),
    'read public recipe steps',
  );
  const privateSteps = expectOk(
    await request(
      `/recipe_steps?select=step_number&recipe_id=eq.${privateRecipe.id}`,
      { token: guest.token },
    ),
    'attempt to read private recipe steps',
  );
  assert.equal(publicSteps.length, 2);
  assert.deepEqual(privateSteps, []);

  const unauthorizedUpdate = await request(
    `/recipes?id=eq.${publicRecipe.id}`,
    {
      token: guest.token,
      method: 'PATCH',
      body: { title: `Tampered ${marker}` },
    },
  );
  assert.ok(
    unauthorizedUpdate.status >= 200 && unauthorizedUpdate.status < 300,
  );
  const unchanged = expectOk(
    await request(`/recipes?select=title&id=eq.${publicRecipe.id}`, {
      token: owner.token,
    }),
    'verify owner data was not changed',
  );
  assert.equal(unchanged[0].title, `PublicFlow ${marker}`);
});
