// =====================================================================
// parse.test.ts
//
// Run:  node --experimental-strip-types parse.test.ts
//   or: deno test --allow-none parse.test.ts
//
// These exercise the real exported functions from parse.ts, which is the
// same module index.ts imports, so what is asserted here is what ships.
//
// The parser is a heuristic. That is exactly why it needs pinning: every
// case below is a real shape that arrives from a recipe site, an
// Instagram caption or a TikTok description, and several of them were
// silently wrong before these tests existed.
// =====================================================================

import {
  fromJsonLd,
  fromText,
  sourceFor,
  MAX_INGREDIENTS,
  MAX_STEPS,
} from "./parse.ts";

let pass = 0;
let fail = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
    console.log("PASS  " + label);
  } else {
    fail++;
    console.log("FAIL  " + label + "\n        expected " + e + "\n        actual   " + a);
  }
}

function contains(label: string, haystack: string[], needle: string): void {
  check(label, haystack.includes(needle), true);
}

const NL = "\n";
const BULLET = "•";
const HALF = "½";

// ---------------------------------------------------------------------
// 1. Caption normalisation
//
// A leading bullet defeats the quantity anchor, and "300g" has no word
// boundary between the digits and the unit. Together those dropped three
// of five ingredients from a perfectly ordinary caption.
// ---------------------------------------------------------------------
const caption = [
  "Creamy garlic butter pasta",
  "serves 4",
  "",
  "Ingredients:",
  BULLET + " 300g spaghetti",
  BULLET + " 3 cloves garlic",
  BULLET + " 50g butter",
  BULLET + " 200ml double cream",
  BULLET + " " + HALF + " cup parmesan",
  "",
  "Method:",
  "1. Boil the spaghetti in salted water until al dente.",
  "2. Melt the butter and cook the garlic gently for two minutes.",
  "3. Pour in the cream and simmer until thickened.",
  "",
  "#pasta #easyrecipes",
].join(NL);

const cap = fromText(caption);

check("1.1  bulleted caption yields every ingredient", cap.ingredients.length, 5);
contains("1.2  glued unit 300g survives", cap.ingredients, "300g spaghetti");
contains("1.3  glued unit 200ml survives", cap.ingredients, "200ml double cream");
contains("1.4  unicode fraction survives", cap.ingredients, HALF + " cup parmesan");
check("1.5  bullet is stripped from output", cap.ingredients.some((i) => i.startsWith(BULLET)), false);
check("1.6  step numbering stripped", cap.steps[0], "Boil the spaghetti in salted water until al dente.");
check("1.7  three steps found", cap.steps.length, 3);
check("1.8  Ingredients: header is not an ingredient", cap.ingredients.includes("Ingredients:"), false);
check("1.9  hashtag line is dropped", JSON.stringify(cap).includes("#pasta"), false);
check("1.10 servings read from caption", cap.servings, 4);
check("1.11 first line becomes the title", cap.title, "Creamy garlic butter pasta");
check("1.12 title is not repeated in notes", (cap.notes ?? "").includes("Creamy garlic butter pasta"), false);

// Emoji must not stop a line being classified.
const emojiCaption = [
  "Spicy noodles",
  "\u{1F9C2} Ingredients:",
  BULLET + " 200g noodles \u{1F35C}",
  "\u{1F468}‍\u{1F373} Method:",
  "Boil the noodles and stir through the sauce until glossy.",
].join(NL);
const emo = fromText(emojiCaption);
check("1.13 emoji do not block ingredient detection", emo.ingredients.length, 1);
check("1.14 emoji header still dropped", emo.ingredients.includes("Ingredients:"), false);
check("1.15 emoji stripped from ingredient text", emo.ingredients[0], "200g noodles");

// ---------------------------------------------------------------------
// 2. Losslessness
//
// The classifier is a guess. A guess that deletes what it cannot place
// loses the marinade time and the oven temperature, and the user never
// learns there was anything to lose.
// ---------------------------------------------------------------------
const lossy = [
  "Overnight fried chicken",
  BULLET + " 900g chicken wings",
  "Marinate overnight, minimum 8 hours",
  "Oven 200C fan / 425F",
  "Gluten free if you swap the starch",
  "Fry in batches until deep golden, about eight minutes.",
].join(NL);
const loss = fromText(lossy);

check("2.1  ingredient still found", loss.ingredients.length, 1);
check("2.2  step still found", loss.steps.length, 1);
check("2.3  unplaced lines are kept, not deleted", loss.notes !== null, true);
check("2.4  marinade time survives", (loss.notes ?? "").includes("Marinate overnight, minimum 8 hours"), true);
check("2.5  oven temperature survives", (loss.notes ?? "").includes("Oven 200C fan / 425F"), true);
check("2.6  substitution note survives", (loss.notes ?? "").includes("Gluten free if you swap the starch"), true);
check("2.7  notes preserve original order", loss.notes, [
  "Marinate overnight, minimum 8 hours",
  "Oven 200C fan / 425F",
  "Gluten free if you swap the starch",
].join(NL));

const clean = fromText([
  "Toast",
  "2 slices bread",
  "Toast the bread until it is golden and serve it warm.",
].join(NL));
check("2.8  notes are null when nothing was left over", clean.notes, null);

// ---------------------------------------------------------------------
// 3. Truncation is reported, never silent
// ---------------------------------------------------------------------
check("3.1  ordinary caption is not truncated", cap.truncated, false);

const manyIngredients = ["Big batch"]
  .concat(Array.from({ length: MAX_INGREDIENTS + 5 }, (_, i) => (i + 1) + " g flour"))
  .join(NL);
