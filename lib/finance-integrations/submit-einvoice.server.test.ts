import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { submitEinvoice, type SubmitEinvoiceRpcClient } from "./submit-einvoice.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "323e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

interface RecordedCalls {
  requests: Record<string, unknown>[];
}

function mockClient(apiUrl: string | null, recorded: RecordedCalls = { requests: [] }, credential: string | null = "test-credential-value"): SubmitEinvoiceRpcClient {
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_finance_provider_dispatch_info") {
        return { data: { connection_id: CONNECTION_ID, connection_status: "active", connection_config: apiUrl ? { apiUrl } : {} }, error: null };
      }
      if (fn === "get_finance_provider_credential") {
        return { data: credential, error: null };
      }
      if (fn === "record_einvoice_submission_attempt") {
        recorded.requests.push(args);
        return {
          data: {
            id: "523e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, connection_id: args.p_connection_id, call_type: "einvoice_submission",
            finance_invoice_id: args.p_finance_invoice_id, tax_code: null, as_of_date: null, request_payload: args.p_request_payload, status: args.p_status,
            response_payload: args.p_response_payload ?? null, provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null, currency: args.p_currency ?? null,
            billed_amount: null, error_message: args.p_error_message ?? null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z",
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as SubmitEinvoiceRpcClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/submit` };
}

describe("submitEinvoice", () => {
  test("a real 2xx provider response with a providerReference succeeds and records a real cost", async () => {
    const received: { headers: Record<string, string | string[] | undefined>; body: string }[] = [];
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        received.push({ headers: req.headers, body });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ providerReference: "EINV-REF-001" }));
      });
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client = mockClient(url, recorded);
      const result = await submitEinvoice(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", financeInvoiceId: INVOICE_ID, invoicePayload: { number: "INV-2026-000001" } }, ALLOW_ALL_URLS);

      assert.equal(result.success, true);
      assert.equal(result.providerReference, "EINV-REF-001");
      assert.equal(recorded.requests.length, 1);
      assert.equal(recorded.requests[0]?.p_status, "success");
      assert.ok((recorded.requests[0]?.p_provider_unit_cost_amount as number) > 0);
      assert.equal(received[0]?.headers["authorization"], "Bearer test-credential-value");
    } finally {
      server.close();
    }
  });

  test("a real non-2xx provider response fails cleanly", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client = mockClient(url, recorded);
      const result = await submitEinvoice(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", financeInvoiceId: INVOICE_ID, invoicePayload: {} }, ALLOW_ALL_URLS);

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(recorded.requests[0]?.p_status, "failed");
    } finally {
      server.close();
    }
  });

  test("no active connection fails without attempting a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client: SubmitEinvoiceRpcClient = {
        rpc: async (fn: string, args: Record<string, unknown>) => {
          if (fn === "get_finance_provider_dispatch_info") {
            return { data: { connection_id: CONNECTION_ID, connection_status: "disabled", connection_config: { apiUrl: url } }, error: null };
          }
          if (fn === "record_einvoice_submission_attempt") {
            recorded.requests.push(args);
            return {
              data: {
                id: "523e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, connection_id: args.p_connection_id, call_type: "einvoice_submission",
                finance_invoice_id: args.p_finance_invoice_id, tax_code: null, as_of_date: null, request_payload: args.p_request_payload, status: args.p_status,
                response_payload: null, provider_unit_cost_amount: null, currency: null, billed_amount: null, error_message: args.p_error_message ?? null,
                requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z",
              },
              error: null,
            };
          }
          throw new Error(`unexpected rpc call: ${fn}, args=${JSON.stringify(args)}`);
        },
      } as unknown as SubmitEinvoiceRpcClient;
      const result = await submitEinvoice(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", financeInvoiceId: INVOICE_ID, invoicePayload: {} }, ALLOW_ALL_URLS);

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /no active einvoice_provider/);
      assert.equal(called, false);
    } finally {
      server.close();
    }
  });

  test("the REAL (non-injected) SSRF guard refuses a literal private-IP provider apiUrl without attempting a live HTTP call", async () => {
    const client = mockClient("https://169.254.169.254/latest/meta-data/");
    const result = await submitEinvoice(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", financeInvoiceId: INVOICE_ID, invoicePayload: {} });

    assert.equal(result.success, false);
    assert.match(result.errorMessage ?? "", /refusing to dispatch/);
  });
});
