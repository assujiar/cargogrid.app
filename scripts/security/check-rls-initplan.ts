/**
 * `auth_rls_initplan` regression guard — ISS-2026-240. Formalizes into a real,
 * committed, `pnpm run`-able tool the ad hoc text-grep methodology this
 * repository's own hardening checkpoints (`HDN-379`, and the original
 * 65-migration fix before it) have re-run *by hand* at every checkpoint —
 * no persisted guard script existed anywhere in this repository before this
 * fix (confirmed: `grep -rn "auth_rls_initplan" scripts/` found zero hits
 * before this file was added).
 *
 * Two distinct checks, over every `create policy`/`alter policy` statement
 * across all `supabase/migrations/*.sql` files, in filename (chronological)
 * order:
 *
 * 1. **BARE_AUTH_CALL (regression, fails the guard)** — a literal, unwrapped
 *    `auth.uid()`/`auth.jwt()`/`auth.role()` inside a policy's own `using`/
 *    `with check` clause, not wrapped in `(select ...)`. This is the
 *    original 65-migration-fix's own detection target; re-swept clean at
 *    `HDN-379` (582 policy statements, 235 call sites, zero bare calls).
 *
 * 2. **DEFAULT_PARAM_INITPLAN_BLIND_SPOT (informational, does NOT fail the
 *    guard) / UNEXPECTED_AUTH_PARAM_OVERRIDE (fails the guard)** — the
 *    structurally-invisible variant ISS-2026-240 itself found: an RLS helper
 *    function declared with a trailing `default auth.uid()`/`auth.jwt()`/
 *    `auth.role()` parameter (self-discovered from every `create [or
 *    replace] function app.*` signature in the same migration set — no
 *    hardcoded function-name list to go stale), called from inside a policy
 *    clause. Per ISS-2026-240's own disposition (Low, informational, this
 *    repository's own load-bearing architectural convention since the first
 *    migration, NOT a regression, NOT fixed by reworking ~40 files' worth of
 *    call sites), a call that simply omits the trailing default-auth
 *    parameter is reported but never fails the guard. A call that DOES
 *    supply that trailing parameter explicitly is checked against the one
 *    safe shape (`(select auth.<fn>())`, this repository's own established
 *    hoisting idiom) — anything else supplied there is a real, different,
 *    higher-priority finding (a caller substituting some OTHER value for the
 *    caller's own identity) and DOES fail the guard.
 *
 * CLI: node --experimental-strip-types scripts/security/check-rls-initplan.ts
 */

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const MIGRATIONS_DIR = "supabase/migrations";

/**
 * Blanks out `-- ...` line-comment text (never inside a single-quoted
 * string, tracked with `''`-escape awareness) with spaces, preserving every
 * other character's exact position -- so every line/column number computed
 * downstream from the returned string still matches the original file. Guards
 * both parsers below against a real false-positive this repository's own
 * prose comments would otherwise trigger: a comment merely *mentioning* the
 * words "create policy"/"alter policy" (e.g. "DROP POLICY + CREATE POLICY
 * for RLS") is not a real policy statement, and a comment mentioning
 * "default auth.uid()" is not a real function signature.
 */
export function blankLineComments(content: string): string {
  const chars = content.split("");
  let inString = false;
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    if (ch === "'") {
      inString = !inString;
      continue;
    }
    if (!inString && ch === "-" && chars[i + 1] === "-") {
      for (let j = i; j < chars.length && chars[j] !== "\n"; j++) {
        chars[j] = " ";
      }
    }
  }
  return chars.join("");
}

export interface BareAuthFinding {
  readonly file: string;
  readonly line: number;
  readonly authFn: "uid" | "jwt" | "role";
  readonly snippet: string;
}

export type HelperFindingKind = "DEFAULT_PARAM_INITPLAN_BLIND_SPOT" | "EXPLICIT_HOISTED_SAFE" | "UNEXPECTED_AUTH_PARAM_OVERRIDE";

export interface HelperCallFinding {
  readonly file: string;
  readonly line: number;
  readonly functionName: string;
  readonly kind: HelperFindingKind;
  readonly snippet: string;
}

