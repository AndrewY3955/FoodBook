import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import {
  cleanupUsers,
  createLibrary,
  createRecipe,
  createUser,
  expectOk,
  request,
  supabaseUrl,
} from './support.mjs';

const base = supabaseUrl.replace(/\/$/, '');
const key = process.env.SUPABASE_PUBLISHABLE_KEY;
const photoDir = process.env.PHOTO_DIR ?? join(tmpdir(), 'fb-photos');
const photo = (n, raw = false) =>
  readFileSync(join(photoDir, `photo-${n}${raw ? '' : '-web'}.jpg`));

const headers = (token, extra = {}) => ({
  apikey: key,
  Authorization: `Bearer ${token}`,
  ...extra,
});
const put = (token, path, bytes) =>
  fetch(`${base}/storage/v1/object/recipe-covers/${path}`, {
    method: 'POST',
    headers: headers(token, { 'Content-Type': 'image/jpeg', 'x-upsert': 'true' }),
    body: bytes,
  });
const get = (token, path) =>
  fetch(`${base}/storage/v1/object/authenticated/recipe-covers/${path}`, {
    headers: headers(token),
  });
const rpc = (user, name, body = {}) =>
  request(`/rpc/${name}`, { token: user.token, method: 'POST', body });
const patch = (user, id, body) =>
  request(`/recipes?id=eq.${id}`, { token: user.token, method: 'PATCH', body });

test('real-size originals exceed the bucket limit, resized ones fit', async (t) => {
  assert.ok(existsSync(photoDir), 'run make-photos.py first');
  const user = await createUser('Big Photo');
  t.after(() => cleanupUsers([user]));
  const library = await createLibrary(user);
  const recipe = await createRecipe({ user, library, title: `Big ${randomUUID().slice(0, 6)}` });
  const raw = photo(0, true);
  assert.ok(raw.length > 5 * 1024 * 1024, 'fixture is a real camera-sized photo');
  const rejected = await put(user.token, `${library.id}/${recipe.id}/cover.jpg`, raw);
  assert.ok(rejected.status >= 400, `raw photo rejected, got ${rejected.status}`);
  const ok = await put(user.token, `${library.id}/${recipe.id}/cover.jpg`, photo(0));
  assert.equal(ok.status, 200);
});

