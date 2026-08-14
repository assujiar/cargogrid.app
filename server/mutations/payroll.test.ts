import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createPayrollPeriod,
  freezePayrollPeriodInputs,
  createPayrollComponent,
  approvePayrollComponentVersion,
  assignPayrollComponentToEmployee,
  decidePayrollReimbursementRequest,
  issuePayrollLoan,
  calculatePayrollRun,
  submitPayrollRunForFinalization,
  finalizePayrollRun,
  prepareFinancePayrollDisbursementHandoffFromPayrollRun,
  acknowledgePayrollFinanceHandoffBatch,
  PayrollMutationError,
  type PayrollMutationRpcClient,
} from "./payroll.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: PayrollMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PayrollMutationRpcClient;
  return { client, calls };
}

const PERIOD_ROW = { id: ID_1, code: "pr1-2026-08", period_type: "monthly", period_start: "2026-08-01", period_end: "2026-08-31", pay_date: "2026-09-05", status: "open", frozen_employee_count: null, record_version: 1 };

describe("createPayrollPeriod / freezePayrollPeriodInputs", () => {
  test("createPayrollPeriod maps to snake_case RPC args", async () => {
    const { client, calls } = fakeClient({ data: PERIOD_ROW, error: null });
    await createPayrollPeriod(client, {
      tenantId: TENANT_ID, orgUnitId: null, code: "pr1-2026-08", periodType: "monthly", periodStart: "2026-08-01",
      periodEnd: "2026-08-31", payDate: "2026-09-05", actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls[0]?.fn, "create_payroll_period");
    assert.equal(calls[0]?.args.p_code, "pr1-2026-08");
  });

  test("freezePayrollPeriodInputs passes expected_version for the optimistic-lock guard", async () => {
    const { client, calls } = fakeClient({ data: { ...PERIOD_ROW, status: "input_frozen", record_version: 2 }, error: null });
    const r = await freezePayrollPeriodInputs(client, { periodId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_expected_version, 1);
    assert.equal(r.status, "input_frozen");
  });
});

describe("createPayrollComponent / approvePayrollComponentVersion", () => {
  test("createPayrollComponent never sets is_statutory -- structurally impossible from this entrypoint", async () => {
    const { client, calls } = fakeClient({
      data: { id: ID_1, tenant_id: TENANT_ID, code: "base_salary", name: "Base Salary", component_type: "earning", is_statutory: false, gl_mapping_category: "salary_expense", status: "active" },
      error: null,
    });
    await createPayrollComponent(client, { tenantId: TENANT_ID, code: "base_salary", name: "Base Salary", componentType: "earning", glMappingCategory: "salary_expense", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal("p_is_statutory" in (calls[0]?.args ?? {}), false);
  });

  test("approvePayrollComponentVersion classifies the RPD-016 example-fixture guard error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "payroll_component_version_example_fixture_not_activatable: version x is a seeded illustrative example" } });
    await assert.rejects(
      () => approvePayrollComponentVersion(client, { versionId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supreme" }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "payroll_component_version_example_fixture_not_activatable",
    );
  });
});

describe("assignPayrollComponentToEmployee", () => {
  test("classifies an overlap conflict distinctly from a plain check_violation", async () => {
    const { client } = fakeClient({ data: null, error: { message: "payroll_assignment_overlap: employee x already has an active assignment" } });
    await assert.rejects(
      () => assignPayrollComponentToEmployee(client, {
        tenantId: TENANT_ID, employeeId: ID_1, componentId: ID_1, overrideAmount: null, overridePercentage: null, manualAmount: null,
        currency: "IDR", effectiveFrom: "2026-01-01", effectiveTo: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
      }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "payroll_assignment_overlap",
    );
  });
});

describe("decidePayrollReimbursementRequest / issuePayrollLoan", () => {
  test("decidePayrollReimbursementRequest classifies self-approval block", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own reimbursement request" } });
    await assert.rejects(
      () => decidePayrollReimbursementRequest(client, { requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "self_approval_not_permitted",
    );
  });

  test("issuePayrollLoan passes the opening-balance cutover fields through distinctly", async () => {
    const { client, calls } = fakeClient({
      data: { id: ID_1, employee_id: ID_1, principal_amount: "300000.00", currency: "IDR", installment_amount: "100000.00", term_count: 6, remaining_installments: 2, status: "active", is_opening_balance: true, record_version: 1 },
      error: null,
    });
    await issuePayrollLoan(client, {
      tenantId: TENANT_ID, employeeId: ID_1, principalAmount: 300000, currency: "IDR", installmentAmount: 100000, termCount: 6,
      isOpeningBalance: true, openingRemainingInstallments: 2, notes: "cutover loan", actorAuthUserId: ACTOR_ID, actorLabel: "approver",
    });
    assert.equal(calls[0]?.args.p_is_opening_balance, true);
    assert.equal(calls[0]?.args.p_opening_remaining_installments, 2);
  });
});

describe("calculatePayrollRun / submitPayrollRunForFinalization / finalizePayrollRun", () => {
  test("calculatePayrollRun classifies a finalized-run recalculation block", async () => {
    const { client } = fakeClient({ data: null, error: { message: "invalid_transition: run x is finalized -- only draft/calculated/exception may (re)calculate" } });
    await assert.rejects(
      () => calculatePayrollRun(client, { runId: ID_1, expectedVersion: 1, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "invalid_transition",
    );
  });

  test("submitPayrollRunForFinalization classifies the missing approval-routing-definition error (decision 6, mirrors leave)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "approval_definition_not_configured: tenant x has no published approval routing definition" } });
    await assert.rejects(
      () => submitPayrollRunForFinalization(client, { runId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "approval_definition_not_configured",
    );
  });

  test("finalizePayrollRun sends PLT-123's own decision vocabulary (approved/rejected)", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, payroll_period_id: ID_1, run_type: "regular", adjusts_run_id: null, status: "finalized", currency: "IDR", employee_count: 1, exception_count: 0, approval_request_id: ID_1, record_version: 2 }, error: null });
    await finalizePayrollRun(client, { requestStepId: ID_1, decision: "approved", reason: "looks good", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_decision, "approved");
  });
});

describe("prepareFinancePayrollDisbursementHandoffFromPayrollRun / acknowledgePayrollFinanceHandoffBatch", () => {
  test("prepare classifies a not-yet-finalized-run block (decision 1 -- Finance handoff boundary)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "payroll_run_not_finalized: run x is calculated -- only a finalized run may generate a Finance handoff" } });
    await assert.rejects(
      () => prepareFinancePayrollDisbursementHandoffFromPayrollRun(client, { tenantId: TENANT_ID, runId: ID_1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "payroll_run_not_finalized",
    );
  });

  test("acknowledge classifies a non-Finance-authority block (the one FIN:Edit-gated action in this whole checkpoint)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: identity x lacks FIN:Edit for tenant y" } });
    await assert.rejects(
      () => acknowledgePayrollFinanceHandoffBatch(client, { batchId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PayrollMutationError && err.code === "insufficient_authority",
    );
  });
});
