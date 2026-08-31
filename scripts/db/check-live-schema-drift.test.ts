import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findLiveSchemaDrift, DRIFT_QUERY, type FunctionPairRow } from "./check-live-schema-drift.ts";

function row(overrides: Partial<FunctionPairRow> = {}): FunctionPairRow {
  return {
    proname: "approve_finance_invoice",
    args: "p_invoice_id uuid, p_actor_auth_user_id uuid",
    app_secdef: true,
    pub_secdef: true,
    app_anon: false,
    pub_anon: false,
    app_auth: true,
    pub_auth: true,
    app_sr: true,
    pub_sr: true,
    ...overrides,
  };
}

describe("findLiveSchemaDrift", () => {
  test("an agreeing pair produces nothing", () => {
    assert.deepEqual(findLiveSchemaDrift([row()]), []);
  });

  test("THE ISS-2026-318 SHAPE: a definer app.* function with an invoker public.* wrapper", () => {
    const findings = findLiveSchemaDrift([row({ pub_secdef: false })]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "security_mode");
    // The message has to name which side is which -- whoever reads it is about to write a
    // corrective migration and needs to know which one to change.
    assert.match(findings[0]?.detail ?? "", /app\.approve_finance_invoice is security definer/);
    assert.match(findings[0]?.detail ?? "", /public\.approve_finance_invoice is invoker/);
  });

  test("THE SECOND ISS-2026-318 SHAPE: a wrapper that has lost a grant the app.* function holds", () => {
    const findings = findLiveSchemaDrift([row({ proname: "check_finance_journal_authority", pub_auth: false })]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "grants");
    assert.match(findings[0]?.detail ?? "", /authenticated,service_role/);
    assert.match(findings[0]?.detail ?? "", /public\.check_finance_journal_authority grants it to service_role/);
  });

  test("a WIDENED wrapper is drift too, not only a narrowed one", () => {
    // A wrapper reachable by anon while its app.* function is not is the direction that
    // actually matters for exposure, and it is the same comparison.
    const findings = findLiveSchemaDrift([row({ pub_anon: true })]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "grants");
  });

  test("both properties drifting on one function reports BOTH, not just the first", () => {
    // ISS-2026-318 had exactly this: one function that had lost its definer flag AND a grant.
    // Reporting one would have hidden the other from the corrective migration.
    const findings = findLiveSchemaDrift([row({ pub_secdef: false, pub_auth: false })]);
    assert.deepEqual(
      findings.map((f) => f.kind),
      ["security_mode", "grants"],
    );
  });

  test("every drifting function is reported, not just the first -- the real finding was 111 of them", () => {
    const findings = findLiveSchemaDrift([
      row({ proname: "a", pub_secdef: false }),
      row({ proname: "b" }),
      row({ proname: "c", pub_secdef: false }),
    ]);
    assert.deepEqual(
      findings.map((f) => f.proname),
      ["a", "c"],
    );
  });

  test("an empty pair set is clean, not an error", () => {
    assert.deepEqual(findLiveSchemaDrift([]), []);
  });

  test("the query joins app to public by name and compares exactly the two properties the local gate does", () => {
    assert.match(DRIFT_QUERY, /nspname = 'app'/);
    assert.match(DRIFT_QUERY, /nspname = 'public'/);
    assert.match(DRIFT_QUERY, /prosecdef/);
    assert.match(DRIFT_QUERY, /has_function_privilege\('authenticated'/);
    // prokind = 'f' on both sides: postgis ships aggregates in public whose names collide, and
    // pg_get_functiondef refuses an aggregate outright.
    assert.match(DRIFT_QUERY, /a\.prokind = 'f' and b\.prokind = 'f'/);
  });
});
