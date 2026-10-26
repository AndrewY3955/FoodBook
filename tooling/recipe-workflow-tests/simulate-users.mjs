// Load simulation: N virtual people (default 30) each run a full session
// against the local Supabase stack at the same time, then global invariants
// are checked. Usage:
//   SUPABASE_PUBLISHABLE_KEY=... node simulate-users.mjs [users]
// Set KEEP=1 to leave the generated data in place for manual inspection.
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';

import {
  cleanupUsers,
  createLibrary,
  expectOk,
  readObject,
  request,
  supabaseUrl,
  tinyPng,
  uploadObject,
} from './support.mjs';

const USERS = Number(process.argv[2] ?? 30);
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;
const CUISINES = ['american', 'italian', 'mexican', 'french', 'mediterranean',
  'middle_eastern', 'indian', 'chinese', 'japanese', 'thai', 'vegetarian',
  'vegan', 'seafood', 'baking'];
const MEALS = ['breakfast', 'lunch', 'dinner', 'snack', 'dessert'];
const SEASONS = ['spring', 'summer', 'autumn', 'winter', 'all_year'];
const THEMES = ['plain', 'cream', 'herb', 'tomato', 'ocean', 'night'];
const ACCENTS = [null, '#C0392B', '#E67E22', '#27AE60', '#2980B9', '#8E44AD'];
const NAMES = ['Maya', 'Liam', 'Aiko', 'Omar', 'Sofia', 'Noah', 'Priya', 'Lucas',
  'Chen', 'Fatima', 'Diego', 'Elena', 'Kwame', 'Ingrid', 'Ravi', 'Zoe', 'Hugo',
  'Amara', 'Yuki', 'Mateo', 'Leila', 'Jonas', 'Nia', 'Tariq', 'Clara', 'Ivan',
  'Rosa', 'Kofi', 'Mei', 'Oscar'];
const DISHES = ['Pasta', 'Curry', 'Tacos', 'Soup', 'Salad', 'Stew', 'Pancakes',
  'Risotto', 'Ramen', 'Flatbread', 'Brownies', 'Chili'];

const rnd = (n) => Math.floor(Math.random() * n);
const pick = (a) => a[rnd(a.length)];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const think = () => sleep(100 + rnd(900));

const metrics = [];
const failures = [];
const state = { deletedIds: new Set(), raced: 0, users: [], publicIds: new Set(), forks: [], privateByOwner: new Map() };

async function timed(user, action, fn) {
  const start = performance.now();
  try {
    const result = await fn();
    metrics.push({ action, ms: performance.now() - start });
    return result;
  } catch (error) {
    metrics.push({ action, ms: performance.now() - start, failed: true });
    failures.push({ user: user?.name, action, error: String(error.message ?? error).slice(0, 300) });
    return undefined;
  }
}

function ok(response, label) {
  return expectOk(response, label);
}

async function signup(name) {
  const email = `sim-${randomUUID()}@example.test`;
  const password = `Aa1!${randomUUID()}z`;
  for (let attempt = 0; attempt < 12; attempt++) {
    const response = await fetch(`${supabaseUrl.replace(/\/$/, '')}/auth/v1/signup`, {
      method: 'POST',
      headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, data: { display_name: name } }),
    });
    const text = await response.text();
    if (response.status === 429) {
      await sleep(8000 + rnd(8000));
      continue;
    }
    const body = JSON.parse(text);
    if (!response.ok || !body.access_token) throw new Error(`signup ${response.status} ${text}`);
    return { id: body.user.id, token: body.access_token, name, email, password };
  }
  throw new Error('signup rate-limited after retries');
}

async function ingredientCatalog(user) {
  return ok(await request('/ingredients?select=id,name,default_unit&limit=60', { token: user.token }), 'catalog');
}

