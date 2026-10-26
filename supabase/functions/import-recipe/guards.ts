// =====================================================================
// guards.ts
//
// The pure, side-effect-free half of import-recipe: URL validation,
// SSRF address screening, and content stripping.
//
// These live in their own module for one reason: they are the security
// boundary of the function, and a module with no Deno.serve and no
// network calls can be executed and tested by any JavaScript runtime.
// The handler in index.ts imports from here, so what the tests exercise
// is the code that ships, not a copy of it.
// =====================================================================

export const MAX_BYTES = 1_500_000;       // 1.5 MB of HTML is a very long page
const TOTAL_TIMEOUT_MS = 8_000;
const MAX_REDIRECTS = 3;
const MAX_INGREDIENTS = 60;
const MAX_STEPS = 40;
export const MAX_LINE = 200;

// ---------------------------------------------------------------------
// URL validation
// ---------------------------------------------------------------------

/** Literal addresses that must never be fetched from inside the isolate. */
export function isForbiddenHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, "");

  if (host === "localhost" || host.endsWith(".localhost")) return true;
  if (host.endsWith(".internal") || host.endsWith(".local")) return true;

  // IPv6 loopback and unique-local / link-local ranges.
  if (host === "::1" || host === "::") return true;
  if (/^f[cd][0-9a-f]{2}:/i.test(host)) return true;
  if (/^fe80:/i.test(host)) return true;

  const v4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    if (a === 0 || a === 10 || a === 127) return true;          // this/private/loopback
    if (a === 169 && b === 254) return true;                    // link-local + metadata
    if (a === 172 && b >= 16 && b <= 31) return true;           // private
    if (a === 192 && b === 168) return true;                    // private
    if (a === 100 && b >= 64 && b <= 127) return true;          // carrier NAT
    if (a >= 224) return true;                                  // multicast / reserved
  }

  // Common metadata endpoints by name.
  if (host === "metadata.google.internal") return true;

  return false;
}

export function validateUrl(raw: unknown): URL | null {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 2048) {
    return null;
  }
  // Reject breakout characters before parsing, matching the client
  // sanitiser and the database CHECK.
  if (/[\s<>"'`\\{}|^]/.test(raw)) return null;

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }

  if (url.protocol !== "https:") return null;
  if (url.username || url.password) return null;
  if (!url.hostname || isForbiddenHost(url.hostname)) return null;
  if (url.port && url.port !== "443") return null;

  return url;
}

// ---------------------------------------------------------------------
// Stripping
// ---------------------------------------------------------------------

/** Removes whole dangerous elements, then tags, then normalises space. */
export function stripHtml(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<(script|style|noscript|template|svg|iframe|object|embed)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|li|div|h[1-6]|tr)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/\r/g, "")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n");
}

/**
 * Final pass over any string that will be returned.
 *
 * Strips control and bidi characters, anything that looks like a scheme
 * handler, inline event attributes, and template-injection delimiters.
 * The output of this function is what the Flutter client will put in a
 * text field and the database will store, so it is the last chance to
 * drop a payload.
 */
export function sanitiseLine(input: string, maxLength = MAX_LINE): string {
  return input
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]/g, "")
    .replace(/\b(javascript|vbscript|data|file|blob)\s*:/gi, " ")
    .replace(/\bon[a-z]+\s*=/gi, " ")
    .replace(/[{}<>]/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim()
    .slice(0, maxLength);
}
