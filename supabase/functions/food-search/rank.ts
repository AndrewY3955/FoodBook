// Query understanding and relevance ranking for food-search.
//
// USDA and Open Food Facts do plain keyword matching: no typo tolerance,
// no "type-ahead" completion, and restaurant chains are spelled a dozen
// ways. This module fills those gaps:
//
//   * plan()   turns what the user typed into a few upstream queries
//              (chain-aware, typo-corrected, last-word completed);
//   * score()  ranks the merged results so the closest match to what was
//              typed comes first.

import type { FoodResult } from "./normalize.ts";

/** Lowercase, accents and punctuation removed, single spaces. */
export function norm(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/['’`]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function tokens(s: string): string[] {
  const n = norm(s);
  return n ? n.split(" ") : [];
}

/** Levenshtein distance, giving up (returns max + 1) once it exceeds max. */
export function editDistance(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      const v = Math.min(
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
      cur.push(v);
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

// Canonical name (as USDA spells it) -> ways people type it.
export const CHAINS: Record<string, string[]> = {
  "McDonald's": ["mcdonalds", "mcdonald", "mickey ds", "mcd", "mc donalds"],
  "Burger King": ["burger king", "bk", "burgerking"],
  "Wendy's": ["wendys", "wendy"],
  "Taco Bell": ["taco bell", "tacobell"],
  "Pizza Hut": ["pizza hut", "pizzahut"],
  "Domino's": ["dominos", "domino", "dominos pizza"],
  "KFC": ["kfc", "kentucky fried chicken"],
  "Subway": ["subway"],
  "Papa John's": ["papa johns", "papa john", "papajohns"],
  "Little Caesars": ["little caesars", "little caesar", "little ceasars"],
  "Dairy Queen": ["dairy queen", "dq"],
  "Chick-fil-A": ["chick fil a", "chickfila", "chick fila", "chic fil a"],
  "Starbucks": ["starbucks", "starbuck", "sbux"],
  "Dunkin'": ["dunkin", "dunkin donuts", "dunkin donut"],
  "Chipotle": ["chipotle", "chipotle mexican grill"],
  "Panera Bread": ["panera", "panera bread"],
  "Arby's": ["arbys", "arby"],
  "Sonic": ["sonic", "sonic drive in"],
  "Jack in the Box": ["jack in the box", "jack in box"],
  "Popeyes": ["popeyes", "popeye", "popeyes louisiana kitchen"],
  "Whataburger": ["whataburger", "what a burger"],
  "Five Guys": ["five guys", "5 guys"],
  "In-N-Out": ["in n out", "in and out", "innout"],
  "Carl's Jr.": ["carls jr", "carl s jr", "carls junior"],
  "Hardee's": ["hardees", "hardee"],
  "Denny's": ["dennys", "denny"],
  "Applebee's": ["applebees", "applebee"],
  "Olive Garden": ["olive garden"],
  "Chili's": ["chilis", "chili s"],
  "Red Lobster": ["red lobster"],
  "IHOP": ["ihop"],
  "Panda Express": ["panda express", "panda"],
  "Shake Shack": ["shake shack"],
  "Culver's": ["culvers", "culver"],
  "Zaxby's": ["zaxbys", "zaxby"],
  "Raising Cane's": ["raising canes", "raising cane", "canes"],
  "Wingstop": ["wingstop", "wing stop"],
  "Tim Hortons": ["tim hortons", "tim horton", "timmies"],
  "Krispy Kreme": ["krispy kreme", "krispy kreme donuts"],
  "Baskin-Robbins": ["baskin robbins", "baskin"],
  "Jamba Juice": ["jamba juice", "jamba"],
  "Long John Silver's": ["long john silvers", "long john silver"],
  "Church's": ["churchs chicken", "churchs", "church s"],
  "Bojangles": ["bojangles", "bojangle"],
  "El Pollo Loco": ["el pollo loco"],
  "Qdoba": ["qdoba"],
  "Jersey Mike's": ["jersey mikes", "jersey mike"],
  "Jimmy John's": ["jimmy johns", "jimmy john"],
  "Firehouse Subs": ["firehouse subs", "firehouse"],
  "Del Taco": ["del taco"],
  "White Castle": ["white castle"],
  "Buffalo Wild Wings": ["buffalo wild wings", "bww"],
  "Cracker Barrel": ["cracker barrel"],
  "Outback Steakhouse": ["outback", "outback steakhouse"],
  "TGI Friday's": ["tgi fridays", "fridays", "tgi friday"],
  "Cold Stone": ["cold stone", "cold stone creamery"],
  "Auntie Anne's": ["auntie annes", "auntie anne"],
  "Texas Roadhouse": ["texas roadhouse"],
  "Dutch Bros": ["dutch bros", "dutch brothers"],
  "Tropical Smoothie": ["tropical smoothie", "tropical smoothie cafe"],
  "Sweetgreen": ["sweetgreen", "sweet green"],
  "Cava": ["cava"],
  "Moe's": ["moes", "moes southwest grill"],
};

interface ChainEntry {
  name: string;
  aliases: string[];
  key: string;
}
const CHAIN_LIST: ChainEntry[] = Object.entries(CHAINS).map((
  [name, aliases],
) => ({
  name,
  aliases: [norm(name), ...aliases.map(norm)],
  key: norm(name),
}));

export interface ChainMatch {
  name: string;
  key: string;
  /** What was typed after the chain name, e.g. "big mac". */
  rest: string;
}

export function detectChain(query: string): ChainMatch | null {
  const q = norm(query);
  if (q.length < 3) return null;
  let best: ChainMatch | null = null;
  let bestLen = 0;
  for (const c of CHAIN_LIST) {
    for (const a of c.aliases) {
      let rest: string | null = null;
      if (q === a) rest = "";
      else if (q.startsWith(a + " ")) rest = q.slice(a.length + 1);
      else if (
        a.length > q.length && a.startsWith(q) &&
        (q.includes(" ") || q.length >= 6)
      ) {
        rest = ""; // still typing the chain name
      } else if (q.endsWith(" " + a)) rest = q.slice(0, -(a.length + 1));
      if (rest !== null && a.length > bestLen) {
        best = { name: c.name, key: c.key, rest };
        bestLen = a.length;
      }
    }
  }
  return best;
}

// Words people look up, in rough order of popularity. Used only to fix
// typos and finish a half-typed last word; the real data comes from USDA.
const VOCAB_TEXT = `
chicken beef pork turkey lamb duck bacon sausage ham steak ribs brisket meatball meatballs hotdog hot dog burger
cheeseburger hamburger sandwich sandwiches nugget nuggets wings wing tenders fries fry onion rings
egg eggs milk cheese cheddar mozzarella parmesan feta ricotta gouda brie swiss provolone cream butter yogurt yoghurt
margarine ghee oil olive coconut canola avocado vegetable sesame peanut
rice pasta spaghetti macaroni noodles noodle ramen bread bagel toast tortilla taco burrito quesadilla nachos enchilada
pizza pepperoni lasagna ravioli oats oatmeal cereal granola flour wheat quinoa barley couscous cornmeal corn
potato potatoes sweet tomato tomatoes lettuce spinach kale broccoli cauliflower cabbage carrot carrots celery cucumber
zucchini squash pumpkin pepper peppers jalapeno mushroom mushrooms asparagus beet beets radish turnip eggplant
artichoke leek shallot scallion garlic ginger onion peas pea beans bean lentils chickpeas hummus tofu tempeh edamame
apple apples banana bananas orange oranges lemon lime grape grapes strawberry strawberries blueberry blueberries
raspberry raspberries blackberry cherry cherries peach peaches pear pears plum plums mango pineapple watermelon
cantaloupe melon kiwi papaya pomegranate grapefruit fig figs date dates raisin raisins cranberry cranberries apricot
coconut avocado olive olives pickle pickles
salmon tuna shrimp cod tilapia trout sardines sardine crab lobster scallops oyster oysters clams fish catfish halibut
almond almonds walnut walnuts pecan pecans cashew cashews pistachio pistachios hazelnut peanuts peanut seeds chia flax
flaxseed sunflower pumpkin
salt pepper paprika cumin coriander turmeric cinnamon nutmeg cloves clove cardamom saffron oregano basil thyme rosemary
sage parsley cilantro dill mint tarragon marjoram bay laurel fennel anise allspice cayenne chili chilli powder curry
mustard vanilla extract cumin garam masala seasoning spice spices herb herbs paprika smoked pepper peppercorn
sumac zaatar za'atar fenugreek caraway cardamom nutmeg mace wasabi horseradish vinegar
ketchup mayonnaise mayo mustard sauce salsa guacamole dressing ranch barbecue bbq teriyaki soy sriracha pesto
marinara alfredo gravy syrup honey jam jelly sugar brown molasses maple stevia sweetener
chocolate cocoa candy cookie cookies cake brownie muffin donut doughnut pie pancake pancakes waffle waffles croissant
cracker crackers chips pretzel popcorn ice cream icecream sundae shake milkshake smoothie
coffee latte cappuccino espresso mocha frappuccino tea juice soda cola water lemonade beer wine
protein bar whey powder
mcchicken big mac quarter pounder whopper frosty biscuit hash browns mcflurry
cheeseburger fillet filet grilled fried crispy spicy original nuggets
breakfast burrito wrap salad bowl soup stew chili broth stock
`;

const VOCAB: string[] = [];
const VOCAB_SET = new Set<string>();
for (const w of norm(VOCAB_TEXT).split(" ")) {
  if (w && !VOCAB_SET.has(w)) {
    VOCAB_SET.add(w);
    VOCAB.push(w);
  }
}
for (const c of CHAIN_LIST) {
  for (const a of c.aliases) {
    for (const w of a.split(" ")) {
      if (w.length >= 3 && !VOCAB_SET.has(w)) {
        VOCAB_SET.add(w);
        VOCAB.push(w);
      }
    }
  }
}

function known(t: string): boolean {
  if (VOCAB_SET.has(t) || /^\d+$/.test(t)) return true;
  if (t.endsWith("s") && VOCAB_SET.has(t.slice(0, -1))) return true;
  if (t.endsWith("es") && VOCAB_SET.has(t.slice(0, -2))) return true;
  return false;
}

/** Likely intended words for [t]. Empty when [t] already looks right. */
export function correctToken(t: string, isLast: boolean): string[] {
  if (t.length < 3) return [];
  const isKnown = known(t);
  // A short, valid word can still be the start of a longer one ("chick").
  if (isKnown && !(isLast && t.length <= 5)) return [];
  const out: string[] = [];
  if (isLast) {
    for (const w of VOCAB) {
      if (w.length > t.length && w.startsWith(t) && w !== t + "s") {
        out.push(w);
      }
      if (out.length >= (isKnown ? 1 : 2)) break;
    }
  }
  if (!isKnown && t.length >= 4) {
    const max = t.length >= 7 ? 2 : 1;
    let best: string | null = null;
    let bestD = max + 1;
    for (const w of VOCAB) {
      if (w.length < 3) continue;
      const d = editDistance(t, w, max);
      if (d < bestD) {
        best = w;
        bestD = d;
      }
    }
    if (best && !out.includes(best)) out.push(best);
  }
  return out;
}

export interface QueryPlan {
  query: string;
  chain: ChainMatch | null;
  /** Extra upstream queries beyond [query], best first. */
  variants: string[];
}

export function plan(rawQuery: string): QueryPlan {
  const query = rawQuery;
  const chain = detectChain(query);
  const variants: string[] = [];
  const add = (v: string) => {
    const nv = norm(v);
    if (nv && nv !== norm(query) && !variants.some((x) => norm(x) === nv)) {
      variants.push(v);
    }
  };

  if (chain) {
    // USDA spells the chain its own way; search that spelling too.
    add(chain.rest ? chain.name + " " + chain.rest : chain.name);
  }

  const toks = tokens(query);
  const fixes = toks.map((t, i) => correctToken(t, i === toks.length - 1));
  if (fixes.some((f) => f.length)) {
    // One variant per candidate for the last word, plus all typos fixed.
    const last = fixes[fixes.length - 1];
    const base = toks.map((t, i) => fixes[i][fixes[i].length - 1] ?? t);
    if (last.length > 1) {
      for (const cand of last.slice(0, 2)) {
        add(toks.slice(0, -1).map((t, i) => fixes[i][0] ?? t).concat(cand)
          .join(" "));
      }
    } else {
      add(base.join(" "));
    }
  }
  return { query, chain, variants: variants.slice(0, 2) };
}

const TYPE_BONUS: Record<string, number> = {
  "Foundation": 28,
  "SR Legacy": 24,
  "Survey (FNDDS)": 16,
  "Branded": 0,
  "Open Food Facts": -4,
};

/**
 * How well [food] answers what the user typed. Higher is closer.
 * The last typed word counts as a prefix so results appear while typing.
 */
export function score(
  food: FoodResult,
  queries: string[],
  chain: ChainMatch | null,
): number {
  const nameN = norm(food.name);
  const brandN = norm(food.brand ?? "");
  const nameWords = nameN.split(" ").filter(Boolean);
  const brandWords = brandN.split(" ").filter(Boolean);
  let best = -Infinity;

  for (let qi = 0; qi < queries.length; qi++) {
    const qt = tokens(queries[qi]);
    if (!qt.length) continue;
    let hit = 0;
    let firstPos = Infinity;
    qt.forEach((t, ti) => {
      const isLast = ti === qt.length - 1;
      let m = 0;
      let pos = nameWords.indexOf(t);
      if (pos >= 0) m = 1;
      if (m === 0 && t.length >= 3) {
        pos = nameWords.findIndex((w) =>
          w.startsWith(t) && (isLast || t.length >= 4)
        );
        if (pos >= 0) m = isLast ? 0.9 : 0.7;
      }
      if (m === 0 && t.length >= 4) {
        const max = t.length >= 7 ? 2 : 1;
        pos = nameWords.findIndex((w) => editDistance(t, w, max) <= max);
        if (pos >= 0) m = 0.6;
      }
      if (m === 0 && brandWords.some((w) => w === t || w.startsWith(t))) {
        m = 0.6;
        pos = 0;
      }
      if (m > 0 && pos >= 0 && pos < firstPos) firstPos = pos;
      hit += m;
    });
    const coverage = hit / qt.length;
    let s = coverage * 55;
    if (coverage < 0.5) s -= 30;

    const phrase = qt.join(" ");
    const branded = food.dataType === "Branded" ||
      food.dataType === "Open Food Facts";
    const segments = food.name.split(",").map(norm);
    const deplural = (s: string) => s.replace(/(es|s)$/, "");
    if (nameN === phrase) s += branded ? 25 : 45;
    else if (
      segments.some((g) => g === phrase || deplural(g) === deplural(phrase))
    ) {
      // "Spices, paprika" / "Bananas, raw": a reference food for the phrase.
      s += branded ? 18 : 40;
    } else if (nameN.startsWith(phrase)) s += 28;
    else if ((" " + nameN + " ").includes(" " + phrase + " ")) s += 18;
    if (Number.isFinite(firstPos)) s -= Math.min(firstPos, 8) * 1.5;
    s -= Math.min(Math.max(nameWords.length - qt.length, 0), 10) * 1.1;
    if (qi > 0) s -= 4; // a rewritten query is a guess; prefer what was typed
    if (s > best) best = s;
  }

  const chainHit = chain &&
    (brandN.includes(chain.key) || nameN.includes(chain.key));
  if (chainHit) best += 30;
  else if (!chain) best += TYPE_BONUS[food.dataType] ?? 0;
  else best += (TYPE_BONUS[food.dataType] ?? 0) / 2;

  best += Math.min(Object.keys(food.per100g).length, 30) * 0.25;
  return best;
}

/** Sorts best-first; ties keep the upstream order. */
export function rank(
  foods: FoodResult[],
  queries: string[],
  chain: ChainMatch | null,
): FoodResult[] {
  return foods
    .map((f, i) => ({ f, i, s: score(f, queries, chain) }))
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .map((x) => x.f);
}
