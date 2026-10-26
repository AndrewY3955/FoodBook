// =====================================================================
// import-recipe
//
// Takes a URL, returns a structured guess at the recipe on the other
// end. Runs in a Deno isolate with no database credentials beyond the
// caller's own JWT.
//
// This function is the only part of the system that fetches attacker-
// chosen URLs, so it is written defensively throughout:
//
//   1. Authentication. verify_jwt is left ON (the default). An
//      unauthenticated fetch-anything endpoint on a public URL is an
//      open proxy, and it will be found.
//   2. Method and content-type are checked before the body is read.
//   3. SSRF. https only; literal private, loopback, link-local and
//      cloud-metadata addresses are refused; redirects are followed
//      manually so each hop is re-checked rather than trusted.
//   4. Resource limits. A connect timeout, a total timeout, a byte
//      ceiling enforced while streaming, and a redirect cap. Without
//      the streaming ceiling a 4 GB response ends the isolate.
//   5. Content is stripped before it is parsed, not after. Script,
//      style, template and comment nodes are removed wholesale, then
//      anything that still smells like a scheme handler or an event
//      attribute is dropped.
//   6. Output is bounded: fixed field count, fixed lengths, fixed array
//      sizes. Whatever the remote page contains, the response shape is
//      the same.
//
// Deploy:  supabase functions deploy import-recipe
// =====================================================================

import { MAX_BYTES, validateUrl } from "./guards.ts";
import { fromJsonLd, fromText, sourceFor } from "./parse.ts";

const TOTAL_TIMEOUT_MS = 8_000;
const MAX_REDIRECTS = 3;

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

// ---------------------------------------------------------------------
// Fetch, with manual redirect handling and a hard byte ceiling
// ---------------------------------------------------------------------

async function fetchHtml(start: URL, signal: AbortSignal): Promise<string> {
  let current = start;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const response = await fetch(current.toString(), {
      signal,
      redirect: "manual",
      headers: {
        // A plain, honest user agent. Pretending to be a browser to get
        // past a block is someone else's bandwidth being taken.
        "User-Agent": "KitchenRecipeImporter/1.0 (+recipe import on user request)",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en",
      },
    });

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      await response.body?.cancel();
      if (!location) throw new Error("redirect without location");

      // Re-validate every hop. A page that passes the check and then
      // redirects to 169.254.169.254 is the classic SSRF bypass.
      const next = validateUrl(new URL(location, current).toString());
      if (!next) throw new Error("redirect to a disallowed address");
      current = next;
      continue;
    }

    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`upstream status ${response.status}`);
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("html") && !contentType.includes("text/plain")) {
      await response.body?.cancel();
      throw new Error("not an HTML document");
    }

    // Content-Length is a hint from the remote server, so it is checked
    // but not trusted; the real limit is enforced while reading.
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (declared > MAX_BYTES) {
      await response.body?.cancel();
      throw new Error("document too large");
    }

    const reader = response.body?.getReader();
    if (!reader) throw new Error("empty body");

    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > MAX_BYTES) {
        await reader.cancel();
        throw new Error("document too large");
      }
      chunks.push(value);
    }

    const merged = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      merged.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder("utf-8", { fatal: false }).decode(merged);
  }

  throw new Error("too many redirects");
}

// ---------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------

// ---------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return json({ error: "expected_json" }, 415);
  }

  // The platform has already verified the JWT (verify_jwt defaults to
  // true). This check is belt and braces: if that default is ever
  // changed the function still refuses anonymous callers rather than
  // quietly becoming an open proxy.
  if (!request.headers.get("authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const body = payload as Record<string, unknown> | null;

  // -------------------------------------------------------------------
  // PASTE PATH
  //
  // The fetch path below declares an honest user agent and is refused by
  // sites that block bots. Rather than impersonate a browser to take
  // bandwidth that was deliberately withheld, the client may send the
  // page content the user already has open.
  //
  // Nothing is fetched on this path, so there is no SSRF surface at all.
  // The document is capped, then run through exactly the same parser and
  // the same sanitiser as a fetched page, so the output shape and the
  // escaping guarantees are identical.
  // -------------------------------------------------------------------
  if (typeof body?.html === "string") {
    const documentBytes = new TextEncoder().encode(body.html).byteLength;
    if (documentBytes === 0 || documentBytes > MAX_BYTES) {
      return json({ error: "invalid_document" }, 400);
    }

    // An attribution URL is optional. It is validated to the same standard
    // as a fetched URL because it is stored, and recipes.source_url carries
    // a CHECK constraint, but it is never requested.
    let attribution: URL | null = null;
    if (body.url !== undefined) {
      attribution = validateUrl(body.url);
      if (!attribution) return json({ error: "invalid_url" }, 400);
    }

    const pasted = fromJsonLd(body.html) ?? fromText(body.html);
    if (pasted.ingredients.length === 0 && pasted.steps.length === 0) {
      return json({ error: "no_recipe_found" }, 422);
    }

    return json({
      title: pasted.title,
      description: pasted.description,
      ingredients: pasted.ingredients,
      steps: pasted.steps,
      servings: pasted.servings,
      notes: pasted.notes,
      truncated: pasted.truncated,
      source_url: attribution ? attribution.toString() : null,
      source: attribution ? sourceFor(attribution.hostname) : "manual",
    });
  }

  const url = validateUrl(body?.url);
  if (!url) {
    return json({ error: "invalid_url" }, 400);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TOTAL_TIMEOUT_MS);

  try {
    const html = await fetchHtml(url, controller.signal);

    const parsed = fromJsonLd(html) ?? fromText(html);

    if (parsed.ingredients.length === 0 && parsed.steps.length === 0) {
      return json({ error: "no_recipe_found" }, 422);
    }

    return json({
      title: parsed.title,
      description: parsed.description,
      ingredients: parsed.ingredients,
      steps: parsed.steps,
      servings: parsed.servings,
      notes: parsed.notes,
      truncated: parsed.truncated,
      source_url: url.toString(),
      source: sourceFor(url.hostname),
    });
  } catch (error) {
    // The upstream failure reason is logged, never returned. Telling a
    // caller the difference between "timed out", "refused" and "not
    // found" turns this endpoint into a network scanner.
    console.error("import failed", {
      host: url.hostname,
      reason: error instanceof Error ? error.message : "unknown",
    });
    return json({ error: "fetch_failed" }, 422);
  } finally {
    clearTimeout(timer);
  }
});