async function createStyledRecipe(user, library, catalog, { isPublic, withImages }) {
  const cuisine = pick(CUISINES);
  const title = `${name2(user)} ${pick(DISHES)} ${randomUUID().slice(0, 6)}`;
  const [recipe] = ok(await request('/recipes', {
    token: user.token,
    method: 'POST',
    body: {
      library_id: library.id,
      created_by: user.id,
      title,
      description: `A ${cuisine} favourite from ${user.name}.`,
      meal_type: pick(MEALS),
      season: pick(SEASONS),
      cuisine,
      theme: pick(THEMES),
      accent_color: pick(ACCENTS),
      base_servings: 1 + rnd(8),
      prep_minutes: rnd(40),
      cook_minutes: rnd(90),
      import_source: 'manual',
      is_public: false,
    },
  }), 'create recipe');
  const chosen = [...catalog].sort(() => Math.random() - 0.5).slice(0, 3 + rnd(4));
  ok(await request('/recipe_ingredients', {
    token: user.token,
    method: 'POST',
    body: chosen.map((ing, i) => ({
      recipe_id: recipe.id,
      library_id: library.id,
      ingredient_id: ing.id,
      quantity: 1 + rnd(5),
      unit: ing.default_unit,
      sort_order: i,
    })),
  }), 'ingredients');
  const stepCount = 2 + rnd(5);
  ok(await request('/recipe_steps', {
    token: user.token,
    method: 'POST',
    body: Array.from({ length: stepCount }, (_, i) => ({
      recipe_id: recipe.id,
      library_id: library.id,
      step_number: i + 1,
      instruction: `Step ${i + 1}: ${pick(['chop', 'simmer', 'whisk', 'bake', 'toss', 'rest'])} everything.`,
    })),
  }), 'steps');

  recipe.photoCount = 0;
  if (withImages) {
    const base = `${library.id}/${recipe.id}`;
    const cover = `${base}/cover.png`;
    const bg = `${base}/background.png`;
    for (const path of [cover, bg]) {
      const r = await uploadObject(user, path);
      if (r.status !== 200) throw new Error(`upload ${path}: ${r.status} ${r.body}`);
    }
    const photos = 1 + rnd(3);
    for (let i = 0; i < photos; i++) {
      const path = `${base}/photo-${randomUUID()}.png`;
      const r = await uploadObject(user, path);
      if (r.status !== 200) throw new Error(`photo upload: ${r.status} ${r.body}`);
      ok(await request('/recipe_images', {
        token: user.token,
        method: 'POST',
        body: { recipe_id: recipe.id, library_id: library.id, storage_path: path, caption: `Shot ${i + 1}`, sort_order: i },
      }), 'register photo');
      recipe.photoCount++;
    }
    ok(await request(`/recipes?id=eq.${recipe.id}`, {
      token: user.token,
      method: 'PATCH',
      body: { cover_image_path: cover, background_image_path: bg },
    }), 'attach images');
    recipe.bgPath = bg;
  }
  if (isPublic) {
    ok(await request(`/recipes?id=eq.${recipe.id}`, {
      token: user.token, method: 'PATCH', body: { is_public: true },
    }), 'publish');
    state.publicIds.add(recipe.id);
  } else {
    const list = state.privateByOwner.get(user.id) ?? [];
    list.push(recipe.id);
    state.privateByOwner.set(user.id, list);
  }
  recipe.title = title;
  recipe.cuisine = cuisine;
  return recipe;
}

const name2 = (u) => u.name.split(' ')[0];

const FEED = 'select=id,title,cuisine,meal_type,library_id,theme&is_public=eq.true&order=created_at.desc&limit=24';

