// =====================================================================
// guards.test.ts
//
// Run:  node --experimental-strip-types guards.test.ts
//   or: deno test --allow-none guards.test.ts
//
// This exercises the real exported functions from guards.ts, which is
// the same module index.ts imports. Every SSRF case here is a negative
// control: the assertion is that the address is REFUSED, and the file
// deliberately includes the addresses that a naive https-only check
// would happily fetch.
// =====================================================================

import {
  isForbiddenHost,
  sanitiseLine,
  stripHtml,
  validateUrl,
} from "./guards.ts";

let pass = 0;
let fail = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) {
    pass++;
    console.log(`PASS  ${label}`);
  } else {
    fail++;
    console.log(
      `FAIL  ${label}   expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`,
    );
  }
}

function accepts(label: string, url: string): void {
  check(label, validateUrl(url) !== null, true);
}

function refuses(label: string, url: string): void {
  check(label, validateUrl(url) === null, true);
}

console.log("\n===== 1. URLs that must be accepted =====");
accepts("1.1  ordinary recipe page", "https://example.test/recipes/shakshuka");
accepts("1.2  query string", "https://example.test/r?id=12&ref=x");
accepts("1.3  instagram reel", "https://www.instagram.com/reel/C0000000000/");
accepts("1.4  tiktok video", "https://www.tiktok.com/@cook/video/123");
accepts("1.5  explicit port 443", "https://example.test:443/r");

console.log("\n===== 2. Scheme and syntax negative controls =====");
refuses("2.1  plain http", "http://example.test/r");
refuses("2.2  javascript scheme", "javascript:alert(1)");
refuses("2.3  data scheme", "data:text/html,<script>alert(1)</script>");
refuses("2.4  file scheme", "file:///etc/passwd");
refuses("2.5  ftp scheme", "ftp://example.test/r");
refuses("2.6  protocol-relative", "//example.test/r");
refuses("2.7  embedded credentials", "https://user:pass@example.test/r");
refuses("2.8  whitespace smuggling", "https://example.test/ onerror=x");
refuses("2.9  quote breakout", 'https://example.test/"><script>');
refuses("2.10 backslash", "https://example.test/a\\b");
refuses("2.11 non-443 port", "https://example.test:8080/r");
refuses("2.12 empty string", "");
refuses("2.13 not a url", "just some text");
refuses("2.14 non-string input", 12345 as unknown as string);
refuses("2.15 over length", "https://example.test/" + "a".repeat(2100));

console.log("\n===== 3. SSRF negative controls (the ones that matter) =====");
refuses("3.1  loopback by name", "https://localhost/admin");
refuses("3.2  loopback v4", "https://127.0.0.1/admin");
refuses("3.3  loopback v4 alt", "https://127.9.9.9/admin");
refuses("3.4  this-network 0.x", "https://0.0.0.0/");
refuses("3.5  private 10.x", "https://10.1.2.3/");
refuses("3.6  private 172.16.x", "https://172.16.0.1/");
refuses("3.7  private 172.31.x", "https://172.31.255.254/");
refuses("3.8  private 192.168.x", "https://192.168.1.1/");
refuses("3.9  AWS/GCP metadata", "https://169.254.169.254/latest/meta-data/");
refuses("3.10 GCP metadata by name", "https://metadata.google.internal/");
refuses("3.11 carrier NAT 100.64.x", "https://100.64.0.1/");
refuses("3.12 multicast", "https://239.1.1.1/");
refuses("3.13 .internal suffix", "https://vault.internal/");
refuses("3.14 .local suffix", "https://printer.local/");
refuses("3.15 IPv6 loopback", "https://[::1]/");
refuses("3.16 IPv6 link-local", "https://[fe80::1]/");
refuses("3.17 IPv6 unique-local", "https://[fd00::1]/");

console.log("\n===== 4. Public addresses must still pass =====");
check("4.1  172.32.x is public", isForbiddenHost("172.32.0.1"), false);
check("4.2  172.15.x is public", isForbiddenHost("172.15.0.1"), false);
check("4.3  100.63.x is public", isForbiddenHost("100.63.0.1"), false);
check("4.4  8.8.8.8 is public", isForbiddenHost("8.8.8.8"), false);
check("4.5  ordinary host", isForbiddenHost("example.test"), false);

console.log("\n===== 5. Content stripping =====");
check(
  "5.1  script element removed whole",
  stripHtml("<p>before</p><script>alert(1)</script><p>after</p>").includes("alert"),
  false,
);
check(
  "5.2  style element removed whole",
  stripHtml("<style>body{x:url(javascript:1)}</style>text").includes("javascript"),
  false,
);
check(
  "5.3  comment removed",
  stripHtml("a<!-- <script>alert(1)</script> -->b").includes("alert"),
  false,
);
check(
  "5.4  iframe removed",
  stripHtml("<iframe src=https://evil.test></iframe>ok").includes("evil"),
  false,
);
check(
  "5.5  visible text survives",
  stripHtml("<h1>Shakshuka</h1><li>2 eggs</li>").includes("Shakshuka"),
  true,
);

console.log("\n===== 6. Line sanitisation =====");
check(
  "6.1  javascript scheme neutralised",
  sanitiseLine("click javascript:alert(1) now").includes("javascript:"),
  false,
);
check(
  "6.2  event handler neutralised",
  sanitiseLine('x onerror=alert(1)').includes("onerror="),
  false,
);
check(
  "6.3  angle brackets removed",
  sanitiseLine("<script>alert(1)</script>").includes("<"),
  false,
);
check(
  "6.4  template delimiters removed",
  sanitiseLine("{{ 7*7 }}").includes("{"),
  false,
);
check(
  "6.5  bidi override stripped",
  sanitiseLine("safe\u202Etxt.exe").includes("\u202E"),
  false,
);
check(
  "6.6  null byte stripped",
  sanitiseLine("a\u0000b"),
  "ab",
);
check(
  "6.7  length is capped",
  sanitiseLine("x".repeat(500)).length <= 200,
  true,
);
check(
  "6.8  ordinary ingredient line survives intact",
  sanitiseLine("2 tbsp olive oil"),
  "2 tbsp olive oil",
);

console.log("\n---------------------------------------------");
console.log(`PASS ${pass}   FAIL ${fail}`);

if (fail > 0 && typeof process !== "undefined") process.exitCode = 1;
