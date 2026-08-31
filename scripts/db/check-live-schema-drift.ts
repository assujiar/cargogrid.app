/**
 * Live-versus-migrations schema drift check (ISS-2026-318).
 *
 * WHY THE EXISTING GATE CANNOT BE THIS CHECK
 *
 *   `scripts/db-tests/public-api-wrapper-regression.sql` already asserts, exhaustively, that
 *   no `public.*` wrapper's security mode or grant set differs from its `app.*` counterpart.
 *   It runs against a database built from `supabase/migrations/` — so it compares what the
 *   migrations say to what the migrations say. Every divergence between the migration set and
 *   the live project is invisible to it by construction, and always will be.
 *
 *   `ISS-2026-318` is what that blindness costs: 111 `public.*` wrappers had lost their
 *   `security definer` flag on the hosted project, and one had additionally lost its
 *   `authenticated` grant, while every migration in the repository said otherwise. Nothing was
 *   broken and nothing was exposed — an invoker wrapper is the more restrictive of the two —
 *   but for months the code did not describe the database, and no test could have said so.
 *
 * WHY THIS IS AN OPERATOR COMMAND AND NOT A CI STEP
 *
 *   Answering the question needs credentials for the live project. CI does not have them and
 *   should not: a pipeline that can read production's schema is a pipeline whose compromise
 *   reads production. So this runs where the credentials already live — an operator's session
 *   — and prints something a person can act on.
 *
 * WHAT IT CHECKS
 *
 *   The two properties the parity gate checks locally, asked of the live project instead:
 *   every `app.*` function that has an identically-named `public.*` wrapper must agree with it
 *   on (a) `security definer` versus invoker, and (b) which of anon/authenticated/service_role
 *   hold EXECUTE. Both are single facts per function, comparable without shipping any schema
 *   snapshot around, which is what keeps this cheap enough to run often.
 *
 *   It deliberately does NOT diff function bodies. A body diff against the migration set needs
 *   a migration-built database to compare with, which is a heavier tool than this one, and
 *   bodies drift far less often than attributes do — every instance this repository has found
 *   was an attribute.
 *
 * USAGE
 *
 *   SUPABASE_PAT=... SUPABASE_PROJECT_REF=... pnpm run db:check-live-drift
 *
 *   Exits 1 on any mismatch, 0 when live agrees with itself. With no credentials it prints the
 *   query and exits 0 — it reports that it did not run, rather than reporting a pass.
 */

export interface FunctionPairRow {
  readonly proname: string;
  readonly args: string;
  readonly app_secdef: boolean;
  readonly pub_secdef: boolean;
  readonly app_anon: boolean;
  readonly pub_anon: boolean;
  readonly app_auth: boolean;
  readonly pub_auth: boolean;
  readonly app_sr: boolean;
  readonly pub_sr: boolean;
}

export interface DriftFinding {
  readonly proname: string;
  readonly args: string;
  readonly kind: "security_mode" | "grants";
  readonly detail: string;
}

function roleSet(anon: boolean, auth: boolean, sr: boolean): string {
  const held = [anon ? "anon" : null, auth ? "authenticated" : null, sr ? "service_role" : null].filter(Boolean);
  return held.length > 0 ? held.join(",") : "(none)";
}

/**
 * Pure decision core. One row in, at most two findings out — a function can drift on both
 * properties independently, and reporting only the first would hide the second from whoever
 * is about to write the corrective migration.
 */
export function findLiveSchemaDrift(rows: readonly FunctionPairRow[]): DriftFinding[] {
  const findings: DriftFinding[] = [];
  for (const row of rows) {
    if (row.app_secdef !== row.pub_secdef) {
      findings.push({
        proname: row.proname,
        args: row.args,
        kind: "security_mode",
        detail: `app.${row.proname} is ${row.app_secdef ? "security definer" : "invoker"} but public.${row.proname} is ${row.pub_secdef ? "security definer" : "invoker"}`,
      });
    }
    const appRoles = roleSet(row.app_anon, row.app_auth, row.app_sr);
    const pubRoles = roleSet(row.pub_anon, row.pub_auth, row.pub_sr);
    if (appRoles !== pubRoles) {
      findings.push({
        proname: row.proname,
        args: row.args,
        kind: "grants",
        detail: `app.${row.proname} grants EXECUTE to ${appRoles} but public.${row.proname} grants it to ${pubRoles}`,
      });
    }
  }
  return findings;
}

export const DRIFT_QUERY = `
select a.proname,
  pg_get_function_identity_arguments(a.oid) as args,
  a.prosecdef as app_secdef,
  b.prosecdef as pub_secdef,
  has_function_privilege('anon', a.oid, 'execute') as app_anon,
  has_function_privilege('anon', b.oid, 'execute') as pub_anon,
  has_function_privilege('authenticated', a.oid, 'execute') as app_auth,
  has_function_privilege('authenticated', b.oid, 'execute') as pub_auth,
  has_function_privilege('service_role', a.oid, 'execute') as app_sr,
  has_function_privilege('service_role', b.oid, 'execute') as pub_sr
from pg_proc a
join pg_namespace na on na.oid = a.pronamespace and na.nspname = 'app'
join pg_proc b on b.proname = a.proname
join pg_namespace nb on nb.oid = b.pronamespace and nb.nspname = 'public'
where a.prokind = 'f' and b.prokind = 'f'
order by a.proname;
`.trim();

async function main(): Promise<void> {
  const pat = process.env.SUPABASE_PAT;
  const ref = process.env.SUPABASE_PROJECT_REF;

  if (!pat || !ref) {
    // Saying "not run" rather than printing a tick: a green result nobody produced is worse
    // than no result, which is the same reasoning check-applied-migration-collision.ts uses
    // when it cannot see the base branch.
    console.log("• live schema drift check NOT RUN — set SUPABASE_PAT and SUPABASE_PROJECT_REF to run it against the live project.");
    console.log("  To run it by hand instead, execute this against the project's database:\n");
    console.log(DRIFT_QUERY);
    return;
  }

  const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${pat}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query: DRIFT_QUERY }),
  });
  if (!response.ok) {
    console.error(`✖ live schema drift check could not reach the project (HTTP ${response.status}). It has NOT passed; it did not run.`);
    process.exit(1);
  }

  const rows = (await response.json()) as FunctionPairRow[];
  const findings = findLiveSchemaDrift(rows);

  if (findings.length > 0) {
    console.error(`✖ ${findings.length} live schema drift finding(s) across ${rows.length} app./public. function pair(s) on project ${ref}:`);
    for (const finding of findings) {
      console.error(`  - [${finding.kind}] ${finding.proname}(${finding.args})`);
      console.error(`    ${finding.detail}`);
    }
    console.error("\n  The live project no longer matches what the migrations declare. Fix it with a corrective");
    console.error("  migration generated FROM THE MIGRATION-BUILT SHAPE, never from the live one — copying a live");
    console.error("  definition carries every other attribute that drifted with it (ISS-2026-318 found exactly that).");
    process.exit(1);
  }

  console.log(`✔ live project ${ref} agrees with itself on security mode and grants across ${rows.length} app./public. function pair(s).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
