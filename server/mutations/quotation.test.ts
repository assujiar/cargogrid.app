import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createQuotationDraft,
  cloneQuotation,
  addQuotationLine,
  removeQuotationLine,
  updateQuotationTerms,
  submitQuotation,
  createQuotationRevision,
  QuotationMutationError,
  type QuotationMutationRpcClient,
} from "./quotation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_QUOTATION_ROW = {
  id: QUOTATION_ID,
  tenant_id: TENANT_ID,
  quote_number: "QTN-2026-000001",
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  prospect_id: "623e4567-e89b-12d3-a456-426614174000",
  contact_id: null,
  customer_snapshot: { legal_name: "Contoso Ltd" },
  currency: "IDR",
  validity_from: "2026-07-24T00:00:00.000Z",
  validity_to: "2026-08-24T00:00:00.000Z",
  terms: {},
  subtotal_amount: 0,
  discount_amount: 0,
  tax_amount: 0,
  total_amount: 0,
  status: "draft",
  cancel_reason: null,
  cloned_from_id: null,
  document_ref: null,
  submitted_at: null,
  submitted_by: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
  root_quotation_id: QUOTATION_ID,
  version_number: 1,
  is_current: true,
  superseded_by_id: null,
  revision_reason: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): QuotationMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as QuotationMutationRpcClient;
}

describe("createQuotationDraft", () => {
  test("calls create_quotation_draft with the exact snake_case params and returns an unmasked quotation", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_QUOTATION_ROW, error: null }, calls);
    const quotation = await createQuotationDraft(client, {
      tenantId: TENANT_ID,
      opportunityId: OPPORTUNITY_ID,
      currency: "IDR",
      validityTo: "2026-08-24T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(calls[0]?.fn, "create_quotation_draft");
    assert.equal(calls[0]?.args.p_opportunity_id, OPPORTUNITY_ID);
    assert.equal(quotation.sellMasked, false);
    assert.equal(quotation.status, "draft");
  });

  test("classifies cross_tenant_opportunity_denied", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "cross_tenant_opportunity_denied: opportunity x does not belong to tenant y" } }, []);
    await assert.rejects(
      () =>
        createQuotationDraft(client, {
          tenantId: TENANT_ID,
          opportunityId: OPPORTUNITY_ID,
          currency: "IDR",
          validityTo: "2026-08-24T00:00:00.000Z",
          actorAuthUserId: ACTOR_ID,
          createdBy: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationMutationError);
        assert.equal(err.code, "cross_tenant_opportunity_denied");
        return true;
      },
    );
  });
});

describe("cloneQuotation", () => {
  test("calls clone_quotation with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_QUOTATION_ROW, cloned_from_id: QUOTATION_ID }, error: null }, calls);
    const clone = await cloneQuotation(client, { sourceQuotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(calls[0]?.fn, "clone_quotation");
    assert.equal(calls[0]?.args.p_source_quotation_id, QUOTATION_ID);
    assert.equal(clone.clonedFromId, QUOTATION_ID);
  });
});

describe("addQuotationLine", () => {
  test("calls add_quotation_line and returns the recalculated header", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_QUOTATION_ROW, total_amount: 15000000 }, error: null }, calls);
    const quotation = await addQuotationLine(client, {
      quotationId: QUOTATION_ID,
      expectedVersion: 1,
      lineType: "service",
      description: "Ocean freight",
      quantity: 1,
      unitPrice: 15000000,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.fn, "add_quotation_line");
    assert.equal(calls[0]?.args.p_description, "Ocean freight");
    assert.equal(quotation.totalAmount, 15000000);
  });

  test("classifies stale_version", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "stale_version: quotation x expected version 1 but found 2" } }, []);
    await assert.rejects(
      () =>
        addQuotationLine(client, {
          quotationId: QUOTATION_ID,
          expectedVersion: 1,
          lineType: "service",
          description: "Ocean freight",
          quantity: 1,
          unitPrice: 100,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("removeQuotationLine", () => {
  test("calls remove_quotation_line with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_QUOTATION_ROW, error: null }, calls);
    await removeQuotationLine(client, {
      quotationId: QUOTATION_ID,
      expectedVersion: 1,
      lineId: "723e4567-e89b-12d3-a456-426614174000",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.fn, "remove_quotation_line");
    assert.equal(calls[0]?.args.p_line_id, "723e4567-e89b-12d3-a456-426614174000");
  });
});

describe("updateQuotationTerms", () => {
  test("serializes terms to the whitelisted snake_case keys", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_QUOTATION_ROW, error: null }, calls);
    await updateQuotationTerms(client, {
      quotationId: QUOTATION_ID,
      expectedVersion: 1,
      currency: "IDR",
      validityFrom: "2026-07-24T00:00:00.000Z",
      validityTo: "2026-08-24T00:00:00.000Z",
      terms: { paymentTerms: "Net 30" },
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.deepEqual(calls[0]?.args.p_terms, { payment_terms: "Net 30" });
  });

  test("classifies unknown_terms_key", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "unknown_terms_key: bogus is not a whitelisted terms key" } }, []);
    await assert.rejects(
      () =>
        updateQuotationTerms(client, {
          quotationId: QUOTATION_ID,
          expectedVersion: 1,
          currency: "IDR",
          validityFrom: "2026-07-24T00:00:00.000Z",
          validityTo: "2026-08-24T00:00:00.000Z",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationMutationError);
        assert.equal(err.code, "unknown_terms_key");
        return true;
      },
    );
  });
});

describe("submitQuotation", () => {
  test("calls submit_quotation with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_QUOTATION_ROW, status: "submitted" }, error: null }, calls);
    const quotation = await submitQuotation(client, { quotationId: QUOTATION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "submit_quotation");
    assert.equal(quotation.status, "submitted");
  });

  test("classifies submission_not_ready", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "submission_not_ready: quotation x is not ready to submit (no_lines, contact_required)" } }, []);
    await assert.rejects(
      () => submitQuotation(client, { quotationId: QUOTATION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationMutationError);
        assert.equal(err.code, "submission_not_ready");
        return true;
      },
    );
  });
});

describe("createQuotationRevision", () => {
  test("calls create_quotation_revision with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_QUOTATION_ROW, version_number: 2, revision_reason: "Customer requested a discount" }, error: null }, calls);
    const revision = await createQuotationRevision(client, {
      sourceQuotationId: QUOTATION_ID,
      reason: "Customer requested a discount",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.fn, "create_quotation_revision");
    assert.equal(calls[0]?.args.p_source_quotation_id, QUOTATION_ID);
    assert.equal(calls[0]?.args.p_reason, "Customer requested a discount");
    assert.equal(revision.versionNumber, 2);
    assert.equal(revision.revisionReason, "Customer requested a discount");
  });

  test("classifies reason_required", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reason_required: creating a quotation revision requires a non-empty reason" } }, []);
    await assert.rejects(
      () => createQuotationRevision(client, { sourceQuotationId: QUOTATION_ID, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });

  test("rejects an empty reason at the schema layer before any RPC call", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_QUOTATION_ROW, error: null }, calls);
    await assert.rejects(() => createQuotationRevision(client, { sourceQuotationId: QUOTATION_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }));
    assert.equal(calls.length, 0);
  });

  test("classifies concurrent_revision", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "concurrent_revision: another revision was created concurrently for quotation root x" } }, []);
    await assert.rejects(
      () => createQuotationRevision(client, { sourceQuotationId: QUOTATION_ID, reason: "Retry", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationMutationError);
        assert.equal(err.code, "concurrent_revision");
        return true;
      },
    );
  });
});
