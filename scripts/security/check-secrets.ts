/**
 * Secret scanning — docs/standards/SECURITY_STANDARDS.md §3, CG-S5-PH0-015
 * (Prompt 94, Security Baseline Controls). Scans every tracked file for five
 * well-known secret shapes (not a generic entropy heuristic, which would
 * flag this repository's own legitimate high-entropy content — lockfile
 * integrity hashes, UUIDs, fingerprints).
 *
 * Never prints a matched value, even redacted-partial — only file:line:kind
 * (docs/standards/SECURITY_STANDARDS.md §2's leakage-prevention rule applied
 * reflexively to the scanner itself).
 *
 * CLI: node --experimental-strip-types scripts/security/check-secrets.ts
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

export type SecretKind = "AWS_ACCESS_KEY_ID" | "PRIVATE_KEY_BLOCK" | "STRIPE_LIVE_KEY" | "JWT_SHAPED_TOKEN" | "GENERIC_HARDCODED_SECRET_ASSIGNMENT";

export interface SecretFinding {
  readonly file: string;
  readonly line: number;
  readonly kind: SecretKind;
}

const AWS_ACCESS_KEY_ID = /\bAKIA[0-9A-Z]{16}\b/;
const PRIVATE_KEY_BLOCK = /-----BEGIN\s+(RSA|EC|OPENSSH|DSA|ENCRYPTED)?\s?PRIVATE KEY-----/;
const STRIPE_LIVE_KEY = /\bsk_live_[0-9a-zA-Z]{16,}\b/;
const JWT_SHAPED_TOKEN = /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/;
const GENERIC_HARDCODED_SECRET_ASSIGNMENT = /\b(secret|password|token|api[_-]?key|private[_-]?key)\b\s*[:=]\s*["']([A-Za-z0-9+/=_.-]{20,})["']/i;

// Always-checked patterns (unambiguous, low-false-positive-risk shapes) —
// safe to apply even to test fixture files, since a legitimate test would
// only ever match these if deliberately testing the scanner itself.
const ALWAYS_PATTERNS: readonly [SecretKind, RegExp][] = [
  ["AWS_ACCESS_KEY_ID", AWS_ACCESS_KEY_ID],
  ["PRIVATE_KEY_BLOCK", PRIVATE_KEY_BLOCK],
  ["STRIPE_LIVE_KEY", STRIPE_LIVE_KEY],
  ["JWT_SHAPED_TOKEN", JWT_SHAPED_TOKEN],
];

// Excluded from GENERIC_HARDCODED_SECRET_ASSIGNMENT only — *.test.ts files
// legitimately construct short fake credential-shaped strings to test
// redaction (docs/standards/SECURITY_STANDARDS.md §3's disclosed design:
// the >=20-char threshold already excludes most of those; this closes the
// remaining gap without weakening the four unambiguous-shape patterns above,
// which still scan every file including tests).
function isTestFile(file: string): boolean {
  return file.endsWith(".test.ts") || file.endsWith(".test.tsx");
}

/**
 * This scanner's own source/test files intentionally contain matching
 * fixtures to prove detection works — scanning them would be a false
 * positive against itself, the same self-referential-exclusion reasoning
 * scripts/standards/check-suppressions.ts already established
 * (docs/build-log/phase-00/PH0-89.md §5).
 */
const SELF_REFERENTIAL_EXCLUSIONS = new Set(["scripts/security/check-secrets.ts", "scripts/security/check-secrets.test.ts"]);

// Noise, not a human-typed-secret surface — dependency integrity hashes.
const FILE_EXCLUSIONS = new Set(["pnpm-lock.yaml"]);

export function scanContent(file: string, content: string): SecretFinding[] {
  const findings: SecretFinding[] = [];
  const lines = content.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? "";
    for (const [kind, pattern] of ALWAYS_PATTERNS) {
      if (pattern.test(line)) {
        findings.push({ file, line: i + 1, kind });
      }
    }
    if (!isTestFile(file) && GENERIC_HARDCODED_SECRET_ASSIGNMENT.test(line)) {
      findings.push({ file, line: i + 1, kind: "GENERIC_HARDCODED_SECRET_ASSIGNMENT" });
    }
  }
  return findings;
}

function listTrackedFiles(): string[] {
  return execFileSync("git", ["ls-files"], { encoding: "utf8" })
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
}

export function scanRepository(): SecretFinding[] {
  const files = listTrackedFiles().filter((f) => !SELF_REFERENTIAL_EXCLUSIONS.has(f) && !FILE_EXCLUSIONS.has(f));
  const findings: SecretFinding[] = [];
  for (const file of files) {
    let content: string;
    try {
      content = readFileSync(file, "utf8");
    } catch {
      continue; // binary/unreadable-as-utf8 file — not a text secret-leak surface this scanner can assess
    }
    findings.push(...scanContent(file, content));
  }
  return findings;
}

function main(): void {
  const findings = scanRepository();
  if (findings.length === 0) {
    console.log("✔ no secret-shaped pattern found in any tracked file.");
    return;
  }
  for (const f of findings) {
    // Deliberately never includes the matched value — file:line:kind only.
    console.error(`✖ ${f.file}:${f.line} [${f.kind}]`);
  }
  console.error(`\n${findings.length} potential secret(s) found — see docs/standards/SECURITY_STANDARDS.md §3. Rotate any real credential before removing it from history.`);
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
