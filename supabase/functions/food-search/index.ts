// =====================================================================
// food-search
//
// Live food and restaurant nutrition lookup. Merges:
//
//   * USDA FoodData Central: Foundation, SR Legacy and FNDDS survey foods
//     (generic ingredients and the fast-food chains in SR Legacy), plus
//     the Branded Foods database (hundreds of thousands of packaged and
//     restaurant-brand items, refreshed by the USDA continuously).
//   * Open Food Facts: crowd-sourced packaged foods from around the
//     world. Best effort; its failure never fails the request.
//
// The FDC API key lives here as a secret so it never ships in the app:
//
//   supabase secrets set FDC_API_KEY=<key from https://fdc.nal.usda.gov/api-key-signup>
//
// Without it the shared DEMO_KEY is used, which is heavily rate limited.
//
// Auth: verify_jwt stays ON and the header is re-checked, so this can't
// become an anonymous proxy that spends the key's quota.
//
// Deploy:  supabase functions deploy food-search
// =====================================================================

import {
  cleanQuery,
  dedupe,
  type FdcFood,
  type FoodResult,
  fromFdc,
  fromOff,
  type OffProduct,
} from "./normalize.ts";
import { plan, rank } from "./rank.ts";

const GENERIC_TYPES = ["Foundation", "SR Legacy", "Survey (FNDDS)"];
const MAX_RESULTS = 40;
const UPSTREAM_TIMEOUT_MS = 6_000;
const CACHE_TTL_MS = 10 * 60_000;
const CACHE_MAX = 200;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const cache = new Map<string, { at: number; foods: FoodResult[] }>();

async function getJson(
  url: string,
  headers: Record<string, string>,
): Promise<unknown> {
  // FoodData Central intermittently answers 400/5xx to valid requests,
  // so a couple of quick retries are worth it.
  let lastStatus = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    const response = await fetch(url, {
      headers: { Accept: "application/json", ...headers },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    if (response.ok) return await response.json();
    await response.body?.cancel();
    lastStatus = response.status;
    if (lastStatus === 429 || (lastStatus < 500 && lastStatus !== 400)) break;
  }
  throw new Error(`upstream status ${lastStatus}`);
}

async function searchFdc(
  query: string,
  dataTypes: string[],
  pageSize: number,
  page: number,
): Promise<FoodResult[]> {
  const key = Deno.env.get("FDC_API_KEY") || "DEMO_KEY";
  const params = new URLSearchParams({
    query,
    dataType: dataTypes.join(","),
    pageSize: String(pageSize),
    pageNumber: String(page),
  });
  const data = await getJson(
    `https://api.nal.usda.gov/fdc/v1/foods/search?${params}`,
    { "X-Api-Key": key },
  ) as { foods?: FdcFood[] };
  return (data.foods ?? []).map(fromFdc).filter((f): f is FoodResult => !!f);
}

async function searchOff(query: string, page: number): Promise<FoodResult[]> {
  const params = new URLSearchParams({
    search_terms: query,
    search_simple: "1",
    action: "process",
    json: "1",
    page_size: "12",
    page: String(page),
    fields: "code,product_name,brands,categories,serving_size," +
      "serving_quantity,nutriments",
  });
  const data = await getJson(
    `https://world.openfoodfacts.org/cgi/search.pl?${params}`,
    { "User-Agent": "FoodBook/1.0 (recipe and nutrition app)" },
  ) as { products?: OffProduct[] };
  return (data.products ?? []).map(fromOff).filter((f): f is FoodResult =>
    !!f
  );
}

async function settled(p: Promise<FoodResult[]>, label: string) {
  try {
    return await p;
  } catch (error) {
    console.error("food source failed", {
      source: label,
      reason: error instanceof Error ? error.message : "unknown",
    });
    return null;
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!(request.headers.get("content-type") ?? "").includes("json")) {
    return json({ error: "expected_json" }, 415);
  }
  if (!request.headers.get("authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown> | null;
  try {
    body = await request.json() as Record<string, unknown> | null;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const query = cleanQuery(body?.query);
  if (!query) return json({ error: "invalid_query" }, 400);
  const rawPage = Number(body?.page ?? 1);
  const page = Number.isInteger(rawPage) && rawPage >= 1 && rawPage <= 20
    ? rawPage
    : 1;

  const cacheKey = `${page}|${query.toLowerCase()}`;
  const hit = cache.get(cacheKey);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) {
    return json({ foods: hit.foods });
  }

  // Typed text, plus guesses for typos, half-typed words and chain names.
  const queryPlan = plan(query);
  const isChain = queryPlan.chain !== null;
  const [generic, branded, off, ...extra] = await Promise.all([
    settled(
      searchFdc(query, GENERIC_TYPES, 25, page),
      "usda-generic",
    ),
    settled(searchFdc(query, ["Branded"], 25, page), "usda-branded"),
    settled(searchOff(query, page), "off"),
    ...queryPlan.variants.map((v, i) =>
      settled(
        searchFdc(v, [...GENERIC_TYPES, "Branded"], isChain && i === 0 ? 50 : 25, page),
        "usda-variant",
      )
    ),
  ]);

  if (
    generic === null && branded === null && off === null &&
    extra.every((e) => e === null)
  ) {
    return json({ error: "upstream_unavailable" }, 502);
  }

  const merged = dedupe([
    ...(generic ?? []),
    ...(branded ?? []),
    ...extra.flatMap((e) => e ?? []),
    ...(off ?? []),
  ]);
  const foods = rank(
    merged,
    [query, ...queryPlan.variants],
    queryPlan.chain,
  ).slice(0, MAX_RESULTS);

  if (cache.size >= CACHE_MAX) cache.clear();
  cache.set(cacheKey, { at: Date.now(), foods });
  return json({ foods });
});
