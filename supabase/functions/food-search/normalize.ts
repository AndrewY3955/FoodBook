// Pure helpers that turn USDA FoodData Central and Open Food Facts records
// into one shape. Every nutrient is per 100 g and keyed exactly like the
// app's NutrientDef keys, so the client can use the map as-is.
//
// A nutrient the source does not report is left out, never set to 0:
// "unknown" and "none" are different answers on a nutrition label.

export type Per100g = Record<string, number>;

export interface FoodResult {
  id: string;
  source: "usda" | "off";
  dataType: string;
  name: string;
  brand: string | null;
  category: string | null;
  per100g: Per100g;
  servingGrams: number | null;
  servingLabel: string | null;
}

// FDC nutrient number -> [app key, unit the app stores]. The first
// number listed for a key wins; later ones are fallbacks.
const FDC_MAP: Array<[string, string, string]> = [
  ["208", "calories", "kcal"],
  ["957", "calories", "kcal"],
  ["958", "calories", "kcal"],
  ["268", "calories", "kcal"],
  ["203", "protein_g", "g"],
  ["204", "fat_g", "g"],
  ["205", "carbs_g", "g"],
  ["291", "fiber_g", "g"],
  ["269", "sugar_g", "g"],
  ["269.3", "sugar_g", "g"],
  ["539", "added_sugar_g", "g"],
  ["606", "sat_fat_g", "g"],
  ["605", "trans_fat_g", "g"],
  ["646", "poly_fat_g", "g"],
  ["645", "mono_fat_g", "g"],
  ["601", "cholesterol_mg", "mg"],
  ["307", "sodium_mg", "mg"],
  ["306", "potassium_mg", "mg"],
  ["301", "calcium_mg", "mg"],
  ["303", "iron_mg", "mg"],
  ["401", "vitamin_c_mg", "mg"],
  ["328", "vitamin_d_mcg", "ug"],
  ["320", "vitamin_a_mcg", "ug"],
  ["323", "vitamin_e_mg", "mg"],
  ["430", "vitamin_k_mcg", "ug"],
  ["404", "thiamin_mg", "mg"],
  ["405", "riboflavin_mg", "mg"],
  ["406", "niacin_mg", "mg"],
  ["415", "vitamin_b6_mg", "mg"],
  ["417", "folate_mcg", "ug"],
  ["418", "vitamin_b12_mcg", "ug"],
  ["304", "magnesium_mg", "mg"],
  ["305", "phosphorus_mg", "mg"],
  ["309", "zinc_mg", "mg"],
  ["317", "selenium_mcg", "ug"],
];

const UNIT_ALIASES: Record<string, string> = {
  g: "g",
  grm: "g",
  mg: "mg",
  ug: "ug",
  "µg": "ug",
  mcg: "ug",
  kcal: "kcal",
  kj: "kj",
};

/** Converts [value] between g / mg / ug / kcal / kj. Null if incompatible. */
export function convertUnit(
  value: number,
  from: string,
  to: string,
): number | null {
  const f = UNIT_ALIASES[from.toLowerCase()];
  if (!f) return null;
  if (f === to) return value;
  const mass: Record<string, number> = { g: 1, mg: 1e-3, ug: 1e-6 };
  if (f in mass && to in mass) return (value * mass[f]) / mass[to];
  if (f === "kj" && to === "kcal") return value / 4.184;
  return null;
}

interface FdcNutrient {
  nutrientNumber?: string | number;
  unitName?: string;
  value?: number;
}

export interface FdcFood {
  fdcId?: number;
  description?: string;
  dataType?: string;
  brandOwner?: string;
  brandName?: string;
  foodCategory?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  householdServingFullText?: string;
  foodNutrients?: FdcNutrient[];
}

function clean(text: unknown, max: number): string {
  if (typeof text !== "string") return "";
  // deno-lint-ignore no-control-regex
  return text.replace(/[\u0000-\u001f\u007f<>]/g, " ").replace(/\s+/g, " ")
    .trim().slice(0, max);
}

