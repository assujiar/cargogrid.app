/**
 * The real carrier/port/airport/customs poll-sync worker (IAE-016, Prompt
 * 344) -- the FOURTH real outbound HTTP client in this repository, after
 * IAE-012's webhook worker, IAE-014's notification worker and IAE-015's
 * geocode client. Consumes an already-claimed `app.jobs` row
 * (job_type='logistics_partner_sync', payload={connection_id, adapter_code}),
 * enqueued only by app.trigger_logistics_partner_poll_sync
 * (../../scripts/logistics-partner-sync-worker.ts's own caller,
 * ../../server/mutations/logistics-partner.ts).
 *
 * Unlike the webhook receiver (inbound, HMAC-authenticated, anon-callable),
 * this is the OUTBOUND "poll" direction: CargoGrid calling out to a
 * provider's own poll endpoint and recording whatever batch of events comes
 * back. A malformed/invalid individual event within a batch is skipped, not
 * fatal to the whole batch -- the same "provider variance is real, tolerate
 * it" posture the prompt's own test requirements name explicitly.
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse IAE-014/015 already established.
 */

import { getLogisticsPartnerConnectionForSync, getLogisticsPartnerCredential, type LogisticsPartnerQueryRpcClient } from "../../server/queries/logistics-partner.ts";
import { recordLogisticsPartnerSyncEvent, type LogisticsPartnerMutationRpcClient } from "../../server/mutations/logistics-partner.ts";
import { completeJob, type BackgroundJobMutationRpcClient } from "../../server/mutations/background-job.ts";
import { recordJobFailure, type ImportExportMutationRpcClient } from "../../server/mutations/import-export.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";
import { LOGISTICS_PARTNER_EVENT_TYPES } from "../../server/contracts/logistics-partner/logistics-partner.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const POLL_TIMEOUT_MS = 15_000;
const MAX_EVENTS_PER_BATCH = 500;

export type LogisticsPartnerDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type ProcessLogisticsPartnerSyncJobRpcClient = LogisticsPartnerQueryRpcClient & LogisticsPartnerMutationRpcClient & BackgroundJobMutationRpcClient & ImportExportMutationRpcClient;

export interface LogisticsPartnerSyncJobOutcome {
  readonly outcome: "synced" | "failed";
  readonly recordedCount: number;
  readonly skippedCount: number;
  readonly errorMessage: string | null;
}

function extractConnectionId(job: ImportExportJob): string | null {
  const value = job.payload.connection_id;
  return typeof value === "string" ? value : null;
}

interface RawSyncEvent {
  readonly event_id?: unknown;
  readonly event_type?: unknown;
  readonly external_reference?: unknown;
  readonly [key: string]: unknown;
}

/**
 * One real poll-sync attempt for one already-claimed logistics_partner_sync
 * job. Never throws for a delivery-side failure (no connection/credential,
 * HTTP error, timeout, malformed response) -- those are real, expected
 * outcomes reported back to app.record_job_failure. DOES throw for a genuine
 * wiring/programming invariant violation (a malformed job payload this
 * repository's own app.trigger_logistics_partner_poll_sync never produces).
 */
export async function processLogisticsPartnerSyncJob(client: ProcessLogisticsPartnerSyncJobRpcClient, job: ImportExportJob, workerId: string, actorLabel: string, checkUrlSafety: LogisticsPartnerDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<LogisticsPartnerSyncJobOutcome> {
  if (!job.requestedByAuthUserId) {
    throw new Error(`logistics_partner_sync job ${job.jobId} has no requested_by_auth_user_id -- this job was not enqueued by app.trigger_logistics_partner_poll_sync`);
  }
  const actorAuthUserId = job.requestedByAuthUserId;

  const connectionId = extractConnectionId(job);
  if (!connectionId) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: "logistics_partner_sync job payload is missing connection_id", actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage: "missing connection_id in job payload" };
  }

  const connection = await getLogisticsPartnerConnectionForSync(client, connectionId);
  if (!connection || connection.connectionStatus !== "active") {
    const errorMessage = `no active logistics-partner connection ${connectionId}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const pollUrl = typeof connection.connectionConfig.pollUrl === "string" ? connection.connectionConfig.pollUrl : null;
  if (!pollUrl) {
    const errorMessage = `logistics-partner connection ${connectionId} has no pollUrl configured`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const urlSafety = await checkUrlSafety(pollUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to poll: ${urlSafety.reason ?? "provider pollUrl failed the delivery-time safety check"}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const credential = await getLogisticsPartnerCredential(client, connectionId);
  if (!credential) {
    const errorMessage = `logistics-partner connection ${connectionId} has no stored credential`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
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
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `logistics-partner provider responded with HTTP ${response.status}`;
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  let body: { events?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = "logistics-partner provider returned a non-JSON response body";
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", recordedCount: 0, skippedCount: 0, errorMessage };
  }

  const events = Array.isArray(body.events) ? (body.events as RawSyncEvent[]).slice(0, MAX_EVENTS_PER_BATCH) : [];
  let recordedCount = 0;
  let skippedCount = 0;

  for (const event of events) {
    const providerEventId = typeof event.event_id === "string" ? event.event_id : null;
    const eventType = typeof event.event_type === "string" ? event.event_type : null;
    const externalReference = typeof event.external_reference === "string" ? event.external_reference : null;
    if (!providerEventId || !eventType || !(LOGISTICS_PARTNER_EVENT_TYPES as readonly string[]).includes(eventType)) {
      skippedCount++;
      continue;
    }
    await recordLogisticsPartnerSyncEvent(client, {
      tenantId: connection.tenantId,
      connectionId,
      providerEventId,
      eventType: eventType as (typeof LOGISTICS_PARTNER_EVENT_TYPES)[number],
      externalReference,
      rawPayload: event as Record<string, unknown>,
      actorAuthUserId,
      actorLabel,
    });
    recordedCount++;
  }

  await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
  return { outcome: "synced", recordedCount, skippedCount, errorMessage: null };
}
