// Run:  node --experimental-strip-types normalize.test.ts
//   or: deno test normalize.test.ts

import {
  cleanQuery,
  convertUnit,
  dedupe,
  fdcNutrients,
  fromFdc,
  fromOff,
  tidyName,
} from "./normalize.ts";

let pass = 0;
let fail = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) pass++;
  else {
    fail++;
    console.error(`FAIL ${label}\n  got      ${JSON.stringify(actual)}\n  expected ${JSON.stringify(expected)}`);
  }
}

check("unit g->mg", convertUnit(1.5, "G", "mg"), 1500);
check("unit ug->mg", convertUnit(500, "UG", "mg"), 0.5);
check("unit kj->kcal", Math.round(convertUnit(418.4, "kJ", "kcal")!), 100);
check("unit incompatible", convertUnit(5, "IU", "ug"), null);

check(
  "fdc maps and converts units",
  fdcNutrients([
    { nutrientNumber: "208", unitName: "KCAL", value: 516 },
    { nutrientNumber: "307", unitName: "MG", value: 613 },
    { nutrientNumber: "301", unitName: "G", value: 0.5 },
    { nutrientNumber: "328", unitName: "UG", value: 2 },
  ]),
  { calories: 516, sodium_mg: 613, calcium_mg: 500, vitamin_d_mcg: 2 },
);

check(
  "fdc falls back to kJ energy and keeps missing nutrients absent",
  fdcNutrients([
    { nutrientNumber: "268", unitName: "kJ", value: 418.4 },
    { nutrientNumber: "203", unitName: "G", value: 3 },
  ]),
  { calories: 100, protein_g: 3 },
);

const sauce = fromFdc({
  fdcId: 2559846,
  description: "CHICK-FIL-A SAUCE, 16 FL OZ",
  dataType: "Branded",
  brandName: "CHICK-FIL-A",
  servingSize: 31,
  servingSizeUnit: "GRM",
  householdServingFullText: "2 Tbsp (31g)",
  foodNutrients: [
    { nutrientNumber: "208", unitName: "KCAL", value: 516 },
    { nutrientNumber: "204", unitName: "G", value: 45.2 },
  ],
});
check("fdc name tidied", sauce?.name, "Chick-Fil-A Sauce, 16 Fl Oz");
check("fdc serving", [sauce?.servingGrams, sauce?.servingLabel], [31, "2 Tbsp (31g)"]);
check("fdc id", sauce?.id, "fdc:2559846");

check("fdc rejects record without calories", fromFdc({
  fdcId: 1,
  description: "x",
  foodNutrients: [{ nutrientNumber: "203", unitName: "G", value: 3 }],
}), null);

check("fdc rejects impossible energy", fromFdc({
  fdcId: 2,
  description: "bad",
  foodNutrients: [
    { nutrientNumber: "208", unitName: "KCAL", value: 5000 },
    { nutrientNumber: "203", unitName: "G", value: 3 },
  ],
}), null);

const off = fromOff({
  code: "3017620422003",
  product_name: "Nutella",
  brands: "Ferrero,Other",
  serving_quantity: "15",
  serving_size: "15 g",
  nutriments: {
    "energy-kcal_100g": 539,
    proteins_100g: 6.3,
    sodium_100g: 0.0428,
    "vitamin-d_100g": 0.000002,
  },
});
check("off converts grams to mg / mcg", [
  off?.per100g.sodium_mg,
  off?.per100g.vitamin_d_mcg,
], [42.8, 2]);
check("off brand and serving", [off?.brand, off?.servingGrams], ["Ferrero", 15]);
check("off needs a barcode", fromOff({ product_name: "x", nutriments: {} }), null);

check(
  "dedupe keeps first of identical items",
  dedupe([sauce!, { ...sauce!, id: "fdc:2" }]).map((f) => f.id),
  ["fdc:2559846"],
);
check("tidyName leaves mixed case alone", tidyName("Cheese, cheddar"), "Cheese, cheddar");
check("cleanQuery strips markup", cleanQuery("  <b>big</b>   mac "), "b big /b mac");
check("cleanQuery too short", cleanQuery("a"), null);
check("cleanQuery non-string", cleanQuery(5), null);

console.log(`${pass} passed, ${fail} failed`);
if (fail > 0) {
  // deno-lint-ignore no-explicit-any
  (globalThis as any).process?.exit?.(1);
  throw new Error("tests failed");
}
