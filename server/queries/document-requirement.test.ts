import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getShipmentDocumentChecklist,
  evaluateShipmentDocumentChecklistCompleteness,
  listDocumentRequirementDefinitions,
  DocumentRequirementQueryError,
  type DocumentRequirementQueryClient,
} from "./document-requirement.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const DEFINITION_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: DocumentRequirementQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DocumentRequirementQueryClient;
  return { client, calls };
}

describe("getShipmentDocumentChecklist", () => {
  test("calls get_shipment_document_checklist with the exact snake_case params and maps every row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: ITEM_ID,
          requirement_definition_id: DEFINITION_ID,
          party: "carrier",
          document_type_code: "pod",
          criticality: "mandatory",
          file_id: null,
          malware_scan_status: null,
          review_status: "pending",
          reviewed_by_auth_user_id: null,
          reviewed_at: null,
          review_notes: null,
          expires_at: null,
          effective_status: "missing",
        },
      ],
      error: null,
    });
    const rows = await getShipmentDocumentChecklist(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "get_shipment_document_checklist");
    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.effectiveStatus, "missing");
  });

  test("wraps an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(
      () => getShipmentDocumentChecklist(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentRequirementQueryError);
        return true;
      },
    );
  });

  test("rejects a non-array response", async () => {
    const { client } = fakeRpcClient({ data: {}, error: null });
    await assert.rejects(() => getShipmentDocumentChecklist(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("evaluateShipmentDocumentChecklistCompleteness", () => {
  test("calls evaluate_shipment_document_checklist_completeness and maps the single-row result", async () => {
    const { client, calls } = fakeRpcClient({ data: { is_complete: true, missing_mandatory: [] }, error: null });
    const result = await evaluateShipmentDocumentChecklistCompleteness(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "evaluate_shipment_document_checklist_completeness");
    assert.equal(result.isComplete, true);
  });

  test("throws on a missing row", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => evaluateShipmentDocumentChecklistCompleteness(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("listDocumentRequirementDefinitions", () => {
  test("filters by tenant_id and optional status", async () => {
    const calls: { table: string; filters: [string, unknown][] }[] = [];
    const client = {
      from(table: string) {
        const filters: [string, unknown][] = [];
        const builder = {
          select() {
            return builder;
          },
          eq(column: string, value: unknown) {
            filters.push([column, value]);
            return builder;
          },
          then(resolve: (result: { data: unknown[]; error: null }) => void) {
            calls.push({ table, filters });
            resolve({ data: [], error: null });
          },
        };
        return builder;
      },
    } as unknown as DocumentRequirementQueryClient;

    await listDocumentRequirementDefinitions(client, { tenantId: TENANT_ID, status: "published" });
    assert.equal(calls[0]?.table, "document_requirement_definitions");
    assert.deepEqual(calls[0]?.filters, [
      ["tenant_id", TENANT_ID],
      ["status", "published"],
    ]);
  });
});
