/**
 * The real external accounting/HR sync poll worker (IAE-018, Prompt 346) --
 * the EIGHTH real outbound HTTP client in this repository. Consumes an
 * already-claimed `app.jobs` row (job_type='external_sync',
 * payload={connection_id, adapter_code, entity_type}), enqueued only by
 * app.trigger_external_sync (../../server/mutations/external-sync.ts).
 *
 * Every fetched snapshot is handed to app.record_external_sync_snapshot,
 * which NEVER writes to app.employees/app.finance_accounts -- this worker
 * is therefore inherently a dry run in the sense that matters (nothing
 * commits to HRIS/Finance truth), consistent with the migration's own
 * design decision 5. A malformed/unrecognized individual record within a
 * batch is skipped, not fatal to the whole batch -- the same "provider
 * variance is real, tolerate it" posture IAE-016's own poll worker already
 * established.
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse every prior real outbound client in
 * this repository has already established.
 */

import { getExternalSyncConnectionForSync, getExternalSyncCredential, type ExternalSyncQueryRpcClient } from "../../server/queries/external-sync.ts";
import { recordExternalSyncSnapshot, type ExternalSyncMutationRpcClient } from "../../server/mutations/external-sync.ts";
import { completeJob, type BackgroundJobMutationRpcClient } from "../../server/mutations/background-job.ts";
import { recordJobFailure, type ImportExportMutationRpcClient } from "../../server/mutations/import-export.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";
import { EXTERNAL_SYNC_ENTITY_TYPES, EXTERNAL_SYNC_ADAPTER_CODES } from "../../server/contracts/external-sync/external-sync.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const POLL_TIMEOUT_MS = 15_000;
const MAX_RECORDS_PER_BATCH = 500;

export type ExternalSyncDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type ProcessExternalSyncJobRpcClient = ExternalSyncQueryRpcClient & ExternalSyncMutationRpcClient & BackgroundJobMutationRpcClient & ImportExportMutationRpcClient;

export interface ExternalSyncJobOutcome {
  readonly outcome: "synced" | "failed";
  readonly recordedCount: number;
  readonly skippedCount: number;
  readonly errorMessage: string | null;
}

interface RawSyncRecord {
  readonly externalEntityId?: unknown;
  readonly payload?: unknown;
}

function extractPayload(job: ImportExportJob): { connectionId: string | null; adapterCode: string | null; entityType: string | null } {
  const connectionId = typeof job.payload.connection_id === "string" ? job.payload.connection_id : null;
  const adapterCode = typeof job.payload.adapter_code === "string" ? job.payload.adapter_code : null;
  const entityType = typeof job.payload.entity_type === "string" ? job.payload.entity_type : null;
  return { connectionId, adapterCode, entityType };
}

/**
 * One real fetch-and-record attempt for one already-claimed external_sync
 * job. Never throws for a delivery-side failure (no connection/credential,
 * HTTP error, timeout, malformed response) -- those are real, expected
 * outcomes reported back to app.record_job_failure. DOES throw for a
 * genuine wiring/programming invariant violation (a malformed job payload
 * this repository's own app.trigger_external_sync never produces).
 */
export async function processExternalSyncJob(client: ProcessExternalSyncJobRpcClient, job: ImportExportJob, workerId: string, actorLabel: string, checkUrlSafety: ExternalSyncDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<ExternalSyncJobOutcome> {
  if (!job.requestedByAuthUserId) {
    throw new Error(`external_sync job ${job.jobId} has no requested_by_auth_user_id -- this job was not enqueued by app.trigger_external_sync`);
  }
  const actorAuthUserId = job.requestedByAuthUserId;

  const { connectionId, adapterCode, entityType } = extractPayload(job);
  if (!connectionId || !adapterCode || !entityType || !(EXTERNAL_SYNC_ADAPTER_CODES as readonly string[]).includes(adapterCode) || !(EXTERNAL_SYNC_ENTITY_TYPES as readonly string[]).includes(entityType)) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: "external_sync job payload is missing/invalid connection_id, adapter_code, or entity_type", actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage: "missing/invalid job payload" };
  }

  const connection = await getExternalSyncConnectionForSync(client, connectionId);
  if (!connection || connection.connectionStatus !== "active") {
    const errorMessage = `no active ${adapterCode} connection ${connectionId}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const pollUrl = typeof connection.connectionConfig.pollUrl === "string" ? connection.connectionConfig.pollUrl : null;
  if (!pollUrl) {
    const errorMessage = `${adapterCode} connection ${connectionId} has no pollUrl configured`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const urlSafety = await checkUrlSafety(pollUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to poll: ${urlSafety.reason ?? "provider pollUrl failed the delivery-time safety check"}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const credential = await getExternalSyncCredential(client, connectionId);
  if (!credential) {
    const errorMessage = `${adapterCode} connection ${connectionId} has no stored credential`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), POLL_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(`${pollUrl}?entityType=${encodeURIComponent(entityType)}`, {
      method: "GET",
      headers: { authorization: `Bearer ${credential}` },
      signal: controller.signal,
      redirect: "manual",
    });
  } catch (error) {
    const errorMessage = error instanceof Error && error.name === "AbortError" ? `poll request timed out after ${POLL_TIMEOUT_MS}ms` : error instanceof Error ? error.message : "unknown fetch error";
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `${adapterCode} provider responded with HTTP ${response.status}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  let body: { records?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = `${adapterCode} provider returned a non-JSON response body`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const records = Array.isArray(body.records) ? (body.records as RawSyncRecord[]).slice(0, MAX_RECORDS_PER_BATCH) : [];
  let recordedCount = 0;
  let skippedCount = 0;

  for (const record of records) {
    const externalEntityId = typeof record.externalEntityId === "string" ? record.externalEntityId : null;
    const payload = record.payload && typeof record.payload === "object" ? (record.payload as Record<string, unknown>) : null;
    if (!externalEntityId || !payload) {
      skippedCount++;
      continue;
    }
    await recordExternalSyncSnapshot(client, {
      tenantId: connection.tenantId,
      connectionId,
      adapterCode: adapterCode as (typeof EXTERNAL_SYNC_ADAPTER_CODES)[number],
      entityType: entityType as (typeof EXTERNAL_SYNC_ENTITY_TYPES)[number],
      externalEntityId,
      rawPayload: payload,
      actorAuthUserId,
      actorLabel,
    });
    recordedCount++;
  }

  await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
  return { outcome: "synced", recordedCount, skippedCount, errorMessage: null };
}
