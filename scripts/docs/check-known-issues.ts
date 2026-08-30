/**
 * Keeps `docs/runtime/KNOWN_ISSUES.md`'s §3 index honest about its own §4 records.
 *
 * Why this exists, stated plainly, because the failure it prevents already happened:
 *
 * On 2026-08-30 the index carried **63 rows for 261 records** — it stopped being maintained
 * around Phase 8 Batch 4 — and, worse, **78 record headings declared a status their own body
 * contradicted**, almost all of them saying `OPEN` where the body recorded a later, dated
 * `RESOLVED`. Every backlog count anyone took from this file was wrong, always in the direction
 * of overstating how much work remained. Three separate sessions produced three different
 * "how many are open" numbers and none of them was right.
 *
 * A ledger nobody can count is not a ledger. So the rules below are mechanical:
 *
 *   1. Every §4 record has exactly one §3 row, and every §3 row has a record. No orphans in
 *      either direction — that is the drift that actually occurred.
 *   2. A record's heading declares its own status and severity in its final parenthetical, and
 *      the §3 row must agree with it. Two places, forced to say the same thing.
 *   3. Statuses come from the closed vocabulary in §1. A typo is an error, not a new status.
 *   4. Issue IDs are unique.
 *
 * What this deliberately does NOT do: decide whether a record's status is *true*. No parser can
 * read "the fix landed but the UI caller is still missing" and rule on it. That judgement is a
 * human reading each record, and this gate only makes sure the judgement, once made, is written
 * in both places and stays there.
 *
 * Run: node --experimental-strip-types scripts/docs/check-known-issues.ts
 */

import { readFileSync } from "node:fs";

export const KNOWN_ISSUES_PATH = "docs/runtime/KNOWN_ISSUES.md";

/** The closed status vocabulary, from `KNOWN_ISSUES.md` §1. */
export const VALID_STATUSES = [
  "OPEN",
  "TRIAGED",
  "PLANNED",
  "IN_PROGRESS",
  "MONITORING",
  "ACCEPTED_RISK",
  "ACCEPTED_EXCEPTION",
  "RESOLVED",
  "VERIFIED",
  "SUPERSEDED",
] as const;

export type IssueStatus = (typeof VALID_STATUSES)[number];

/** Statuses that mean "no further work is tracked here". */
export const CLOSED_STATUSES: readonly string[] = ["RESOLVED", "VERIFIED", "SUPERSEDED"];

export const VALID_SEVERITIES = ["Critical", "High", "Medium", "Low"] as const;

export interface IssueRecord {
  readonly id: string;
  readonly heading: string;
  readonly status: string | null;
  readonly severity: string | null;
  readonly line: number;
}

export interface IndexRow {
  readonly id: string;
  readonly severity: string;
  readonly status: string;
  readonly line: number;
}

export interface Finding {
  readonly code: string;
  readonly message: string;
}

/**
 * Returns the span of the LAST top-level `(...)` group in a heading.
 *
 * Headings in this file are long and quote code, prose and other issue ids, all of which contain
 * status-shaped words — `21 \`VERIFIED\` checkpoints`, `see ISS-2026-072 (OPEN, High)`. Scanning
 * the whole heading for a status word finds those and reports the wrong status; that mistake is
 * how one of this session's own counts went wrong. Only the final parenthetical declares.
 */
export function lastParentheticalSpan(heading: string): readonly [number, number] | null {
  let depth = 0;
  let start = -1;
  let best: [number, number] | null = null;
  for (let i = 0; i < heading.length; i += 1) {
    const c = heading[i];
    if (c === "(") {
      if (depth === 0) start = i;
      depth += 1;
    } else if (c === ")") {
      depth -= 1;
      if (depth === 0 && start >= 0) best = [start, i + 1];
    }
  }
  return best;
}

const STATUS_PATTERN = new RegExp(`\\b(${VALID_STATUSES.join("|")})\\b`);
const SEVERITY_PATTERN = new RegExp(`\\b(${VALID_SEVERITIES.join("|")})\\b`);