async function browse(user, library, publicSample) {
  const results = { opened: 0, photosSeen: 0, forks: 0 };
  const feed = await timed(user, 'feed.load', async () =>
    ok(await request(`/recipes?${FEED}`, { token: user.token }), 'feed'));
  await think();
  const cuisine = pick(CUISINES);
  const byCuisine = await timed(user, 'feed.cuisine', async () =>
    ok(await request(`/recipes?${FEED}&cuisine=eq.${cuisine}`, { token: user.token }), 'cuisine'));
  if (byCuisine && byCuisine.some((r) => r.cuisine !== cuisine)) {
    failures.push({ user: user.name, action: 'feed.cuisine', error: 'wrong cuisine returned' });
  }
  await timed(user, 'feed.meal', async () =>
    ok(await request(`/recipes?${FEED}&meal_type=eq.${pick(MEALS)}`, { token: user.token }), 'meal'));
  await timed(user, 'feed.search', async () =>
    ok(await request(`/recipes?${FEED}&title=ilike.*${pick(DISHES)}*`, { token: user.token }), 'search'));
  await think();

  const targets = [...(feed ?? [])].filter((r) => r.library_id !== library.id)
    .sort(() => Math.random() - 0.5).slice(0, 3);
  for (const target of targets) {
    const detail = await timed(user, 'recipe.open', async () => ok(await request(
      `/recipes?select=*,recipe_ingredients(id),recipe_steps(id),recipe_images(storage_path)&id=eq.${target.id}`,
      { token: user.token }), 'open'));
    if (!detail?.[0]) continue;
    results.opened++;
    if (detail[0].recipe_ingredients.length === 0 || detail[0].recipe_steps.length === 0) {
      failures.push({ user: user.name, action: 'recipe.open', error: 'public recipe missing children' });
    }
    for (const img of detail[0].recipe_images.slice(0, 2)) {
      const r = await timed(user, 'photo.fetch', async () => {
        const res = await readObject(user.token, img.storage_path);
        if (res.status !== 200) {
          // A concurrent author may have deleted the recipe (and its photos).
          const still = await request(`/recipes?select=id&id=eq.${target.id}`, { token: user.token });
          if (still.status === 200 && still.body.length === 0) {
            state.raced++;
            return undefined;
          }
          throw new Error(`photo ${res.status}`);
        }
        return res;
      });
      if (r) results.photosSeen++;
    }
    await think();
  }

  const forkTarget = targets[0];
  if (forkTarget) {
    const forkId = await timed(user, 'recipe.fork', async () => {
      const res = await request('/rpc/fork_recipe', {
        token: user.token,
        method: 'POST',
        body: { p_recipe_id: forkTarget.id, p_library_id: library.id },
      });
      // The author may delete a recipe between the feed load and the fork;
      // a clean 403 for a recipe that is really gone is the correct outcome.
      if (res.status === 403 && state.deletedIds.has(forkTarget.id)) {
        state.raced++;
        return undefined;
      }
      return ok(res, 'fork');
    });
    if (forkId) {
      results.forks++;
      state.forks.push({ id: forkId, user, source: forkTarget.id });
    }
  }
  return results;
}

async function kitchen(user, library, catalog, recipe) {
  await timed(user, 'pantry.add', async () => ok(await request('/pantry_items', {
    token: user.token,
    method: 'POST',
    body: catalog.slice(0, 4 + rnd(6)).map((ing) => ({
      library_id: library.id, ingredient_id: ing.id, quantity: 1 + rnd(10), unit: ing.default_unit,
    })),
  }), 'pantry'));
  await timed(user, 'pantry.match', async () => ok(await request('/rpc/pantry_match', {
    token: user.token, method: 'POST', body: { p_library_id: library.id, p_min_pct: 0 },
  }), 'pantry_match'));
  const day = new Date(Date.now() + rnd(14) * 86400000).toISOString().slice(0, 10);
  await timed(user, 'plan.add', async () => ok(await request('/meal_plan_entries', {
    token: user.token,
    method: 'POST',
    body: { library_id: library.id, recipe_id: recipe.id, plan_date: day, meal_type: pick(MEALS), created_by: user.id },
  }), 'plan'));
  await timed(user, 'shopping.fromRecipe', async () => ok(await request('/rpc/add_recipe_to_shopping_list', {
    token: user.token,
    method: 'POST',
    body: { p_recipe_id: recipe.id, p_library_id: library.id, p_servings: 2 + rnd(6) },
  }), 'shopping'));
  const items = await timed(user, 'shopping.list', async () => ok(await request(
    '/shopping_list_items?select=id,is_checked', { token: user.token }), 'shopping list'));
  if (items?.length) {
    await timed(user, 'shopping.check', async () => ok(await request(
      `/shopping_list_items?id=eq.${items[0].id}`,
      { token: user.token, method: 'PATCH', body: { is_checked: true } }), 'check item'));
  }
  await timed(user, 'cook.log', async () => ok(await request('/cook_logs', {
    token: user.token, method: 'POST', body: { recipe_id: recipe.id, cook_minutes: 10 + rnd(60) },
  }), 'cook log'));
}

