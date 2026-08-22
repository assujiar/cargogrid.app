import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { processOcrDocumentJob, type ProcessOcrDocumentJobClient } from "./process-ocr-document.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";

interface RecordedCalls {
  rpc: { fn: string; args: Record<string, unknown> }[];
}

function fakeClient(options: { apiUrl?: string | null; connectionStatus?: string; jobStatus?: string; recorded?: RecordedCalls }): ProcessOcrDocumentJobClient {
  const recorded = options.recorded ?? { rpc: [] };
  const connectionStatus = options.connectionStatus ?? "active";

  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      recorded.rpc.push({ fn, args });
      if (fn === "get_ai_governed_dispatch_info") {
        return { data: { connection_id: CONNECTION_ID, connection_status: connectionStatus, connection_config: options.apiUrl ? { apiUrl: options.apiUrl } : {} }, error: null };
      }
      if (fn === "get_ai_governed_credential") {
        return { data: "test-credential", error: null };
      }
      if (fn === "request_ai_governed_action") {
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: args.p_connection_id, feature_code: args.p_feature_code,
            correlation_record_type: args.p_correlation_record_type ?? null, correlation_record_id: args.p_correlation_record_id ?? null,
            prompt_payload: args.p_prompt_payload, status: "pending", output_payload: null, confidence_label: null,
            model_version: null, provider_unit_cost_amount: null, currency: null, billed_amount: null, error_message: null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
          },
          error: null,
        };
      }
      if (fn === "record_ai_governed_request_outcome") {
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "ocr_document_extraction",
            correlation_record_type: "file", correlation_record_id: FILE_ID, prompt_payload: {}, status: args.p_status,
            output_payload: args.p_output_payload ?? null, confidence_label: args.p_confidence_label ?? null,
            model_version: args.p_model_version ?? null, provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null,
            currency: args.p_currency ?? null, billed_amount: 0.02, error_message: args.p_error_message ?? null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-22T00:00:00.000Z",
            completed_at: "2026-08-22T00:01:00.000Z",
          },
          error: null,
        };
      }
      if (fn === "record_ocr_document_job_outcome") {
        return {
          data: {
            id: JOB_ID, tenant_id: TENANT_ID, file_id: FILE_ID, ai_governed_request_id: args.p_ai_governed_request_id,
            document_type_hint: "finance", status: options.jobStatus ?? "extracted",
            reviewer_corrected_fields: null, low_confidence_override_reason: null, applied_target_type: null, applied_target_id: null,
            dismiss_reason: null, requested_by: "test", reviewed_by: null, created_at: "2026-08-22T00:00:00.000Z", reviewed_at: null, applied_at: null,
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as ProcessOcrDocumentJobClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/infer` };
}

describe("processOcrDocumentJob", () => {
  test("a real succeeded dispatch syncs the job to extracted and never sends file content bytes -- only metadata", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.equal(parsed.file.id, FILE_ID);
        assert.equal(parsed.file.originalFilename, "invoice-scan.pdf");
        assert.equal(parsed.file.mimeType, "application/pdf");
        assert.equal(parsed.documentTypeHint, "finance");
        assert.ok(!("content" in parsed.file) && !("bytes" in parsed.file));
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { extractedSubject: "Vendor invoice #INV-2091" }, confidenceLabel: "high" }));
      });
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, jobStatus: "extracted", recorded });
      const result = await processOcrDocumentJob(
        client,
        { tenantId: TENANT_ID, jobId: JOB_ID, fileId: FILE_ID, documentTypeHint: "finance", originalFilename: "invoice-scan.pdf", mimeType: "application/pdf", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, true);
      assert.equal(result.requestId, REQUEST_ID);
      assert.equal(result.job.status, "extracted");
      assert.ok(recorded.rpc.some((call) => call.fn === "record_ocr_document_job_outcome" && call.args.p_job_id === JOB_ID && call.args.p_ai_governed_request_id === REQUEST_ID));
    } finally {
      server.close();
    }
  });

  test("a real dispatch failure still syncs the job -- to failed, not left pending", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, jobStatus: "failed", recorded });
      const result = await processOcrDocumentJob(
        client,
        { tenantId: TENANT_ID, jobId: JOB_ID, fileId: FILE_ID, documentTypeHint: "finance", originalFilename: "invoice-scan.pdf", mimeType: "application/pdf", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(result.job.status, "failed");
      assert.ok(recorded.rpc.some((call) => call.fn === "record_ocr_document_job_outcome"));
    } finally {
      server.close();
    }
  });

  test("no active connection configured -- throws before any job sync is attempted", async () => {
    const recorded: RecordedCalls = { rpc: [] };
    const client = fakeClient({ connectionStatus: "inactive", recorded });
    await assert.rejects(() =>
      processOcrDocumentJob(client, { tenantId: TENANT_ID, jobId: JOB_ID, fileId: FILE_ID, documentTypeHint: "finance", originalFilename: "invoice-scan.pdf", mimeType: "application/pdf", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" }, ALLOW_ALL_URLS),
    );
    assert.ok(!recorded.rpc.some((call) => call.fn === "record_ocr_document_job_outcome"));
  });
});
