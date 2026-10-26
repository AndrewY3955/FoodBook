import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';

export const supabaseUrl =
  process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;

if (!publishableKey) {
  throw new Error('Set SUPABASE_PUBLISHABLE_KEY before running workflow tests.');
}

const restUrl = `${supabaseUrl.replace(/\/$/, '')}/rest/v1`;

export async function request(path, {
  token,
  method = 'GET',
  body,
} = {}) {
  const headers = { apikey: publishableKey };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method !== 'GET') headers.Prefer = 'return=representation';

  const response = await fetch(`${restUrl}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let parsed = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }
  }
  return { status: response.status, body: parsed };
}

export function expectOk(response, label) {
  assert.ok(
    response.status >= 200 && response.status < 300,
    `${label}: HTTP ${response.status} ${JSON.stringify(response.body)}`,
  );
  return response.body;
}

export async function createUser(displayName) {
  const email = `workflow-${randomUUID()}@example.test`;
  const password = `Aa1!${randomUUID()}z`;
  const response = await fetch(
    `${supabaseUrl.replace(/\/$/, '')}/auth/v1/signup`,
    {
      method: 'POST',
      headers: {
        apikey: publishableKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email,
        password,
        data: { display_name: displayName },
      }),
    },
  );
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  assert.ok(
    response.ok && body?.access_token && body?.user?.id,
    `signup: HTTP ${response.status} ${JSON.stringify(body)}`,
  );
  return { id: body.user.id, email, token: body.access_token };
}

export async function createLibrary(user) {
  const rows = expectOk(
    await request('/libraries?select=id,name', { token: user.token }),
    'read the new user library',
  );
  assert.equal(rows.length, 1, 'signup should create exactly one library');
  return rows[0];
}

export async function createRecipe({
  user,
  library,
  title,
  isPublic = false,
}) {
  const recipeRows = expectOk(
    await request('/recipes', {
      token: user.token,
      method: 'POST',
      body: {
        library_id: library.id,
        created_by: user.id,
        title,
        description: `Workflow test recipe ${title}`,
        meal_type: 'dinner',
        season: 'all_year',
        base_servings: 4,
        import_source: 'manual',
        is_public: isPublic,
      },
    }),
    'create recipe',
  );
  const recipe = recipeRows[0];
  assert.ok(recipe?.id, 'recipe insert should return its id');

  const ingredients = [];
  for (const [sortOrder, [name, quantity, unit]] of [
    ['Olive Oil', 2, 'tbsp'],
    ['Garlic', 2, 'clove'],
  ].entries()) {
    const found = expectOk(
      await request(
        `/ingredients?select=id,name&name=eq.${encodeURIComponent(name)}`,
        { token: user.token },
      ),
      `find global ingredient ${name}`,
    );
    assert.ok(found[0]?.id, `global ingredient ${name} must exist`);
    ingredients.push({
      recipe_id: recipe.id,
      library_id: library.id,
      ingredient_id: found[0].id,
      quantity,
      unit,
      sort_order: sortOrder,
    });
  }

  expectOk(
    await request('/recipe_ingredients', {
      token: user.token,
      method: 'POST',
      body: ingredients,
    }),
    'create recipe ingredients',
  );
  expectOk(
    await request('/recipe_steps', {
      token: user.token,
      method: 'POST',
      body: [
        {
          recipe_id: recipe.id,
          library_id: library.id,
          step_number: 1,
          instruction: 'Warm the oil and soften the garlic.',
        },
        {
          recipe_id: recipe.id,
          library_id: library.id,
          step_number: 2,
          instruction: 'Finish, season and serve.',
        },
      ],
    }),
    'create recipe steps',
  );

  return recipe;
}

export function recipeQuery({
  ids,
  libraryId,
  titlePattern,
}) {
  const query = new URLSearchParams({
    select: 'id,title,library_id,is_public,forked_from_recipe_id',
  });
  if (ids) query.set('id', `in.(${ids.join(',')})`);
  if (libraryId) query.set('library_id', `eq.${libraryId}`);
  if (titlePattern) query.set('title', `ilike.*${titlePattern}*`);
  return `/recipes?${query.toString()}`;
}

export function cleanupUsers(users) {
  const ids = users.map((user) => user.id);
  if (ids.length === 0) return;
  assert.ok(ids.every((id) => /^[0-9a-f-]{36}$/i.test(id)));
  const container =
    process.env.FOODBOOK_DB_CONTAINER ?? 'supabase_db_FoodBook';
  const values = ids.map((id) => `'${id}'`).join(',');
  execFileSync(
    'docker',
    [
      'exec',
      container,
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-v',
      'ON_ERROR_STOP=1',
      '-c',
      `delete from libraries where created_by in (${values}); delete from auth.users where id in (${values})`,
    ],
    { stdio: 'ignore' },
  );
}

const authUrl = supabaseUrl.replace(/\/$/, '');

// 1x1 PNG, accepted by the recipe-covers bucket.
export const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

export async function uploadObject(user, path, bytes = tinyPng) {
  const response = await fetch(
    `${authUrl}/storage/v1/object/recipe-covers/${path}`,
    {
      method: 'POST',
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${user.token}`,
        'Content-Type': 'image/png',
      },
      body: bytes,
    },
  );
  return { status: response.status, body: await response.text() };
}

export async function readObject(token, path) {
  const headers = { apikey: publishableKey };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(
    `${authUrl}/storage/v1/object/authenticated/recipe-covers/${path}`,
    { headers },
  );
  return { status: response.status, bytes: (await response.arrayBuffer()).byteLength };
}
