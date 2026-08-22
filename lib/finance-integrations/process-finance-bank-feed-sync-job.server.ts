/**
 * The real bank-feed poll-sync worker (IAE-017, Prompt 345) -- the FIFTH
 * real outbound HTTP client in this repository, after IAE-012's webhook
 * worker, IAE-014's notification worker, IAE-015's geocode client, and
 * IAE-016's logistics-partner sync worker. Consumes an already-claimed
 * `app.jobs` row (job_type='finance_bank_feed_sync',
 * payload={connection_id, bank_account_id}), enqueued only by
 * app.trigger_finance_bank_feed_sync (../../server/mutations/bank-payment-tax-integrations.ts).
 *
 * Fills the exact gap FIN-211's own migration header disclosed: "no live
 * bank-API adapter is built here... a caller-supplied, already-parsed batch
 * of lines." This worker fetches that real batch and hands it, unmodified in
 * shape, to the existing, UNMODIFIED app.import_finance_bank_statement --
 * every idempotency/dedup guarantee that RPC already provides is inherited
 * for free (batch-level source_reference uniqueness, line-level line_hash
 * dedup).
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse every prior real outbound client in
 * this repository has already established.
 */

import { getFinanceProviderConnectionForSync, getFinanceProviderCredential, type FinanceIntegrationsQueryRpcClient } from "../../server/queries/bank-payment-tax-integrations.ts";
import { importFinanceBankStatement, type CashBankMutationRpcClient } from "../../server/mutations/cash-bank.ts";
import type { FinanceBankStatementLine } from "../../server/contracts/cash-bank/cash-bank.ts";
import { completeJob, type BackgroundJobMutationRpcClient } from "../../server/mutations/background-job.ts";
import { recordJobFailure, type ImportExportMutationRpcClient } from "../../server/mutations/import-export.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const POLL_TIMEOUT_MS = 15_000;

export type FinanceProviderDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type ProcessFinanceBankFeedSyncJobRpcClient = FinanceIntegrationsQueryRpcClient & CashBankMutationRpcClient & BackgroundJobMutationRpcClient & ImportExportMutationRpcClient;

export interface FinanceBankFeedSyncJobOutcome {
  readonly outcome: "synced" | "failed";
  readonly lineCount: number;
  readonly errorMessage: string | null;
}

function extractPayload(job: ImportExportJob): { connectionId: string | null; bankAccountId: string | null } {
  const connectionId = typeof job.payload.connection_id === "string" ? job.payload.connection_id : null;
  const bankAccountId = typeof job.payload.bank_account_id === "string" ? job.payload.bank_account_id : null;
  return { connectionId, bankAccountId };
}

/**
 * One real bank-feed fetch-and-import attempt for one already-claimed
 * finance_bank_feed_sync job. Never throws for a delivery-side failure (no
 * connection/credential, HTTP error, timeout, malformed response) -- those
 * are real, expected outcomes reported back to app.record_job_failure. DOES
 * throw for a genuine wiring/programming invariant violation (a malformed
 * job payload this repository's own app.trigger_finance_bank_feed_sync
 * never produces).
 */
export async function processFinanceBankFeedSyncJob(client: ProcessFinanceBankFeedSyncJobRpcClient, job: ImportExportJob, workerId: string, actorLabel: string, checkUrlSafety: FinanceProviderDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<FinanceBankFeedSyncJobOutcome> {
  if (!job.requestedByAuthUserId) {
    throw new Error(`finance_bank_feed_sync job ${job.jobId} has no requested_by_auth_user_id -- this job was not enqueued by app.trigger_finance_bank_feed_sync`);
  }
  const actorAuthUserId = job.requestedByAuthUserId;

  const { connectionId, bankAccountId } = extractPayload(job);
  if (!connectionId || !bankAccountId) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: "finance_bank_feed_sync job payload is missing connection_id/bank_account_id", actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage: "missing connection_id/bank_account_id in job payload" };
  }

  const connection = await getFinanceProviderConnectionForSync(client, connectionId);
  if (!connection || connection.connectionStatus !== "active") {
    const errorMessage = `no active bank_feed_api connection ${connectionId}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  const pollUrl = typeof connection.connectionConfig.pollUrl === "string" ? connection.connectionConfig.pollUrl : null;
  if (!pollUrl) {
    const errorMessage = `bank feed connection ${connectionId} has no pollUrl configured`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  const urlSafety = await checkUrlSafety(pollUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to poll: ${urlSafety.reason ?? "provider pollUrl failed the delivery-time safety check"}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  const credential = await getFinanceProviderCredential(client, connectionId);
  if (!credential) {
    const errorMessage = `bank feed connection ${connectionId} has no stored credential`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), POLL_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(pollUrl, {
      method: "GET",
      headers: { authorization: `Bearer ${credential}` },
      signal: controller.signal,
      redirect: "manual",
    });
  } catch (error) {
    const errorMessage = error instanceof Error && error.name === "AbortError" ? `poll request timed out after ${POLL_TIMEOUT_MS}ms` : error instanceof Error ? error.message : "unknown fetch error";
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `bank feed provider responded with HTTP ${response.status}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  let body: { sourceReference?: unknown; lines?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = "bank feed provider returned a non-JSON response body";
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  const sourceReference = typeof body.sourceReference === "string" ? body.sourceReference : null;
  const lines = Array.isArray(body.lines) ? (body.lines as FinanceBankStatementLine[]) : null;
  if (!sourceReference || !lines || lines.length === 0) {
    const errorMessage = "bank feed provider response is missing sourceReference, or lines is missing/empty";
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  let batch;
  try {
    batch = await importFinanceBankStatement(client, {
      tenantId: connection.tenantId,
      bankAccountId,
      sourceReference,
      lines,
      actorAuthUserId,
      actorLabel,
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "unknown error importing the fetched bank statement batch";
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", lineCount: 0, errorMessage };
  }

  await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
  return { outcome: "synced", lineCount: batch.lineCount, errorMessage: null };
}
