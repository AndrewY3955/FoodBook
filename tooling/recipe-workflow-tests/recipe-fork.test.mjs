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

test('a guest forks a public recipe into their library as private content', async (t) => {
  const owner = await createUser('Fork Source Owner');
  const guest = await createUser('Fork Destination Guest');
  t.after(() => cleanupUsers([owner, guest]));
  const sourceLibrary = await createLibrary(owner);
  const destinationLibrary = await createLibrary(guest);
  const marker = owner.id.slice(0, 8);
  const source = await createRecipe({
    user: owner,
    library: sourceLibrary,
    title: `ForkFlow ${marker}`,
    isPublic: true,
  });

  const response = await request('/rpc/fork_recipe', {
    token: guest.token,
    method: 'POST',
    body: {
      p_recipe_id: source.id,
      p_library_id: destinationLibrary.id,
    },
  });
  const forkId = expectOk(response, 'fork public recipe');
  assert.match(forkId, /^[0-9a-f-]{36}$/i);

  const fork = expectOk(
    await request(
      `/recipes?select=id,title,library_id,is_public,forked_from_recipe_id,recipe_ingredients(id),recipe_steps(id)&id=eq.${forkId}`,
      { token: guest.token },
    ),
    'read forked recipe',
  );
  assert.equal(fork.length, 1);
  assert.equal(fork[0].library_id, destinationLibrary.id);
  assert.equal(fork[0].title, `ForkFlow ${marker} (fork)`);
  assert.equal(fork[0].is_public, false);
  assert.equal(fork[0].forked_from_recipe_id, source.id);
  assert.equal(fork[0].recipe_ingredients.length, 2);
  assert.equal(fork[0].recipe_steps.length, 2);

  const anonymousFork = await request('/rpc/fork_recipe', {
    method: 'POST',
    body: {
      p_recipe_id: source.id,
      p_library_id: destinationLibrary.id,
    },
  });
  assert.ok([401, 403].includes(anonymousFork.status));
});