test('fork copies text, notes, cuisine, theme and every image; account deletion keeps the fork', async (t) => {
  const owner = await createUser('Source Cook');
  const reader = await createUser('Forking Cook');
  t.after(() => cleanupUsers([owner, reader]));
  const ownerLib = await createLibrary(owner);
  const readerLib = await createLibrary(reader);
  const recipe = await createRecipe({
    user: owner,
    library: ownerLib,
    title: `Source ${randomUUID().slice(0, 6)}`,
    isPublic: true,
  });

  const coverPath = `${ownerLib.id}/${recipe.id}/cover.jpg`;
  const bgPath = `${ownerLib.id}/${recipe.id}/background.jpg`;
  const photoPaths = [1, 2, 3].map((n) => `${ownerLib.id}/${recipe.id}/photo-${randomUUID()}.jpg`);
  assert.equal((await put(owner.token, coverPath, photo(0))).status, 200);
  assert.equal((await put(owner.token, bgPath, photo(1))).status, 200);
  for (const [i, p] of photoPaths.entries()) {
    assert.equal((await put(owner.token, p, photo(i + 2))).status, 200);
  }
  expectOk(
    await patch(owner, recipe.id, {
      theme: 'tomato',
      accent_color: '#AA3311',
      cuisine: 'italian',
      description: 'Nonna\'s long Sunday sauce, slow and patient.',
      cover_image_path: coverPath,
      background_image_path: bgPath,
    }),
    'style source',
  );
  expectOk(
    await request('/recipe_images', {
      token: owner.token,
      method: 'POST',
      body: photoPaths.map((storage_path, i) => ({
        recipe_id: recipe.id,
        library_id: ownerLib.id,
        storage_path,
        caption: `Step ${i + 1}`,
        sort_order: i,
      })),
    }),
    'source photos',
  );

  const forkId = expectOk(
    await rpc(reader, 'fork_recipe', { p_recipe_id: recipe.id, p_library_id: readerLib.id }),
    'fork',
  );
  const [fork] = expectOk(
    await request(`/recipes?id=eq.${forkId}&select=*`, { token: reader.token }),
    'read fork',
  );
  assert.equal(fork.theme, 'tomato');
  assert.equal(fork.accent_color, '#AA3311');
  assert.equal(fork.cuisine, 'italian');
  assert.equal(fork.description, 'Nonna\'s long Sunday sauce, slow and patient.');
  assert.equal(fork.is_public, false);

  // The client's copy step: download from the public source, upload into the fork's prefix.
  const copy = async (from, to) => {
    const dl = await get(reader.token, from);
    assert.equal(dl.status, 200, `download ${from}`);
    assert.equal((await put(reader.token, to, Buffer.from(await dl.arrayBuffer()))).status, 200);
    return to;
  };
  const forkCover = await copy(coverPath, `${readerLib.id}/${forkId}/cover.jpg`);
  const forkBg = await copy(bgPath, `${readerLib.id}/${forkId}/background.jpg`);
  expectOk(
    await patch(reader, forkId, { cover_image_path: forkCover, background_image_path: forkBg }),
    'fork paths',
  );
  const forkPhotos = [];
  for (const [i, p] of photoPaths.entries()) {
    forkPhotos.push(await copy(p, `${readerLib.id}/${forkId}/photo-${randomUUID()}.jpg`));
    expectOk(
      await request('/recipe_images', {
        token: reader.token,
        method: 'POST',
        body: { recipe_id: forkId, library_id: readerLib.id, storage_path: forkPhotos[i], caption: `Step ${i + 1}`, sort_order: i },
      }),
      'fork photo row',
    );
  }

  // Owner deletes the account.
  const paths = expectOk(await rpc(owner, 'account_storage_paths'), 'storage paths');
  assert.equal(paths.length, 5);
  assert.ok(paths.every((p) => p.startsWith(`${ownerLib.id}/`)));
  const removed = await fetch(`${base}/storage/v1/object/recipe-covers`, {
    method: 'DELETE',
    headers: headers(owner.token, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ prefixes: paths }),
  });
  assert.equal(removed.status, 200);
  expectOk(await rpc(owner, 'delete_my_account'), 'delete account');

  const gone = await request(`/recipes?id=eq.${recipe.id}&select=id`, { token: reader.token });
  assert.deepEqual(gone.body, []);
  const lib = await request(`/libraries?id=eq.${ownerLib.id}&select=id`, { token: reader.token });
  assert.deepEqual(lib.body, []);

  const [kept] = expectOk(
    await request(`/recipes?id=eq.${forkId}&select=title,theme,cuisine,forked_from_recipe_id`, { token: reader.token }),
    'fork survives',
  );
  assert.equal(kept.theme, 'tomato');
  assert.equal(kept.forked_from_recipe_id, null);
  const imgs = expectOk(
    await request(`/recipe_images?recipe_id=eq.${forkId}&select=storage_path&order=sort_order`, { token: reader.token }),
    'fork images',
  );
  assert.equal(imgs.length, 3);
  for (const p of [forkCover, forkBg, ...forkPhotos]) {
    assert.equal((await get(reader.token, p)).status, 200, `fork keeps ${p}`);
  }
});

test('title search keeps punctuation and treats LIKE characters literally', async (t) => {
  const user = await createUser('Search Cook');
  t.after(() => cleanupUsers([user]));
  const library = await createLibrary(user);
  const tag = randomUUID().slice(0, 6);
  const titles = [`St. John's Stew ${tag}`, `St John s Stew ${tag}`, `100% Beef_Chili ${tag}`, `100x BeefXChili ${tag}`];
  for (const title of titles) await createRecipe({ user, library, title });

  const search = async (term) => {
    // Mirrors PostgrestSafe.likePattern: escape \, %, _ and wrap in %.
    const esc = term.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
    const rows = expectOk(
      await request(`/recipes?select=title&title=ilike.${encodeURIComponent(`%${esc}%`)}`, { token: user.token }),
      'search',
    );
    return rows.map((r) => r.title);
  };
  assert.deepEqual(await search(`St. John's Stew ${tag}`), [titles[0]]);
  assert.deepEqual(await search(`100% Beef_Chili ${tag}`), [titles[2]]);
});
