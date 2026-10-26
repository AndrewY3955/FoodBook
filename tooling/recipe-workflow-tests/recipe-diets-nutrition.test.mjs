import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  cleanupUsers,
  createLibrary,
  createRecipe,
  createUser,
  expectOk,
  request,
} from './support.mjs';

const patch = (user, id, body) =>
  request(`/recipes?id=eq.${id}`, { token: user.token, method: 'PATCH', body });

test('diets and nutrition save, filter, fork and reject bad values', async (t) => {
  const owner = await createUser('Diet Owner');
  const guest = await createUser('Diet Guest');
  t.after(() => cleanupUsers([owner, guest]));
  const lib = await createLibrary(owner);
  const guestLib = await createLibrary(guest);
  const recipe = await createRecipe({
    user: owner,
    library: lib,
    title: `Diet ${owner.id.slice(0, 6)}`,
    isPublic: true,
  });

  const ok = await patch(owner, recipe.id, {
    diets: ['high_protein', 'gluten_free'],
    calories: 420,
    protein_g: 38.5,
    sodium_mg: 610,
  });
  assert.ok(ok.status < 300, `valid update, got ${ok.status}`);

  // Anyone can filter the public feed on a diet.
  const hit = expectOk(
    await request(
      `/recipes?select=id,diets,calories,protein_g&is_public=eq.true&diets=cs.%7Bhigh_protein%7D&id=eq.${recipe.id}`,
      { token: guest.token },
    ),
    'diet filter',
  );
  assert.equal(hit.length, 1);
  assert.equal(hit[0].calories, 420);
  assert.equal(Number(hit[0].protein_g), 38.5);

  const miss = expectOk(
    await request(
      `/recipes?select=id&diets=cs.%7Bvegan%7D&id=eq.${recipe.id}`,
      { token: guest.token },
    ),
    'non-matching diet filter',
  );
  assert.equal(miss.length, 0);

  // The fork carries the diet labels and nutrition.
  const forkId = expectOk(
    await request('/rpc/fork_recipe', {
      token: guest.token,
      method: 'POST',
      body: { p_recipe_id: recipe.id, p_library_id: guestLib.id },
    }),
    'fork',
  );
  const fork = expectOk(
    await request(`/recipes?select=diets,calories,protein_g,sodium_mg&id=eq.${forkId}`, {
      token: guest.token,
    }),
    'read fork',
  );
  assert.deepEqual([...fork[0].diets].sort(), ['gluten_free', 'high_protein']);
  assert.equal(fork[0].calories, 420);
  assert.equal(fork[0].sodium_mg, 610);

  // The database rejects values outside the closed list and ranges.
  for (const bad of [
    { diets: ['carnivore'] },
    { diets: Array(17).fill('vegan') },
    { calories: -1 },
    { calories: 999999 },
    { protein_g: 9999 },
    { sodium_mg: 99999 },
  ]) {
    const res = await patch(owner, recipe.id, bad);
    assert.ok(res.status >= 400, `${JSON.stringify(bad).slice(0, 40)} rejected, got ${res.status}`);
  }

  // A non-member cannot change them.
  await patch(guest, recipe.id, { calories: 1 });
  const after = expectOk(
    await request(`/recipes?select=calories&id=eq.${recipe.id}`, { token: owner.token }),
    'reread',
  );
  assert.equal(after[0].calories, 420);
});
