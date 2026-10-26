// =====================================================================
// parse.ts
//
// The pure, side-effect-free parsing half of import-recipe: turning a
// document or a pasted caption into a structured recipe.
//
// Split out of index.ts for the same reason guards.ts was: a module with
// no Deno.serve and no network calls can be executed and tested by any
// JavaScript runtime. The handler imports from here, so what the tests
// exercise is the code that ships, not a copy of it.
//
// Run:  node --experimental-strip-types parse.test.ts
// =====================================================================

import { sanitiseLine, stripHtml } from "./guards.ts";

export const MAX_INGREDIENTS = 60;
export const MAX_STEPS = 40;

export interface Parsed {
  title: string;
  description: string | null;
  ingredients: string[];
  steps: string[];
  servings: number | null;
  /**
   * Every line the classifier could not place, in the order it appeared.
   *
   * The heuristic below is a guess, and a guess that silently deletes what
   * it does not understand is worse than no guess at all: an overnight
   * marinade, an oven temperature or a substitution note would vanish
   * without the user ever knowing there was something to lose. Anything
   * unplaced is carried here so the import is lossless and the review
   * screen can show it.
   */
  notes: string | null;
  /** True when a cap was hit, so the client can say so rather than lie. */
  truncated: boolean;
}

/** schema.org/Recipe in a JSON-LD block. By far the most reliable path. */
export function fromJsonLd(html: string): Parsed | null {
  const blocks = html.matchAll(
    /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  );

  for (const block of blocks) {
    let data: unknown;
    try {
      data = JSON.parse(block[1].trim());
    } catch {
      continue;
    }

    const queue: unknown[] = Array.isArray(data) ? [...data] : [data];
    while (queue.length > 0) {
      const node = queue.shift();
      if (!node || typeof node !== "object") continue;
      const record = node as Record<string, unknown>;

      if (Array.isArray(record["@graph"])) queue.push(...record["@graph"]);

      const type = record["@type"];
      const isRecipe = type === "Recipe" ||
        (Array.isArray(type) && type.includes("Recipe"));
      if (!isRecipe) continue;

      const ingredients = (Array.isArray(record.recipeIngredient)
        ? record.recipeIngredient
        : [])
        .filter((v): v is string => typeof v === "string")
        .map((v) => sanitiseLine(v))
        .filter((v) => v.length > 0)
        .slice(0, MAX_INGREDIENTS);

      const rawSteps = Array.isArray(record.recipeInstructions)
        ? record.recipeInstructions
        : [];
      const steps = rawSteps
        .map((entry) => {
          if (typeof entry === "string") return entry;
          if (entry && typeof entry === "object") {
            const text = (entry as Record<string, unknown>).text;
            if (typeof text === "string") return text;
          }
          return "";
        })
        .map((v) => sanitiseLine(v, 500))
        .filter((v) => v.length > 0)
        .slice(0, MAX_STEPS);

      if (ingredients.length === 0 && steps.length === 0) continue;

      const yieldRaw = record.recipeYield;
      const yieldText = Array.isArray(yieldRaw) ? yieldRaw[0] : yieldRaw;
      const servings = typeof yieldText === "string" || typeof yieldText === "number"
        ? Number(String(yieldText).match(/\d+/)?.[0] ?? NaN)
        : NaN;

      return {
        title: sanitiseLine(
          typeof record.name === "string" ? record.name : "Imported recipe",
          160,
        ),
        description: typeof record.description === "string"
          ? sanitiseLine(record.description, 1000)
          : null,
        ingredients,
        steps,
        servings: Number.isFinite(servings) && servings > 0 && servings <= 100
          ? servings
          : null,
        notes: null,
        truncated: ingredients.length >= MAX_INGREDIENTS ||
          steps.length >= MAX_STEPS,
      };
    }
  }

  return null;
}

/**
 * Fallback for Instagram, TikTok and anything else that does not
 * publish structured data: work over the visible text and the meta
 * description, using the shape of the lines rather than any markup.
 */