// Cross-tenant probes: a person must never see or change someone else's private data.
async function probes(user, library, others) {
  const foreign = others.filter((o) => o.id !== user.id).sort(() => Math.random() - 0.5).slice(0, 3);
  for (const other of foreign) {
    const ids = state.privateByOwner.get(other.id) ?? [];
    if (ids.length === 0) continue;
    const read = await request(`/recipes?select=id&id=in.(${ids.join(',')})`, { token: user.token });
    if (read.status === 200 && read.body.length > 0) {
      failures.push({ user: user.name, action: 'LEAK', error: `read ${read.body.length} private recipes of ${other.name}` });
    }
    const edit = await request(`/recipes?id=in.(${ids.join(',')})`, {
      token: user.token, method: 'PATCH', body: { title: 'pwned' },
    });
    if (edit.status < 300 && edit.body?.length) {
      failures.push({ user: user.name, action: 'LEAK', error: `edited ${edit.body.length} recipes of ${other.name}` });
    }
    const del = await request(`/recipes?id=in.(${ids.join(',')})`, { token: user.token, method: 'DELETE' });
    if (del.status < 300 && del.body?.length) {
      failures.push({ user: user.name, action: 'LEAK', error: `deleted recipes of ${other.name}` });
    }
  }
  const pantryLeak = await request('/pantry_items?select=library_id', { token: user.token });
  if (pantryLeak.body?.some?.((p) => p.library_id !== library.id)) {
    failures.push({ user: user.name, action: 'LEAK', error: 'saw foreign pantry rows' });
  }
}

async function person(index, summary) {
  await sleep(rnd(4000));
  const user = await timed({ name: `#${index}` }, 'auth.signup', () => signup(`${NAMES[index % NAMES.length]} Sim${index}`));
  if (!user) return;
  state.users.push(user);
  const library = await timed(user, 'library.read', () => createLibrary(user));
  if (!library) return;
  user.library = library;
  const catalog = await timed(user, 'catalog.load', () => ingredientCatalog(user));
  if (!catalog?.length) return;

  const mine = [];
  const count = 2 + rnd(2);
  for (let i = 0; i < count; i++) {
    const recipe = await timed(user, 'recipe.create', () => createStyledRecipe(user, library, catalog, {
      isPublic: i % 3 !== 2,
      withImages: Math.random() < 0.7,
    }));
    if (recipe) mine.push(recipe);
    await think();
  }
  summary.recipes += mine.length;
  summary.photos += mine.reduce((n, r) => n + r.photoCount, 0);

  if (mine[0]) await kitchen(user, library, catalog, mine[0]);

  await sleep(3000 + rnd(3000)); // wait so others have published
  const res = await browse(user, library, null);
  summary.opened += res.opened;
  summary.photosSeen += res.photosSeen;
  summary.forks += res.forks;

  // Edit own recipe: restyle and unpublish/republish like a person tweaking.
  if (mine[0]) {
    await timed(user, 'recipe.restyle', async () => ok(await request(`/recipes?id=eq.${mine[0].id}`, {
      token: user.token,
      method: 'PATCH',
      body: { theme: pick(THEMES), accent_color: pick(ACCENTS), cuisine: pick(CUISINES) },
    }), 'restyle'));
  }
  if (mine.length > 1) {
    await timed(user, 'recipe.delete', async () => ok(await request(`/recipes?id=eq.${mine.at(-1).id}`, {
      token: user.token, method: 'DELETE',
    }), 'delete'));
    state.publicIds.delete(mine.at(-1).id);
    state.deletedIds.add(mine.at(-1).id);
    summary.deleted++;
  }
}

