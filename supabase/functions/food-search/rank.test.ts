// Run:  node --experimental-strip-types rank.test.ts
//   or: deno test rank.test.ts

import type { FoodResult } from "./normalize.ts";
import {
  correctToken,
  detectChain,
  editDistance,
  norm,
  plan,
  rank,
} from "./rank.ts";

let pass = 0;
let fail = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) pass++;
  else {
    fail++;
    console.error(
      `FAIL ${label}\n  got      ${JSON.stringify(actual)}\n  expected ${
        JSON.stringify(expected)
      }`,
    );
  }
}

function food(
  name: string,
  dataType: string,
  brand: string | null = null,
): FoodResult {
  return {
    id: name,
    source: "usda",
    dataType,
    name,
    brand,
    category: null,
    per100g: { calories: 100, protein_g: 1 },
    servingGrams: null,
    servingLabel: null,
  };
}

function top(foods: FoodResult[], q: string): string[] {
  const p = plan(q);
  return rank(foods, [q, ...p.variants], p.chain).map((f) => f.name);
}

check("norm", norm("McDonald's  Big-Mac!"), "mcdonalds big mac");
check("distance", editDistance("papirka", "paprika", 2), 2);
check("distance cutoff", editDistance("abc", "xyzxyz", 1), 2);

check("typo fixed", correctToken("papirka", false), ["paprika"]);
check("known word untouched", correctToken("chicken", true), []);
check("plural untouched", correctToken("eggs", true), []);
check("prefix completes", correctToken("chick", true)[0], "chicken");

check("chain alias", detectChain("mcdonalds big mac")?.name, "McDonald's");
check("chain rest", detectChain("mcdonalds big mac")?.rest, "big mac");
check("chain typing", detectChain("chick fi")?.name, "Chick-fil-A");
check("chain suffix", detectChain("nuggets wendys")?.rest, "nuggets");
check("not a chain", detectChain("chicken breast"), null);

const p = plan("papirka");
check("plan typo variant", p.variants, ["paprika"]);
check("plan chain variant", plan("mickey ds fries").variants[0], "McDonald's fries");

check(
  "exact generic beats branded compound",
  top([
    food("Mac Attack Mac & Cheese Pizza", "Branded", "Brew Pub"),
    food("Big Mac", "SR Legacy", "McDonald's"),
  ], "big mac")[0],
  "Big Mac",
);

check(
  "simple whole food first",
  top([
    food("Chicken Noodle Soup Kit", "Branded", "Acme"),
    food("Chicken, broilers or fryers, breast, raw", "SR Legacy"),
    food("Chicken breast", "Foundation"),
  ], "chicken breast")[0],
  "Chicken breast",
);

check(
  "type-ahead prefix",
  top([
    food("Spaghetti sauce", "Branded"),
    food("Chickpeas, cooked", "SR Legacy"),
    food("Chicken, raw", "SR Legacy"),
  ], "chick")[0] !== "Spaghetti sauce",
  true,
);

check(
  "typo query finds the right food",
  top([
    food("Pepper, black", "SR Legacy"),
    food("Spices, paprika", "SR Legacy"),
  ], "papirka")[0],
  "Spices, paprika",
);

check(
  "chain items outrank retail",
  top([
    food("Taco Kit", "Branded", "Old El Paso"),
    food("Crunchy Taco", "SR Legacy", "Taco Bell"),
  ], "taco bell")[0],
  "Crunchy Taco",
);

console.log(`${pass} passed, ${fail} failed`);
if (fail > 0) {
  // deno-lint-ignore no-explicit-any
  (globalThis as any).process?.exit(1);
}
