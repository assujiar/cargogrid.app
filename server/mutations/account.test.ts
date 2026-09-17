import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { convertQuotationToAccount, validateCustomerImportRow, commitCustomerImportJob, AccountMutationError, type AccountMutationRpcClient } from "./account.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "723e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "823e4567-e89b-12d3-a456-426614174000";

const ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  legal_name: "Contoso Ltd",
  trade_name: null,
  tax_id: null,
  billing_address: {},
  customer_status: "active",
  parent_account_id: null,
  source_prospect_id: null,
  status: "active",
  merged_into_id: null,
  merged_at: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): AccountMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AccountMutationRpcClient;
}

describe("convertQuotationToAccount", () => {
  test("calls convert_quotation_to_account with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: ACCOUNT_ROW, error: null }, calls);
    const account = await convertQuotationToAccount(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "convert_quotation_to_account");
    assert.equal(calls[0]?.args.p_target_account_id, null);
    assert.equal(calls[0]?.args.p_parent_account_id, null);
    assert.equal(account.legalName, "Contoso Ltd");
  });

  test("passes targetAccountId for the link-to-existing flow", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: ACCOUNT_ROW, error: null }, calls);
    await convertQuotationToAccount(client, { quotationId: QUOTATION_ID, targetAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.args.p_target_account_id, ACCOUNT_ID);
  });

  test("classifies quotation_not_accepted", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "quotation_not_accepted: quotation x has no accepted customer decision" } }, []);
    await assert.rejects(
      () => convertQuotationToAccount(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "quotation_not_accepted");
        return true;
      },
    );
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Approve (missing) for tenant y" } }, []);
    await assert.rejects(
      () => convertQuotationToAccount(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("validateCustomerImportRow (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls validate_customer_import_row with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient(
      {
        data: {
          id: ROW_ID,
          tenant_id: TENANT_ID,
          job_id: JOB_ID,
          row_number: 1,
          raw_payload: { legal_name: "Contoso Ltd" },
          validation_status: "valid",
          error: null,
          created_at: "2026-09-17T00:00:00.000Z",
        },
        error: null,
      },
      calls,
    );
    const row = await validateCustomerImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
    assert.equal(row.validationStatus, "valid");
  });

  test("wraps a database error into a typed AccountMutationError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "import_export_staging_row_not_found: no staging row" } }, []);
    await assert.rejects(() => validateCustomerImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }), AccountMutationError);
  });
});

describe("commitCustomerImportJob (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls commit_customer_import_job with the exact snake_case params, including client IP, defaulting allowPartial to false", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient(
      {
        data: {
          job_id: JOB_ID,
          tenant_id: TENANT_ID,
          job_type: "import",
          status: "completed",
          priority: 0,
          payload: {},
          attempts: 0,
          max_attempts: 3,
          locked_by: null,
          locked_until: null,
          error: null,
          result_url: null,
          created_by: "tester",
          created_at: "2026-09-17T00:00:00.000Z",
          completed_at: "2026-09-17T00:05:00.000Z",
          requested_by_auth_user_id: ACTOR_ID,
          idempotency_key: "idem-customer-import-job",
          import_export_schema_code: "customer_import",
          source_file_id: "923e4567-e89b-12d3-a456-426614174000",
          result_file_id: null,
          total_rows: 1,
          processed_rows: 1,
          valid_row_count: 1,
          invalid_row_count: 0,
          cancel_reason: null,
          updated_at: "2026-09-17T00:05:00.000Z",
        },
        error: null,
      },
      calls,
    );
    const job = await commitCustomerImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "203.0.113.5" });

    assert.deepEqual(calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: false, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester", p_client_ip: "203.0.113.5" });
    assert.equal(job.status, "completed");
  });

  test("classifies import_blocked_legal_hold", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "import_blocked_legal_hold: account x is under legal hold, this import commit cannot target it" } }, []);
    await assert.rejects(
      () => commitCustomerImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "import_blocked_legal_hold");
        return true;
      },
    );
  });

  test("classifies mfa_step_up_required and ip_not_allowed", async () => {
    const mfaClient = fakeRpcClient({ data: null, error: { message: "mfa_step_up_required: COM:Import requires a current MFA step-up verification" } }, []);
    await assert.rejects(
      () => commitCustomerImportJob(mfaClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "mfa_step_up_required");
        return true;
      },
    );
    const ipClient = fakeRpcClient({ data: null, error: { message: "ip_not_allowed: malformed IP address denied for scope" } }, []);
    await assert.rejects(
      () => commitCustomerImportJob(ipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "bad-ip" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "ip_not_allowed");
        return true;
      },
    );
  });
});
