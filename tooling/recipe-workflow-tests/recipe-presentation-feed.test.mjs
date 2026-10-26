import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';

import {
  cleanupUsers,
  createLibrary,
  createRecipe,
  createUser,
  expectOk,
  readObject,
  request,
  uploadObject,
} from './support.mjs';

const patch = (user, id, body) =>
  request(`/recipes?id=eq.${id}`, { token: user.token, method: 'PATCH', body });

test('theme, accent and cuisine persist and reject invalid values', async (t) => {
  const user = await createUser('Presentation Cook');
  t.after(() => cleanupUsers([user]));
  const library = await createLibrary(user);
  const recipe = await createRecipe({ user, library, title: `Styled ${user.id.slice(0, 8)}` });

  const ok = expectOk(
    await patch(user, recipe.id, { theme: 'tomato', accent_color: '#AA3311', cuisine: 'italian' }),
    'style recipe',
  );
  assert.equal(ok[0].theme, 'tomato');
  assert.equal(ok[0].cuisine, 'italian');

  assert.ok((await patch(user, recipe.id, { theme: 'neon' })).status >= 400);
  assert.ok((await patch(user, recipe.id, { accent_color: 'red' })).status >= 400);
  assert.ok((await patch(user, recipe.id, { cuisine: 'martian' })).status >= 400);
  assert.ok((await patch(user, recipe.id, { background_image_path: 'x/y/cover.png' })).status >= 400);
});

test('public feed shows only public recipes, filters by cuisine, and is anon-readable', async (t) => {
  const owner = await createUser('Feed Owner');
  const other = await createUser('Feed Reader');
  t.after(() => cleanupUsers([owner, other]));
  const library = await createLibrary(owner);
  const marker = owner.id.slice(0, 8);
  const pub = await createRecipe({ user: owner, library, title: `FeedPub ${marker}`, isPublic: true });
  const priv = await createRecipe({ user: owner, library, title: `FeedPriv ${marker}` });
  expectOk(await patch(owner, pub.id, { cuisine: 'thai' }), 'set cuisine');

  const q = `/recipes?select=id,cuisine&is_public=eq.true&title=ilike.*${marker}*`;
  for (const token of [undefined, other.token]) {
    const rows = expectOk(await request(q, { token }), 'feed');
    assert.deepEqual(rows.map((r) => r.id), [pub.id]);
    const thai = expectOk(await request(`${q}&cuisine=eq.thai`, { token }), 'thai feed');
    assert.equal(thai.length, 1);
    const italian = expectOk(await request(`${q}&cuisine=eq.italian`, { token }), 'italian feed');
    assert.equal(italian.length, 0);
  }
  const direct = expectOk(
    await request(`/recipes?select=id&id=eq.${priv.id}`, { token: other.token }),
    'private direct read',
  );
  assert.equal(direct.length, 0);
});

test('background and photos upload, read by visibility, and enforce ownership', async (t) => {
  const owner = await createUser('Photo Owner');
  const stranger = await createUser('Photo Stranger');
  t.after(() => cleanupUsers([owner, stranger]));
  const library = await createLibrary(owner);
  const recipe = await createRecipe({ user: owner, library, title: `Photos ${owner.id.slice(0, 8)}` });
  const base = `${library.id}/${recipe.id}`;
  const bgPath = `${base}/background.png`;
  const photoPath = `${base}/photo-${randomUUID()}.png`;

  assert.equal((await uploadObject(owner, bgPath)).status, 200);
  assert.equal((await uploadObject(owner, photoPath)).status, 200);
  assert.ok((await uploadObject(owner, `${base}/evil.png`)).status >= 400, 'bad name rejected');
  assert.ok((await uploadObject(stranger, `${base}/photo-${randomUUID()}.png`)).status >= 400,
    'stranger cannot upload');

  expectOk(await patch(owner, recipe.id, { background_image_path: bgPath }), 'set background');
  expectOk(
    await request('/recipe_images', {
      token: owner.token,
      method: 'POST',
      body: { recipe_id: recipe.id, library_id: library.id, storage_path: photoPath, caption: 'plated', sort_order: 0 },
    }),
    'register photo',
  );

  const strangerBefore = await request(`/recipe_images?select=id&recipe_id=eq.${recipe.id}`, { token: stranger.token });
  assert.deepEqual(strangerBefore.body, []);
  assert.notEqual((await readObject(stranger.token, photoPath)).status, 200);

  expectOk(await patch(owner, recipe.id, { is_public: true }), 'publish');
  const seen = expectOk(
    await request(`/recipe_images?select=storage_path,caption&recipe_id=eq.${recipe.id}`, { token: stranger.token }),
    'stranger reads photos of public recipe',
  );
  assert.equal(seen.length, 1);
  assert.equal((await readObject(stranger.token, photoPath)).status, 200);
  assert.equal((await readObject(stranger.token, bgPath)).status, 200);

  const write = await request('/recipe_images', {
    token: stranger.token,
    method: 'POST',
    body: { recipe_id: recipe.id, library_id: library.id, storage_path: `${base}/photo-${randomUUID()}.png` },
  });
  assert.ok(write.status >= 400, 'stranger cannot add photo rows');
});
