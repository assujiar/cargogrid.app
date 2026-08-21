/**
 * The real webhook delivery worker (IAE-012, Prompt 340) -- the first outbound
 * HTTP client anywhere in this repository (confirmed by direct repository-wide
 * grep before writing this file: zero `fetch()`/`axios`/`http.request` call to
 * an arbitrary external URL existed anywhere in `app/`, `lib/`, `server/`).
 * Fills the gap PLT-129's own header explicitly disclosed: "The bounded
 * delivery adapter interface... never calls a live HTTP endpoint itself."
 *
 * Takes an ALREADY-CLAIMED `app.jobs` row (job_type='webhook_retry',
 * payload={delivery_id}) -- claiming is the caller's own responsibility
 * (`app.claim_next_job`, see ../../scripts/jobs/webhook-delivery-worker.ts).
 * Looks up the delivery's own dispatch info (never the raw signing secret --
 * `app.get_webhook_delivery_dispatch_info` deliberately omits it), computes the
 * HMAC-SHA256 signature via the EXISTING `app.compute_webhook_signature` RPC
 * (ADR-0011) so the raw secret never leaves the database into application
 * memory, does the real POST with a bounded 10-second timeout, and reports the
 * outcome to BOTH state machines this checkpoint's own migration bridges:
 * `app.record_webhook_delivery_attempt` (the delivery's own informational
 * status/attempt history) and `app.complete_job`/`app.record_job_failure` (the
 * job's own real scheduling state -- see the migration's own design decision 2
 * for why these are two independent, deliberately-aligned-not-unified state
 * machines).
 */

import { getWebhookDeliveryDispatchInfo, type WebhookManagementQueryRpcClient } from "../../server/queries/webhook-management.ts";
import { computeWebhookSignature, type ApiKeyWebhookQueryRpcClient } from "../../server/queries/api-key-webhook.ts";
import { recordWebhookDeliveryAttempt, type ApiKeyWebhookMutationRpcClient } from "../../server/mutations/api-key-webhook.ts";
import { completeJob, type BackgroundJobMutationRpcClient } from "../../server/mutations/background-job.ts";
import { recordJobFailure, type ImportExportMutationRpcClient } from "../../server/mutations/import-export.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";

const DELIVERY_TIMEOUT_MS = 10_000;

export type ProcessWebhookDeliveryJobRpcClient = WebhookManagementQueryRpcClient & ApiKeyWebhookQueryRpcClient & ApiKeyWebhookMutationRpcClient & BackgroundJobMutationRpcClient & ImportExportMutationRpcClient;

export interface WebhookDeliveryJobOutcome {
  readonly outcome: "delivered" | "already_terminal" | "failed";
  readonly httpStatusCode: number | null;
  readonly errorMessage: string | null;
}

function extractDeliveryId(job: ImportExportJob): string | null {
  const value = job.payload.delivery_id;
  return typeof value === "string" ? value : null;
}

/**
 * One real dispatch attempt for one already-claimed webhook_retry job. Never
 * throws for a delivery-side failure (HTTP error, timeout, disabled endpoint)
 * -- those are real, expected outcomes reported back to both state machines.
 * DOES throw for a genuine wiring/programming invariant violation: every
 * webhook_retry job this repository ever enqueues (app.queue_webhook_delivery/
 * app.send_test_webhook_delivery/app.replay_webhook_delivery, this
 * checkpoint's own migration) always passes a real, authority-checked actor,
 * so `requested_by_auth_user_id` is only ever null for a genuinely different
 * class of job (a future system/scheduler-originated job type, per PLT-132's
 * own `alter table ... drop not null`) -- never a webhook_retry job. A null
 * here means this job was not enqueued by this checkpoint's own code, which
 * is a bug worth surfacing loudly rather than silently fabricating a fake
 * actor identity for the audit trail.
 */
export async function processWebhookDeliveryJob(client: ProcessWebhookDeliveryJobRpcClient, job: ImportExportJob, workerId: string, actorLabel: string): Promise<WebhookDeliveryJobOutcome> {
  if (!job.requestedByAuthUserId) {
    throw new Error(`webhook_retry job ${job.jobId} has no requested_by_auth_user_id -- this job was not enqueued by app.queue_webhook_delivery/send_test_webhook_delivery/replay_webhook_delivery`);
  }
  const actorAuthUserId = job.requestedByAuthUserId;

  const deliveryId = extractDeliveryId(job);
  if (!deliveryId) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: "webhook_retry job payload is missing delivery_id", actorAuthUserId, actorLabel });
    return { outcome: "failed", httpStatusCode: null, errorMessage: "missing delivery_id in job payload" };
  }

  const dispatchInfo = await getWebhookDeliveryDispatchInfo(client, deliveryId);
  if (!dispatchInfo) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: `webhook_delivery ${deliveryId} not found`, actorAuthUserId, actorLabel });
    return { outcome: "failed", httpStatusCode: null, errorMessage: "delivery not found" };
  }

  // A stale re-claim (the job's own lease expired after a worker crash, but a
  // PRIOR attempt already reached a terminal delivery state) -- complete the
  // job without a redundant live HTTP call.
  if (dispatchInfo.status === "delivered" || dispatchInfo.status === "dead_letter") {
    await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
    return { outcome: "already_terminal", httpStatusCode: null, errorMessage: null };
  }

  if (dispatchInfo.endpointStatus === "disabled") {
    const errorMessage = "endpoint is disabled and will not receive live traffic";
    await recordWebhookDeliveryAttempt(client, { deliveryId, status: "failed", httpStatusCode: null, errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", httpStatusCode: null, errorMessage };
  }

  const timestamp = Math.floor(Date.now() / 1000);
  const payloadText = JSON.stringify(dispatchInfo.payload);
  const signature = await computeWebhookSignature(client, dispatchInfo.webhookEndpointId, payloadText, timestamp);

  let httpStatusCode: number | null = null;
  let errorMessage: string | null = null;
  let success = false;

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), DELIVERY_TIMEOUT_MS);
  try {
    const response = await fetch(dispatchInfo.endpointUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-cargogrid-webhook-timestamp": String(timestamp),
        "x-cargogrid-webhook-signature": signature,
        "x-cargogrid-webhook-event": dispatchInfo.eventTypeCode,
        "x-cargogrid-webhook-delivery-id": deliveryId,
      },
      body: payloadText,
      signal: controller.signal,
    });
    httpStatusCode = response.status;
    success = response.status >= 200 && response.status < 300;
    if (!success) {
      errorMessage = `endpoint responded with HTTP ${response.status}`;
    }
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      errorMessage = `request timed out after ${DELIVERY_TIMEOUT_MS}ms`;
    } else {
      errorMessage = error instanceof Error ? error.message : "unknown fetch error";
    }
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (success) {
    await recordWebhookDeliveryAttempt(client, { deliveryId, status: "success", httpStatusCode, errorMessage: null, actorAuthUserId, actorLabel });
    await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
    return { outcome: "delivered", httpStatusCode, errorMessage: null };
  }

  await recordWebhookDeliveryAttempt(client, { deliveryId, status: "failed", httpStatusCode, errorMessage, actorAuthUserId, actorLabel });
  await recordJobFailure(client, { jobId: job.jobId, errorMessage: errorMessage ?? "unknown delivery failure", actorAuthUserId, actorLabel });
  return { outcome: "failed", httpStatusCode, errorMessage };
}
