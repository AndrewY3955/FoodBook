// Cross-checks the client URL rule against the same corpus the server
// CHECK constraint is run over. This validates the RULE, expressed in
// JS. It does not execute the Dart. See VERIFICATION.md.
const fs = require('fs');
const corpus = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

const DANGEROUS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]/g;
const BREAKOUT  = /[\s<>"'`\\{}|^]/;

function safeUrl(input) {
  const trimmed = input.trim().replace(DANGEROUS, '');
  if (trimmed.length === 0 || trimmed.length > 2048) return null;
  if (BREAKOUT.test(trimmed)) return null;
  // Dart's Uri.parse leaves host empty for "https:///x"; the WHATWG URL
  // parser in Node normalises it to host="x". Reject the empty authority
  // explicitly so this port matches Dart and the server regex.
  if (/^[A-Za-z][A-Za-z0-9+.-]*:\/\/\//.test(trimmed)) return null;
  let uri;
  try { uri = new URL(trimmed); } catch { return null; }
  if (uri.protocol !== 'https:') return null;
  if (uri.hostname.length === 0) return null;
  if (uri.username.length > 0 || uri.password.length > 0) return null;
  return uri.toString();
}

let fail = 0;
for (const [input, expected] of corpus) {
  const actual = safeUrl(input) !== null;
  const ok = actual === expected;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  client  ${expected ? 'accept' : 'reject'}  ${JSON.stringify(input)}`);
}
process.exit(fail === 0 ? 0 : 1);