/**
 * A heading may mention several statuses ("OPEN — partial, two of three sub-items RESOLVED").
 * The convention this file follows is that the FIRST one is the record's own disposition and any
 * later one is context about a part of it.
 */
export function parseHeading(id: string, heading: string, line: number): IssueRecord {
  const span = lastParentheticalSpan(heading);
  const tail = span ? heading.slice(span[0], span[1]) : "";
  const status = tail.match(STATUS_PATTERN)?.[1] ?? null;
  const severity = tail.match(SEVERITY_PATTERN)?.[1] ?? null;
  return { id, heading, status, severity, line };
}

export function parseKnownIssues(text: string): {
  readonly records: readonly IssueRecord[];
  readonly indexRows: readonly IndexRow[];
} {
  const lines = text.split("\n");
  const records: IssueRecord[] = [];
  const indexRows: IndexRow[] = [];

  let inIndex = false;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i] ?? "";
    if (/^## 3\. Issue index/.test(line)) inIndex = true;
    else if (/^## 4\. Issue records/.test(line)) inIndex = false;

    const record = line.match(/^### (ISS-\d{4}-\d+) — (.*)$/);
    if (record) {
      records.push(parseHeading(record[1] as string, record[2] as string, i + 1));
      continue;
    }

    if (!inIndex) continue;
    const row = line.match(/^\|\s*`(ISS-\d{4}-\d+)`\s*\|\s*([^|]*?)\s*\|\s*`?([A-Z_]+)`?\s*\|/);
    if (row) {
      indexRows.push({ id: row[1] as string, severity: (row[2] as string).trim(), status: row[3] as string, line: i + 1 });
    }
  }

  return { records, indexRows };
}

/**
 * The §3 summary table restates the counts in prose, which makes it the one number in this file
 * a reader is most likely to quote and least likely to recompute. It drifted within an hour of
 * being written, so it is checked rather than trusted.
 *
 * Only rows the table actually declares are checked — the table is free to summarise less than
 * everything, but not to be wrong about what it does say.
 */
function checkSummaryTable(text: string, records: readonly IssueRecord[]): readonly Finding[] {
  const findings: Finding[] = [];
  const actual = summarizeRecords(records);

  const expect = (label: string, declared: number | undefined, real: number): void => {
    if (declared !== undefined && declared !== real) {
      findings.push({ code: "SUMMARY_COUNT_STALE", message: `§3 summary says ${declared} ${label}, the records say ${real}` });
    }
  };

  const num = (m: RegExpMatchArray | null, i: number): number | undefined => {
    const raw = m?.[i];
    return raw === undefined ? undefined : Number(raw);
  };

  const openRow = text.match(/^\|\s*`OPEN`\s*\|\s*(\d+)\s*—\s*(\d+) High,\s*(\d+) Medium,\s*(\d+) Low/m);
  expect("OPEN", num(openRow, 1), actual.open);
  expect("open High", num(openRow, 2), actual.openBySeverity["High"] ?? 0);
  expect("open Medium", num(openRow, 3), actual.openBySeverity["Medium"] ?? 0);
  expect("open Low", num(openRow, 4), actual.openBySeverity["Low"] ?? 0);

  expect("accepted", num(text.match(/^\|\s*`ACCEPTED_RISK`[^|]*\|\s*(\d+)/m), 1), actual.accepted);
  expect("RESOLVED", num(text.match(/^\|\s*`RESOLVED`\s*\|\s*(\d+)/m), 1), actual.closed);
  expect("total records", num(text.match(/^\|\s*\*\*Total records\*\*\s*\|\s*\*\*(\d+)\*\*/m), 1), actual.total);

  return findings;
}

export function checkKnownIssues(text: string): readonly Finding[] {
  const { records, indexRows } = parseKnownIssues(text);
  const findings: Finding[] = [];

  const seen = new Set<string>();
  for (const r of records) {
    if (seen.has(r.id)) findings.push({ code: "DUPLICATE_RECORD", message: `${r.id}: a second §4 record with the same id (line ${r.line})` });
    seen.add(r.id);
    if (!r.status) {
      findings.push({
        code: "RECORD_NO_STATUS",
        message: `${r.id} (line ${r.line}): heading's final parenthetical declares no status — add one of ${VALID_STATUSES.join("/")}`,
      });
    }
    if (!r.severity) {
      findings.push({ code: "RECORD_NO_SEVERITY", message: `${r.id} (line ${r.line}): heading's final parenthetical declares no severity` });
    }
  }

  const rowSeen = new Set<string>();
  for (const row of indexRows) {
    if (rowSeen.has(row.id)) findings.push({ code: "DUPLICATE_INDEX_ROW", message: `${row.id}: a second §3 index row (line ${row.line})` });
    rowSeen.add(row.id);
    if (!(VALID_STATUSES as readonly string[]).includes(row.status)) {
      findings.push({ code: "UNKNOWN_STATUS", message: `${row.id} (line ${row.line}): status ${row.status} is not in the §1 vocabulary` });
    }
  }

  findings.push(...checkSummaryTable(text, records));

  const byId = new Map(records.map((r) => [r.id, r]));
  for (const row of indexRows) {
    if (!byId.has(row.id)) {
      findings.push({ code: "INDEX_ROW_WITHOUT_RECORD", message: `${row.id} (line ${row.line}): §3 row has no §4 record` });
    }
  }
  for (const r of records) {
    const row = indexRows.find((x) => x.id === r.id);
    if (!row) {
      findings.push({
        code: "RECORD_WITHOUT_INDEX_ROW",
        message: `${r.id} (line ${r.line}): §4 record has no §3 index row — this is the drift that left the index covering 63 of 261 records`,
      });
      continue;
    }
    if (r.status && row.status !== r.status) {
      findings.push({
        code: "STATUS_DISAGREEMENT",
        message: `${r.id}: §3 says ${row.status}, its own §4 heading says ${r.status} (lines ${row.line} and ${r.line})`,
      });
    }
    if (r.severity && row.severity !== r.severity) {
      findings.push({
        code: "SEVERITY_DISAGREEMENT",
        message: `${r.id}: §3 says ${row.severity}, its own §4 heading says ${r.severity} (lines ${row.line} and ${r.line})`,
      });
    }
  }

  return findings;
}

export interface IssueStats {
  readonly total: number;
  readonly open: number;
  readonly accepted: number;
  readonly closed: number;
  readonly openBySeverity: Readonly<Record<string, number>>;
}

export function summarize(text: string): IssueStats {
  return summarizeRecords(parseKnownIssues(text).records);
}

function summarizeRecords(records: readonly IssueRecord[]): IssueStats {
  const openBySeverity: Record<string, number> = {};
  let open = 0;
  let accepted = 0;
  let closed = 0;
  for (const r of records) {
    const st = r.status ?? "OPEN";
    if (CLOSED_STATUSES.includes(st)) {
      closed += 1;
    } else if (st.startsWith("ACCEPTED_")) {
      accepted += 1;
    } else {
      open += 1;
      const sev = r.severity ?? "Medium";
      openBySeverity[sev] = (openBySeverity[sev] ?? 0) + 1;
    }
  }
  return { total: records.length, open, accepted, closed, openBySeverity };
}

function main(): void {
  const text = readFileSync(KNOWN_ISSUES_PATH, "utf8");
  const findings = checkKnownIssues(text);
  const s = summarize(text);

  const sev = VALID_SEVERITIES.filter((x) => s.openBySeverity[x]).map((x) => `${s.openBySeverity[x]} ${x}`).join(", ");
  console.log(
    `\nknown issues: ${s.total} records; ${s.open} OPEN (${sev || "none"}); ` +
      `${s.accepted} formally accepted; ${s.closed} closed.`,
  );

  if (findings.length > 0) {
    for (const f of findings) console.error(`✖ ${f.code} ${f.message}`);
    console.error(`\n${findings.length} known-issues ledger problem(s).`);
    process.exit(1);
  }
  console.log("✔ issue index and records agree (coverage both ways, status and severity).");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