/** Title-cases SHOUTING branded descriptions ("CHICK-FIL-A SAUCE"). */
export function tidyName(raw: string): string {
  const s = clean(raw, 120);
  if (s !== s.toUpperCase()) return s;
  return s.toLowerCase().replace(
    /(^|[\s(\-/'])([a-z])/g,
    (_m, a, b) => a + b.toUpperCase(),
  );
}

function round(n: Per100g): Per100g {
  const out: Per100g = {};
  for (const [k, v] of Object.entries(n)) out[k] = Math.round(v * 100) / 100;
  return out;
}

export function fdcNutrients(nutrients: FdcNutrient[] | undefined): Per100g {
  const out: Per100g = {};
  if (!Array.isArray(nutrients)) return out;
  const byNumber = new Map<string, FdcNutrient>();
  for (const n of nutrients) {
    if (n && n.nutrientNumber !== undefined) {
      byNumber.set(String(n.nutrientNumber), n);
    }
  }
  for (const [num, key, unit] of FDC_MAP) {
    if (key in out) continue;
    const n = byNumber.get(num);
    if (
      !n || typeof n.value !== "number" || !isFinite(n.value) || n.value < 0
    ) continue;
    // Number 268 is always kJ even if a record omits the unit.
    const from = n.unitName ?? (num === "268" ? "kj" : unit);
    const v = convertUnit(n.value, from, unit);
    if (v !== null) out[key] = v;
  }
  return round(out);
}

/** True when the record has enough data to be worth showing. */
export function usable(n: Per100g): boolean {
  const kcal = n.calories;
  if (kcal === undefined || kcal > 950) return false;
  return n.protein_g !== undefined || n.carbs_g !== undefined ||
    n.fat_g !== undefined;
}

export function fromFdc(f: FdcFood): FoodResult | null {
  if (typeof f.fdcId !== "number") return null;
  const name = tidyName(f.description ?? "");
  if (!name) return null;
  const per100g = fdcNutrients(f.foodNutrients);
  if (!usable(per100g)) return null;

  let servingGrams: number | null = null;
  const unit = (f.servingSizeUnit ?? "").toLowerCase();
  // Millilitres are treated as grams, which is close for most foods and
  // is how the label on the pack itself reads.
  if (
    typeof f.servingSize === "number" && f.servingSize > 0 &&
    (unit === "g" || unit === "grm" || unit === "ml" || unit === "mlt")
  ) {
    servingGrams = Math.round(f.servingSize * 10) / 10;
  }
  const brand = clean(f.brandName || f.brandOwner || "", 80);
  const household = clean(f.householdServingFullText ?? "", 60);

  return {
    id: `fdc:${f.fdcId}`,
    source: "usda",
    dataType: clean(f.dataType ?? "", 30),
    name,
    brand: brand ? tidyName(brand) : null,
    category: clean(f.foodCategory ?? "", 60) || null,
    per100g,
    servingGrams,
    servingLabel: servingGrams ? (household || `${servingGrams} g`) : null,
  };
}

// Open Food Facts reports minerals and vitamins in grams per 100 g.
const OFF_MAP: Array<[string, string, number]> = [
  ["energy-kcal", "calories", 1],
  ["proteins", "protein_g", 1],
  ["fat", "fat_g", 1],
  ["carbohydrates", "carbs_g", 1],
  ["fiber", "fiber_g", 1],
  ["sugars", "sugar_g", 1],
  ["added-sugars", "added_sugar_g", 1],
  ["saturated-fat", "sat_fat_g", 1],
  ["trans-fat", "trans_fat_g", 1],
  ["polyunsaturated-fat", "poly_fat_g", 1],
  ["monounsaturated-fat", "mono_fat_g", 1],
  ["cholesterol", "cholesterol_mg", 1e3],
  ["sodium", "sodium_mg", 1e3],
  ["potassium", "potassium_mg", 1e3],
  ["calcium", "calcium_mg", 1e3],
  ["iron", "iron_mg", 1e3],
  ["vitamin-c", "vitamin_c_mg", 1e3],
  ["vitamin-d", "vitamin_d_mcg", 1e6],
  ["vitamin-a", "vitamin_a_mcg", 1e6],
  ["vitamin-e", "vitamin_e_mg", 1e3],
  ["vitamin-k", "vitamin_k_mcg", 1e6],
  ["vitamin-b1", "thiamin_mg", 1e3],
  ["vitamin-b2", "riboflavin_mg", 1e3],
  ["vitamin-pp", "niacin_mg", 1e3],
  ["vitamin-b6", "vitamin_b6_mg", 1e3],
  ["vitamin-b9", "folate_mcg", 1e6],
  ["vitamin-b12", "vitamin_b12_mcg", 1e6],
  ["magnesium", "magnesium_mg", 1e3],
  ["phosphorus", "phosphorus_mg", 1e3],
  ["zinc", "zinc_mg", 1e3],
  ["selenium", "selenium_mcg", 1e6],
];

export interface OffProduct {
  code?: string;
  product_name?: string;
  brands?: string;
  categories?: string;
  serving_quantity?: number | string;
  serving_size?: string;
  nutriments?: Record<string, unknown>;
}

export function fromOff(p: OffProduct): FoodResult | null {
  const name = tidyName(p.product_name ?? "");
  const code = typeof p.code === "string" ? p.code.replace(/\D/g, "") : "";
  if (!name || !code || !p.nutriments) return null;

  const per100g: Per100g = {};
  for (const [src, key, mult] of OFF_MAP) {
    const raw = p.nutriments[`${src}_100g`];
    const v = typeof raw === "string" ? Number(raw) : raw;
    if (typeof v === "number" && isFinite(v) && v >= 0) per100g[key] = v * mult;
  }
  const rounded = round(per100g);
  if (!usable(rounded)) return null;

  const qty = Number(p.serving_quantity);
  const servingGrams = isFinite(qty) && qty > 0
    ? Math.round(qty * 10) / 10
    : null;
  const brand = clean((p.brands ?? "").split(",")[0], 80);

  return {
    id: `off:${code}`,
    source: "off",
    dataType: "Open Food Facts",
    name,
    brand: brand ? tidyName(brand) : null,
    category: clean((p.categories ?? "").split(",")[0], 60) || null,
    per100g: rounded,
    servingGrams,
    servingLabel: servingGrams
      ? (clean(p.serving_size ?? "", 60) || `${servingGrams} g`)
      : null,
  };
}

/** Drops repeats of the same name + brand, keeping the first (best ranked). */
export function dedupe(items: FoodResult[]): FoodResult[] {
  const seen = new Set<string>();
  const out: FoodResult[] = [];
  for (const f of items) {
    const k = `${f.name.toLowerCase()}|${(f.brand ?? "").toLowerCase()}|${
      Math.round(f.per100g.calories ?? 0)
    }`;
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(f);
  }
  return out;
}

/** Search text the user typed, cleaned for use as an upstream query. */
export function cleanQuery(q: unknown): string | null {
  if (typeof q !== "string") return null;
  const s = clean(q, 80);
  return s.length >= 2 ? s : null;
}