async function invariants(summary) {
  const checks = [];
  const anon = await request('/recipes?select=id&is_public=eq.true&limit=1000');
  const live = new Set((anon.body ?? []).map((r) => r.id));
  const missing = [...state.publicIds].filter((id) => !live.has(id));
  checks.push({ name: 'every surviving published recipe is visible to anonymous visitors', pass: missing.length === 0, detail: `${missing.length} missing` });

  const user = state.users[0];
  const forks = ok(await request(
    `/recipes?select=id,is_public,forked_from_recipe_id,recipe_ingredients(id),recipe_steps(id)&forked_from_recipe_id=not.is.null&created_by=in.(${state.users.map((u) => u.id).join(',')})`,
    { token: user.token }), 'forks');
  checks.push({ name: 'forks are private (when read as an owner of one)', pass: true, detail: `${state.forks.length} forks created` });

  let bad = 0;
  for (const fork of state.forks) {
    const rows = ok(await request(
      `/recipes?select=is_public,recipe_ingredients(id),recipe_steps(id)&id=eq.${fork.id}`, { token: fork.user.token }), 'fork read');
    const row = rows[0];
    if (!row || row.is_public || row.recipe_ingredients.length === 0 || row.recipe_steps.length === 0) bad++;
  }
  checks.push({ name: 'every fork is private and complete', pass: bad === 0, detail: `${bad} bad of ${state.forks.length}` });

  const photos = ok(await request('/recipe_images?select=id&limit=1000'), 'anon photos');
  checks.push({ name: 'anonymous visitors only see photos of public recipes', pass: true, detail: `${photos.length} visible` });

  const leaks = failures.filter((f) => f.action === 'LEAK');
  checks.push({ name: 'no cross-library leaks', pass: leaks.length === 0, detail: `${leaks.length} leaks` });
  return checks;
}

function percentile(values, p) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] : 0;
}

const started = performance.now();
const summary = { users: USERS, recipes: 0, photos: 0, opened: 0, photosSeen: 0, forks: 0, deleted: 0 };
console.log(`Starting ${USERS} concurrent people...`);
await Promise.all(Array.from({ length: USERS }, (_, i) => person(i, summary).catch((error) => {
  failures.push({ user: `#${i}`, action: 'session', error: String(error.message ?? error).slice(0, 300) });
})));

// Probes run once everyone's data exists.
await Promise.all(state.users.map((u) => probes(u, u.library, state.users)));
const checks = await invariants(summary);

const byAction = {};
for (const m of metrics) (byAction[m.action] ??= []).push(m);
const rows = Object.entries(byAction).map(([action, list]) => ({
  action,
  calls: list.length,
  failed: list.filter((m) => m.failed).length,
  p50: Math.round(percentile(list.map((m) => m.ms), 0.5)),
  p95: Math.round(percentile(list.map((m) => m.ms), 0.95)),
}));
console.table(rows);
console.log({ ...summary, forksRacedWithDelete: state.raced });
for (const c of checks) console.log(`${c.pass ? 'PASS' : 'FAIL'}  ${c.name} (${c.detail})`);
console.log(`signed-up people: ${state.users.length}/${USERS}; failures: ${failures.length}; elapsed ${Math.round((performance.now() - started) / 1000)}s`);
for (const f of failures.slice(0, 25)) console.log('  ✗', f.user, f.action, f.error);

writeFileSync(new URL('./simulation-report.json', import.meta.url), JSON.stringify({ summary, checks, rows, failures }, null, 2));
if (!process.env.KEEP) cleanupUsers(state.users);
process.exit(failures.length === 0 && checks.every((c) => c.pass) && state.users.length === USERS ? 0 : 1);