export interface FunctionSignature {
  readonly name: string; // e.g. "app.has_active_tenant_membership"
  readonly paramCount: number;
  readonly defaultAuthFn: "uid" | "jwt" | "role" | null; // set only when the LAST param defaults to auth.<fn>()
}

export interface PolicyStatement {
  readonly file: string;
  readonly startLine: number;
  readonly text: string;
}

// ---- 1. Parse `create [or replace] function app.<name>(...)` signatures ----

/**
 * Splits a raw parameter-list string on top-level commas only (does not
 * split inside a nested `(...)`, e.g. `default auth.uid()` or
 * `default (select 1)`).
 */
function splitTopLevelArgs(argsText: string): string[] {
  const trimmed = argsText.trim();
  if (trimmed === "") return [];
  const parts: string[] = [];
  let depth = 0;
  let current = "";
  for (const ch of trimmed) {
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
    if (ch === "," && depth === 0) {
      parts.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  parts.push(current);
  return parts.map((p) => p.trim()).filter((p) => p !== "");
}

/** Finds the index of the `)` matching the `(` at `openIndex`. */
function findMatchingParen(text: string, openIndex: number): number {
  let depth = 0;
  for (let i = openIndex; i < text.length; i++) {
    if (text[i] === "(") depth++;
    else if (text[i] === ")") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

const AUTH_DEFAULT_PATTERN = /default\s+auth\.(uid|jwt|role)\(\s*\)\s*$/i;

export function parseFunctionSignatures(rawContent: string): FunctionSignature[] {
  const content = blankLineComments(rawContent);
  const signatures: FunctionSignature[] = [];
  const headerPattern = /create\s+(?:or\s+replace\s+)?function\s+(app\.\w+)\s*\(/gi;
  let match: RegExpExecArray | null;
  while ((match = headerPattern.exec(content)) !== null) {
    const name = match[1] ?? "";
    const openParenIndex = headerPattern.lastIndex - 1;
    const closeParenIndex = findMatchingParen(content, openParenIndex);
    if (closeParenIndex === -1) continue;
    const argsText = content.slice(openParenIndex + 1, closeParenIndex);
    const args = splitTopLevelArgs(argsText);
    const lastArg = args[args.length - 1] ?? "";
    const defaultMatch = AUTH_DEFAULT_PATTERN.exec(lastArg);
    signatures.push({
      name,
      paramCount: args.length,
      defaultAuthFn: defaultMatch ? (defaultMatch[1]?.toLowerCase() as "uid" | "jwt" | "role") : null,
    });
  }
  return signatures;
}

// ---- 2. Parse `create policy` / `alter policy` statements ----

/**
 * Policy statements in this codebase's migrations never contain a semicolon
 * inside their own body (no nested `$$...$$` block, no multi-statement
 * clause) — verified by direct sampling before relying on this assumption —
 * so "up to the next top-level `;`" is a safe statement boundary.
 */
export function parsePolicyStatements(file: string, rawContent: string): PolicyStatement[] {
  const content = blankLineComments(rawContent);
  const statements: PolicyStatement[] = [];
  const headerPattern = /\b(create|alter)\s+policy\b/gi;
  let match: RegExpExecArray | null;
  while ((match = headerPattern.exec(content)) !== null) {
    const start = match.index;
    const terminatorIndex = content.indexOf(";", start);
    if (terminatorIndex === -1) continue;
    const text = content.slice(start, terminatorIndex + 1);
    const startLine = content.slice(0, start).split("\n").length;
    statements.push({ file, startLine, text });
  }
  return statements;
}

// ---- 3. Check 1: bare/unwrapped auth.*() inside a policy statement ----

const AUTH_CALL_PATTERN = /auth\.(uid|jwt|role)\(\s*\)/gi;
// Safe iff the call is wrapped as `(select auth.<fn>())` — i.e. immediately
// preceded (ignoring whitespace) by `select` inside its own enclosing `(`.
// Mirrors the original 65-migration fix's own hoisting idiom, live-verified
// as the shape this repository actually uses everywhere it's already fixed
// (e.g. `(tenant_id is null and auth_user_id = (select auth.uid()))`).
const HOISTED_SELECT_PREFIX = /\(\s*select\s+$/i;

export function findBareAuthCalls(file: string, statement: PolicyStatement): BareAuthFinding[] {
  const findings: BareAuthFinding[] = [];
  let match: RegExpExecArray | null;
  AUTH_CALL_PATTERN.lastIndex = 0;
  while ((match = AUTH_CALL_PATTERN.exec(statement.text)) !== null) {
    const before = statement.text.slice(0, match.index);
    if (HOISTED_SELECT_PREFIX.test(before)) continue; // wrapped — safe, not a regression
    const lineOffset = statement.text.slice(0, match.index).split("\n").length - 1;
    findings.push({
      file,
      line: statement.startLine + lineOffset,
      authFn: (match[1]?.toLowerCase() as "uid" | "jwt" | "role") ?? "uid",
      snippet: statement.text.slice(Math.max(0, match.index - 40), match.index + 20).replace(/\s+/g, " ").trim(),
    });
  }
  return findings;
}

// ---- 4. Check 2: default-auth-param helper-function calls inside a policy ----

function findFunctionCallSites(text: string, functionName: string): { argsText: string; index: number }[] {
  const shortName = functionName.replace(/^app\./, "");
  const callPattern = new RegExp(`\\bapp\\.${shortName}\\s*\\(`, "g");
  const sites: { argsText: string; index: number }[] = [];
  let match: RegExpExecArray | null;
  while ((match = callPattern.exec(text)) !== null) {
    const openParenIndex = callPattern.lastIndex - 1;
    const closeParenIndex = findMatchingParen(text, openParenIndex);
    if (closeParenIndex === -1) continue;
    sites.push({ argsText: text.slice(openParenIndex + 1, closeParenIndex), index: match.index });
  }
  return sites;
}

const EXPLICIT_HOISTED_ARG_PATTERN = /^\(\s*select\s+auth\.(uid|jwt|role)\(\s*\)\s*\)$/i;

export function findHelperCallSites(file: string, statement: PolicyStatement, registry: readonly FunctionSignature[]): HelperCallFinding[] {
  const findings: HelperCallFinding[] = [];
  for (const sig of registry) {
    if (sig.defaultAuthFn === null) continue;
    for (const site of findFunctionCallSites(statement.text, sig.name)) {
      const args = splitTopLevelArgs(site.argsText);
      const lineOffset = statement.text.slice(0, site.index).split("\n").length - 1;
      const line = statement.startLine + lineOffset;
      const snippet = `${sig.name}(${site.argsText})`.replace(/\s+/g, " ").trim();
      if (args.length === sig.paramCount - 1) {
        // Trailing default-auth param omitted -- the invisible-to-text-grep
        // shape ISS-2026-240 exists to document. Informational only.
        findings.push({ file, line, functionName: sig.name, kind: "DEFAULT_PARAM_INITPLAN_BLIND_SPOT", snippet });
      } else if (args.length === sig.paramCount) {
        const lastArg = args[args.length - 1] ?? "";
        if (EXPLICIT_HOISTED_ARG_PATTERN.test(lastArg)) {
          findings.push({ file, line, functionName: sig.name, kind: "EXPLICIT_HOISTED_SAFE", snippet });
        } else {
          // Something other than this repository's own `(select auth.<fn>())`
          // idiom was supplied for the parameter that otherwise defaults to
          // the caller's own identity -- a real, separate, higher-priority
          // finding (a possible identity-substitution defect), not the
          // performance-only blind spot this guard otherwise documents.
          findings.push({ file, line, functionName: sig.name, kind: "UNEXPECTED_AUTH_PARAM_OVERRIDE", snippet });
        }
      }
      // A call with fewer than paramCount - 1 args doesn't supply every
      // required non-default parameter and would fail to compile -- not a
      // shape this guard needs to classify (SQL itself already guards it).
    }
  }
  return findings;
}

// ---- 5. Repository-wide scan ----

export interface ScanResult {
  readonly bareAuthRegressions: BareAuthFinding[];
  readonly blindSpotUses: HelperCallFinding[];
  readonly explicitHoistedSafe: HelperCallFinding[];
  readonly unexpectedOverrides: HelperCallFinding[];
}

function listMigrationFiles(): string[] {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort(); // filename-timestamp order == chronological order in this repo
}

export function scanRepository(): ScanResult {
  const files = listMigrationFiles();
  // Keyed by function name so a later CREATE OR REPLACE FUNCTION (a later
  // migration file, since files are processed in chronological/filename
  // order) overwrites an earlier signature -- mirroring how Postgres itself
  // only ever has one live signature per name. Without this, a function
  // redeclared even once would be double-counted at every one of its own
  // call sites (each call matched once per registry entry).
  const registryByName = new Map<string, FunctionSignature>();
  const contents = new Map<string, string>();
  for (const file of files) {
    const content = readFileSync(join(MIGRATIONS_DIR, file), "utf8");
    contents.set(file, content);
    for (const sig of parseFunctionSignatures(content)) {
      registryByName.set(sig.name, sig);
    }
  }
  const registry = [...registryByName.values()];

  const bareAuthRegressions: BareAuthFinding[] = [];
  const blindSpotUses: HelperCallFinding[] = [];
  const explicitHoistedSafe: HelperCallFinding[] = [];
  const unexpectedOverrides: HelperCallFinding[] = [];

  for (const file of files) {
    const content = contents.get(file) ?? "";
    for (const statement of parsePolicyStatements(file, content)) {
      bareAuthRegressions.push(...findBareAuthCalls(file, statement));
      for (const finding of findHelperCallSites(file, statement, registry)) {
        if (finding.kind === "DEFAULT_PARAM_INITPLAN_BLIND_SPOT") blindSpotUses.push(finding);
        else if (finding.kind === "EXPLICIT_HOISTED_SAFE") explicitHoistedSafe.push(finding);
        else unexpectedOverrides.push(finding);
      }
    }
  }

  return { bareAuthRegressions, blindSpotUses, explicitHoistedSafe, unexpectedOverrides };
}

function main(): void {
  const result = scanRepository();
  const hardFailures = result.bareAuthRegressions.length + result.unexpectedOverrides.length;

  for (const f of result.bareAuthRegressions) {
    console.error(`✖ ${f.file}:${f.line} [BARE_AUTH_CALL] unwrapped auth.${f.authFn}() in a policy clause -- wrap as (select auth.${f.authFn}()) … ${f.snippet}`);
  }
  for (const f of result.unexpectedOverrides) {
    console.error(`✖ ${f.file}:${f.line} [UNEXPECTED_AUTH_PARAM_OVERRIDE] ${f.functionName} called with a non-"(select auth.*())" value in its default-auth parameter slot … ${f.snippet}`);
  }

  if (hardFailures > 0) {
    console.error(`\n${hardFailures} auth_rls_initplan regression(s)/override(s) found across ${result.bareAuthRegressions.length + result.blindSpotUses.length + result.explicitHoistedSafe.length + result.unexpectedOverrides.length} scanned call sites.`);
  } else {
    console.log(`✔ no auth_rls_initplan regression found (0 bare auth.*() calls, 0 unexpected default-auth-param overrides).`);
  }

  if (result.blindSpotUses.length > 0) {
    console.log(
      `\nℹ ${result.blindSpotUses.length} call site(s) rely on a helper function's own default auth.*() parameter inside a policy clause (ISS-2026-240's own documented, informational, not-a-regression blind spot -- does not fail this guard):`,
    );
    for (const f of result.blindSpotUses) {
      console.log(`  ${f.file}:${f.line} ${f.functionName}`);
    }
  }
  if (result.explicitHoistedSafe.length > 0) {
    console.log(`\nℹ ${result.explicitHoistedSafe.length} call site(s) already explicitly hoist (select auth.*()) into a default-auth-param helper function -- confirmed already safe.`);
  }

  if (hardFailures > 0) process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