export function fromText(html: string): Parsed {
  const metaTitle = html.match(
    /<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']{1,300})["']/i,
  )?.[1];
  const metaDescription = html.match(
    /<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']{1,2000})["']/i,
  )?.[1] ??
    html.match(
      /<meta[^>]+name=["']description["'][^>]+content=["']([^"']{1,2000})["']/i,
    )?.[1];
  const htmlTitle = html.match(/<title[^>]*>([\s\S]{1,300}?)<\/title>/i)?.[1];

  const body = stripHtml(html);
  const caption = metaDescription ? stripHtml(metaDescription) : "";
  const source = caption.length > 120 ? caption : body;

  // Captions from Instagram and TikTok are the common case, and they are
  // not written like a recipe site. Lines arrive prefixed with bullets,
  // numbered with "1.", padded with emoji, and closed with a wall of
  // hashtags. Normalising those away before classification is the
  // difference between finding five ingredients and finding two: a
  // leading "\u2022 " defeats the quantity anchor, so "\u2022 300g pasta" was
  // silently dropped while "\u2022 3 cloves garlic" survived on the unit word.
  const LIST_MARKER = /^[\s\u2022\u2023\u25E6\u2043\u2219*\u00B7\u25AA\u25CF\u25CB\u2013\u2014-]+/;
  const STEP_NUMBER = /^\s*\d{1,2}[.)]\s+/;
  const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}\u{2B00}-\u{2BFF}]/gu;
  const SECTION_HEADER =
    /^(ingredients|method|instructions|directions|steps|you will need|what you need|shopping list)\s*:?\s*$/i;
  const HASHTAG_LINE = /^#[\w\u00C0-\u024F]/;

  const lines = source
    .split("\n")
    .map((line) => line.replace(EMOJI, " "))
    .map((line) => line.replace(LIST_MARKER, "").replace(STEP_NUMBER, ""))
    .map((line) => sanitiseLine(line, 500))
    .filter((line) => line.length > 1 && line.length < 400)
    .filter((line) => !SECTION_HEADER.test(line))
    .filter((line) => !HASHTAG_LINE.test(line));

  // An ingredient line starts with a quantity, or is short and contains
  // a measurement word. A step is a sentence with a verb and no leading
  // number. Crude, and deliberately so — the user reviews the result.
  const quantityStart =
    /^(\d+[\d\s./,-]*)\s*(g|kg|ml|l|oz|lb|tsp|tbsp|cup|cups|clove|cloves|slice|slices|pinch|bunch|can|tin|pack|x)?\b/i;
  const measurementWord =
    /\b(g|kg|ml|l|oz|lb|tsp|tbsp|teaspoon|tablespoon|cup|cups|clove|cloves|pinch|bunch|can|tin|handful)\b/i;

  const ingredients: string[] = [];
  const steps: string[] = [];
  const leftovers: string[] = [];
  let truncated = false;

  for (const line of lines) {
    const looksIngredient = line.length <= 120 &&
      (quantityStart.test(line) || measurementWord.test(line)) &&
      !/[.!?]\s+\S/.test(line);

    if (looksIngredient) {
      if (ingredients.length < MAX_INGREDIENTS) {
        ingredients.push(sanitiseLine(line));
      } else {
        truncated = true;
        leftovers.push(line);
      }
      continue;
    }

    const looksStep = line.length >= 25 && /[a-z]/.test(line) &&
      /\b(add|mix|stir|heat|bake|cook|pour|chop|slice|season|serve|simmer|whisk|fold|roast|fry|boil|blend|preheat|remove|cover|drain|rest)\b/i
        .test(line);

    if (looksStep) {
      if (steps.length < MAX_STEPS) {
        steps.push(sanitiseLine(line, 500));
      } else {
        truncated = true;
        leftovers.push(line);
      }
      continue;
    }

    leftovers.push(line);
  }

  const servingsMatch = source.match(/serves\s+(\d{1,3})/i) ??
    source.match(/(\d{1,3})\s+servings?/i);
  const servings = servingsMatch ? Number(servingsMatch[1]) : NaN;

  // A pasted caption has no <title> and no og:title. Its first line is
  // almost always the dish name, and "Imported recipe" for every single
  // paste is a worse guess than the line the author actually wrote.
  const headline = metaTitle ?? htmlTitle ?? lines[0] ?? "Imported recipe";
  const usedFirstLineAsTitle = !metaTitle && !htmlTitle && lines.length > 0;

  const kept = usedFirstLineAsTitle
    ? leftovers.filter((line) => line !== lines[0])
    : leftovers;

  return {
    title: sanitiseLine(headline, 160),
    description: caption ? sanitiseLine(caption, 1000) : null,
    ingredients,
    steps,
    servings: Number.isFinite(servings) && servings > 0 && servings <= 100
      ? servings
      : null,
    notes: kept.length > 0 ? kept.join("\n").slice(0, 4000) : null,
    truncated,
  };
}

export function sourceFor(hostname: string): string {
  const host = hostname.toLowerCase();
  if (host.includes("instagram")) return "instagram";
  if (host.includes("tiktok")) return "tiktok";
  return "web";
}
