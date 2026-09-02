/**
 * ISS-2026-146 classifier — cross-tenant `tenant_id` disclosure via exception
 * message text.
 *
 * The finding's own reproduced shape is exact: a `SECURITY DEFINER` function
 * looks a record up by its bare `id` (no tenant scoping, since the caller
 * doesn't yet know which tenant owns it), THEN evaluates the actor's
 * authority against `v_record.tenant_id`, and on denial raises
 *
 *   raise exception 'insufficient_authority: identity % lacks %:% (%) for
 *   tenant %', p_actor_auth_user_id, ..., v_record.tenant_id using errcode =
 *   'insufficient_privilege';
 *
 * — disclosing the looked-up record's REAL tenant_id to a caller who has not
 * yet been shown to have any relationship to that tenant. A blind grep count
 * of this template's occurrences is not evidence of risk: the overwhelming
 * majority interpolate `p_tenant_id`, a value the CALLER itself supplied —
 * echoing it back is not a disclosure. This script tells the two apart by
 * reading, for every row-derived occurrence, whether the SELECT that
 * populated the row variable was itself tenant-scoped by the time the
 * raise fires:
 *
 *   - SAFE_CALLER_SUPPLIED    — final arg is exactly `p_tenant_id`. Nothing
 *     new is disclosed; the caller already knows the value.
 *   - SAFE_TENANT_SCOPED_LOOKUP — final arg is a row/local variable, but the
 *     nearest preceding `select ... into <var> ... from ... where ...` that
 *     populated it already filters by `tenant_id = p_tenant_id` (or
 *     equivalent), so `not found` already excludes foreign-tenant rows
 *     before this line can ever run — the disclosed tenant_id can only be
 *     one the caller already supplied.
 *   - RISK_UNSCOPED_LOOKUP    — final arg is a row/local variable whose
 *     populating SELECT has no tenant scoping at all (looked up by bare
 *     `id`). This is the live-reproduced failure shape: a caller with zero
 *     relationship to the record's real tenant learns that tenant's UUID
 *     from the denial message alone.
 *   - AMBIGUOUS               — the populating assignment could not be
 *     resolved with confidence (set via a helper-function call, a JOIN, a
 *     multi-statement chain, a trigger's NEW/OLD row, etc.) — needs a human
 *     read, never auto-fixed.
 *
 * CLI: node --experimental-strip-types scripts/security/classify-tenant-id-error-disclosure.ts
 */

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const MIGRATIONS_DIR = "supabase/migrations";