const big = fromText(manyIngredients);
check("3.2  ingredients stop at the cap", big.ingredients.length, MAX_INGREDIENTS);
check("3.3  hitting the cap is reported", big.truncated, true);
check("3.4  overflow is kept in notes, not dropped", (big.notes ?? "").length > 0, true);

const manySteps = ["Long method"]
  .concat(Array.from({ length: MAX_STEPS + 3 }, () => "Stir the pot gently and then cover it again."))
  .join(NL);
const longMethod = fromText(manySteps);
check("3.5  steps stop at the cap", longMethod.steps.length, MAX_STEPS);
check("3.6  step overflow reported", longMethod.truncated, true);

// ---------------------------------------------------------------------
// 4. Title resolution
// ---------------------------------------------------------------------
const withOg = '<meta property="og:title" content="Proper Shakshuka"><body>' +
  "2 tbsp olive oil\nFry the onions until soft and sweet.</body>";
check("4.1  og:title wins over the first line", fromText(withOg).title, "Proper Shakshuka");

const withTitleTag = "<title>Panzanella</title><body>200 g sourdough loaf\n" +
  "Toss the bread through the dressing and rest it.</body>";
check("4.2  <title> used when og:title is absent", fromText(withTitleTag).title, "Panzanella");

check("4.3  empty input falls back to a safe title", fromText("").title, "Imported recipe");
check("4.4  empty input yields nothing, not junk", fromText("").ingredients.length, 0);

// ---------------------------------------------------------------------
// 5. Servings
// ---------------------------------------------------------------------
check("5.1  'serves 6'", fromText("Stew\nserves 6\n2 kg beef shin").servings, 6);
check("5.2  '8 servings'", fromText("Cake\n8 servings\n300 g flour").servings, 8);
check("5.3  absurd serving counts rejected", fromText("Feast\nserves 900\n1 kg rice").servings, null);
check("5.4  no serving information is null", fromText("Snack\n1 tsp salt").servings, null);

// ---------------------------------------------------------------------
// 6. JSON-LD, the reliable path
// ---------------------------------------------------------------------
const ld = (obj: unknown) =>
  '<script type="application/ld+json">' + JSON.stringify(obj) + "</script>";

const recipeLd = ld({
  "@type": "Recipe",
  name: "Weeknight Dal",
  description: "A fast lentil curry",
  recipeIngredient: ["200 g red lentils", "1 tsp turmeric"],
  recipeInstructions: [
    { text: "Rinse the lentils until the water runs clear." },
    "Simmer with the turmeric until thick.",
  ],
  recipeYield: "4 servings",
});
const fromLd = fromJsonLd(recipeLd);

check("6.1  JSON-LD recipe is found", fromLd !== null, true);
check("6.2  name becomes the title", fromLd?.title, "Weeknight Dal");
check("6.3  ingredients parsed", fromLd?.ingredients, ["200 g red lentils", "1 tsp turmeric"]);
check("6.4  instruction objects read their .text", fromLd?.steps[0], "Rinse the lentils until the water runs clear.");
check("6.5  plain-string instructions also work", fromLd?.steps[1], "Simmer with the turmeric until thick.");
check("6.6  recipeYield digits become servings", fromLd?.servings, 4);
check("6.7  JSON-LD carries no leftover notes", fromLd?.notes, null);
check("6.8  JSON-LD is not truncated", fromLd?.truncated, false);

const graphLd = ld({
  "@context": "https://schema.org",
  "@graph": [
    { "@type": "WebPage", name: "not the recipe" },
    { "@type": ["Recipe"], name: "Graph Loaf", recipeIngredient: ["500 g flour"], recipeInstructions: ["Bake until hollow."] },
  ],
});
check("6.9  @graph is traversed", fromJsonLd(graphLd)?.title, "Graph Loaf");
check("6.10 @type array containing Recipe is accepted", fromJsonLd(graphLd)?.ingredients, ["500 g flour"]);

check("6.11 a page with no Recipe returns null", fromJsonLd(ld({ "@type": "WebPage", name: "nope" })), null);
check("6.12 malformed JSON-LD does not throw", fromJsonLd('<script type="application/ld+json">{ broken</script>'), null);
check("6.13 no JSON-LD at all returns null", fromJsonLd("<html><body>hello</body></html>"), null);

// ---------------------------------------------------------------------
// 7. Sanitisation carries through the parser
// ---------------------------------------------------------------------
const nasty = fromText([
  "Dodgy recipe",
  "2 tsp javascript:alert(1) sugar",
  "Stir the mixture onerror=alert(1) and heat it through gently.",
].join(NL));
check("7.1  scheme handler neutralised in an ingredient", nasty.ingredients.some((i) => i.includes("javascript:")), false);
check("7.2  event handler neutralised in a step", nasty.steps.some((s) => s.includes("onerror=")), false);

// ---------------------------------------------------------------------
// 8. Source attribution
// ---------------------------------------------------------------------
check("8.1  instagram host", sourceFor("www.instagram.com"), "instagram");
check("8.2  tiktok host", sourceFor("vm.tiktok.com"), "tiktok");
check("8.3  anything else is web", sourceFor("www.bbcgoodfood.com"), "web");
check("8.4  host matching is case insensitive", sourceFor("WWW.TikTok.COM"), "tiktok");

console.log("\n---------------------------------------------");
console.log("PASS " + pass + "   FAIL " + fail);
if (fail > 0) process.exitCode = 1;