// Matches the finding's own cited template shape: a raise exception whose
// format string literally ends "...for tenant %". This is deliberately
// narrower than "any raise exception mentioning tenant_id anywhere" — it is
// the exact, dominant, repeated template ISS-2026-146 itself names and
// counts (2,087 -> 2,335 -> 2,384 across its own re-measurements).
const RAISE_HEADER_PATTERN = /raise\s+exception\s+'([^']*for tenant %[^']*)'/gi;

export type Classification =
  | "SAFE_CALLER_SUPPLIED"
  | "SAFE_TENANT_SCOPED_LOOKUP"
  | "RISK_UNSCOPED_LOOKUP"
  | "AMBIGUOUS";

export interface Finding {
  readonly file: string;
  readonly line: number;
  readonly functionName: string;
  readonly tenantExpr: string;
  readonly classification: Classification;
  readonly reason: string;
  readonly snippet: string;
}

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

function lineAt(content: string, index: number): number {
  return content.slice(0, index).split("\n").length;
}

interface FunctionBlock {
  readonly name: string;
  readonly bodyText: string;
  readonly bodyStartIndex: number;
}

/**
 * Splits a migration file into `create [or replace] function <name>(...) ...
 * as $tag$ ... $tag$` blocks. Handles both bare `$$` and named dollar-quote
 * tags (`$function$`, `$wrap$`) actually used in this repository.
 */
export function parseFunctionBlocks(content: string): FunctionBlock[] {
  const blocks: FunctionBlock[] = [];
  const headerPattern = /create\s+(?:or\s+replace\s+)?function\s+([a-zA-Z0-9_.]+)\s*\(/gi;
  let match: RegExpExecArray | null;
  while ((match = headerPattern.exec(content)) !== null) {
    const name = match[1] ?? "";
    const openParenIndex = headerPattern.lastIndex - 1;
    const closeParenIndex = findMatchingParen(content, openParenIndex);
    if (closeParenIndex === -1) continue;
    // Find the `as $tag$` opening the body, within a bounded lookahead so an
    // unrelated later function's own body is never mistaken for this one's.
    // 1000 (not the original 400) -- a long `RETURNS TABLE(...)` column list can push
    // `AS $tag$` well past a short window (confirmed live: app.get_shipment_document_
    // checklist's own RETURNS TABLE clause alone is 405 chars, silently dropping its
    // block from every scan and making an already-fixed function look permanently
    // unfixed to `scanRepositoryLatestDefinitionOnly` -- the live function body was
    // correct throughout, only this script's own accounting was wrong).
    const asMatch = /as\s+(\$[a-zA-Z_]*\$)/i.exec(content.slice(closeParenIndex, closeParenIndex + 1000));
    if (!asMatch || asMatch.index === undefined) continue;
    const tag = asMatch[1] ?? "$$";
    const bodyStartIndex = closeParenIndex + asMatch.index + asMatch[0].length;
    const bodyEndIndex = content.indexOf(tag, bodyStartIndex);
    if (bodyEndIndex === -1) continue;
    blocks.push({ name, bodyText: content.slice(bodyStartIndex, bodyEndIndex), bodyStartIndex });
  }
  return blocks;
}

/**
 * Given a row/local-variable expression like `v_record.tenant_id` or
 * `v_tenant_id`, looks backward in `bodyText` (before `beforeIndex`) for the
 * statement that populated it, and decides whether that statement already
 * scoped its lookup to a caller-supplied tenant.
 */
function classifyRowDerived(bodyText: string, beforeIndex: number, tenantExpr: string): { classification: Classification; reason: string } {
  const dotMatch = /^([a-zA-Z_][a-zA-Z0-9_]*)\.tenant_id$/.exec(tenantExpr);
  const bareMatch = /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(tenantExpr) ? tenantExpr : null;
  const varName = dotMatch ? dotMatch[1] ?? "" : bareMatch ?? "";
  if (varName === "") {
    return { classification: "AMBIGUOUS", reason: "unrecognized tenant expression shape" };
  }
  // Two different shapes need two different gate-argument forms: a ROW
  // variable's membership is checked as `has_active_tenant_membership(<row>.
  // tenant_id, ...)`, but a bare local variable (e.g. `v_tenant_id`) already
  // IS the tenant id value itself -- its own gate is
  // `has_active_tenant_membership(v_tenant_id, ...)`, with no `.tenant_id`
  // suffix. Conflating the two under-detects real gates on the bare-variable
  // shape (confirmed live: app.get_vendor_bill_match_case already gates via
  // `v_tenant_id is null or not has_active_tenant_membership(v_tenant_id,
  // ...)` and was a false positive before this distinction existed).
  const gateArgExpr = dotMatch ? `${varName}\\.tenant_id` : `${varName}`;
  if (/^(new|old)$/i.test(varName)) {
    return { classification: "AMBIGUOUS", reason: "trigger NEW/OLD row -- needs manual read of the trigger's own firing context" };
  }

  const before = bodyText.slice(0, beforeIndex);

  // Simple local-variable assignment straight from a parameter: always safe.
  const directAssign = new RegExp(`\\b${varName}\\s*:=\\s*p_tenant_id\\b`, "i");
  if (directAssign.test(before)) {
    return { classification: "SAFE_TENANT_SCOPED_LOOKUP", reason: `${varName} := p_tenant_id (direct parameter assignment)` };
  }

  // Find the LAST `into [strict] <varName>` before this point, then walk
  // back to the nearest preceding `select`, and forward to the statement's
  // terminating `;`.
  const intoPattern = new RegExp(`into\\s+(?:strict\\s+)?${varName}\\b`, "gi");
  let lastInto: RegExpExecArray | null = null;
  let m: RegExpExecArray | null;
  while ((m = intoPattern.exec(before)) !== null) lastInto = m;
  if (!lastInto || lastInto.index === undefined) {
    return { classification: "AMBIGUOUS", reason: `no "into ${varName}" assignment found before this raise` };
  }
  const selectIndex = before.lastIndexOf("select", lastInto.index);
  if (selectIndex === -1) {
    return { classification: "AMBIGUOUS", reason: `"into ${varName}" found but no preceding select` };
  }
  const semicolonIndex = bodyText.indexOf(";", beforeIndex >= 0 ? lastInto.index : lastInto.index);
  const statementEnd = bodyText.indexOf(";", selectIndex);
  const statementText = statementEnd === -1 ? bodyText.slice(selectIndex, beforeIndex) : bodyText.slice(selectIndex, statementEnd + 1);

  const hasWhere = /\bwhere\b/i.test(statementText);
  const tenantScoped = hasWhere && (/tenant_id\s*=\s*p_tenant_id\b/i.test(statementText) || /\btenant_id\s*=\s*\$/i.test(statementText));
  if (tenantScoped) {
    return { classification: "SAFE_TENANT_SCOPED_LOOKUP", reason: "populating select's WHERE already filters tenant_id = p_tenant_id" };
  }

  // ISS-2026-167's own established counter-pattern: even when the lookup
  // itself is by bare id, a real membership gate between the select and this
  // raise -- `if not found or not app.has_active_tenant_membership(<row>.
  // tenant_id, <actor>) then raise <generic, no tenant_id> ... end if` --
  // already collapses "record does not exist" and "actor has zero
  // relationship to this tenant" into ONE generic denial before this line
  // can ever be reached. By the time the specific insufficient_authority
  // line fires, the actor is already a confirmed member of that tenant, so
  // its tenant_id is not a new disclosure. Scoped tightly to the SAME
  // variable's tenant_id (not just "a membership check somewhere").
  const gatePattern = new RegExp(`(has_active_tenant_membership|is_tenant_member)\\s*\\(\\s*${gateArgExpr}\\b`, "i");
  if (gatePattern.test(before.slice(selectIndex))) {
    return { classification: "SAFE_TENANT_SCOPED_LOOKUP", reason: `gated by a has_active_tenant_membership/is_tenant_member(${gateArgExpr}, ...) check before this raise (ISS-2026-167 counter-pattern)` };
  }

  if (!hasWhere) {
    return { classification: "RISK_UNSCOPED_LOOKUP", reason: "select has no WHERE clause at all, and no membership gate found before this raise" };
  }
  // A join or subquery might scope tenant indirectly -- treat as ambiguous
  // rather than guessing either way.
  if (/\bjoin\b/i.test(statementText)) {
    return { classification: "AMBIGUOUS", reason: "populating select involves a JOIN -- tenant scoping not confidently determinable from text alone" };
  }
  return { classification: "RISK_UNSCOPED_LOOKUP", reason: "populating select's WHERE has no tenant_id scoping, and no membership gate found before this raise -- looked up by bare id" };
}

function classifyBlock(file: string, content: string, block: FunctionBlock): Finding[] {
  const findings: Finding[] = [];
  RAISE_HEADER_PATTERN.lastIndex = 0;
  let headerMatch: RegExpExecArray | null;
  while ((headerMatch = RAISE_HEADER_PATTERN.exec(block.bodyText)) !== null) {
    const fmtEnd = headerMatch.index + headerMatch[0].length;
    const terminator = block.bodyText.indexOf(";", fmtEnd);
    if (terminator === -1) continue;
    const rest = block.bodyText.slice(fmtEnd, terminator);
    // rest looks like: `, arg1, arg2, ... argN\n  using errcode = '...'`
    const usingSplit = /\busing\b/i.exec(rest);
    const argsText = (usingSplit ? rest.slice(0, usingSplit.index) : rest).replace(/^\s*,/, "");
    const args = splitTopLevelArgs(argsText);
    const tenantExpr = (args[args.length - 1] ?? "").trim();
    if (tenantExpr === "") continue;

    const absoluteIndex = block.bodyStartIndex + headerMatch.index;
    const line = lineAt(content, absoluteIndex);
    const snippet = headerMatch[1]?.slice(0, 90) ?? "";

    if (tenantExpr === "p_tenant_id") {
      findings.push({
        file,
        line,
        functionName: block.name,
        tenantExpr,
        classification: "SAFE_CALLER_SUPPLIED",
        reason: "final interpolated arg is exactly p_tenant_id (caller-supplied)",
        snippet,
      });
      continue;
    }

    const { classification, reason } = classifyRowDerived(block.bodyText, headerMatch.index, tenantExpr);
    findings.push({ file, line, functionName: block.name, tenantExpr, classification, reason, snippet });
  }
  return findings;
}

/**
 * Per-file findings, including every historical definition of a function
 * (useful for counting "how many raise sites were ever written this way",
 * matching this issue's own original grep-count methodology).
 */
export function classifyFile(file: string, content: string): Finding[] {
  const findings: Finding[] = [];
  for (const block of parseFunctionBlocks(content)) {
    findings.push(...classifyBlock(file, content, block));
  }
  return findings;
}

function listMigrationFiles(): string[] {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();
}

export function scanRepository(): Finding[] {
  const findings: Finding[] = [];
  for (const file of listMigrationFiles()) {
    const path = join(MIGRATIONS_DIR, file);
    const content = readFileSync(path, "utf8");
    findings.push(...classifyFile(path, content));
  }
  return findings;
}

/**
 * Same scan, but keyed by function name so a LATER `create or replace
 * function` (a later, chronologically-sorted migration file) fully replaces
 * an earlier definition's own findings -- mirroring how Postgres itself only
 * ever has one live function body per name. Without this, a function fixed
 * by a later hardening migration would still be double-counted from its own
 * old, already-superseded definition. This is the count that matters for
 * "how many sites are actually live and at-risk today".
 */
export function scanRepositoryLatestDefinitionOnly(): Finding[] {
  const byFunction = new Map<string, Finding[]>();
  for (const file of listMigrationFiles()) {
    const path = join(MIGRATIONS_DIR, file);
    const content = readFileSync(path, "utf8");
    for (const block of parseFunctionBlocks(content)) {
      byFunction.set(block.name, classifyBlock(path, content, block));
    }
  }
  return [...byFunction.values()].flat();
}

function report(label: string, findings: Finding[]): Map<Classification, Finding[]> {
  const byClass = new Map<Classification, Finding[]>();
  for (const f of findings) {
    const arr = byClass.get(f.classification) ?? [];
    arr.push(f);
    byClass.set(f.classification, arr);
  }
  const order: Classification[] = ["SAFE_CALLER_SUPPLIED", "SAFE_TENANT_SCOPED_LOOKUP", "RISK_UNSCOPED_LOOKUP", "AMBIGUOUS"];
  console.log(`\n=== ${label}: ${findings.length} total 'for tenant %' occurrences ===`);
  for (const cls of order) {
    const arr = byClass.get(cls) ?? [];
    console.log(`${cls}: ${arr.length}`);
  }
  const riskFindings = byClass.get("RISK_UNSCOPED_LOOKUP") ?? [];
  const distinctRiskFunctions = new Set(riskFindings.map((f) => f.functionName));
  console.log(`RISK_UNSCOPED_LOOKUP spans ${distinctRiskFunctions.size} distinct function names.`);
  return byClass;
}

function main(): void {
  report("ALL historical definitions (every migration, including superseded ones)", scanRepository());
  const latestByClass = report("LATEST definition only (what is actually live today)", scanRepositoryLatestDefinitionOnly());

  const riskFindings = latestByClass.get("RISK_UNSCOPED_LOOKUP") ?? [];
  if (process.argv.includes("--list-risk")) {
    console.log("\n--- RISK_UNSCOPED_LOOKUP sites (latest definition only) ---");
    for (const f of riskFindings) {
      console.log(`${f.file}:${f.line} ${f.functionName} tenantExpr=${f.tenantExpr} :: ${f.reason}`);
    }
  }
  if (process.argv.includes("--list-ambiguous")) {
    console.log("\n--- AMBIGUOUS sites (latest definition only) ---");
    for (const f of latestByClass.get("AMBIGUOUS") ?? []) {
      console.log(`${f.file}:${f.line} ${f.functionName} tenantExpr=${f.tenantExpr} :: ${f.reason}`);
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
