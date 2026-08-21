/**
 * The real notification delivery worker (IAE-014, Prompt 342) -- the SECOND
 * real outbound HTTP client in this repository, directly modeled on IAE-012's
 * webhook delivery worker (../webhooks/process-webhook-delivery-job.server.ts).
 * Fills the gap PLT-127's own header explicitly disclosed: "no code anywhere
 * in this repository ever calls a real email provider."
 *
 * Takes an ALREADY-CLAIMED `app.jobs` row (job_type='notification_batch',
 * payload={notification_id}) -- claiming is the caller's own responsibility
 * (../../scripts/jobs/notification-delivery-worker.ts).
 *
 * Per `RPD-038`/`ADR-0025` Part C ("no generic provider abstraction,
 * case-by-case adapters"): the claim/dispatch/report LOOP below is shared
 * queue plumbing (the same shape any app.jobs consumer needs), but the
 * actual request shape sent to each provider is a distinct, named function
 * per channel (dispatchEmail/dispatchWhatsApp/dispatchSms) -- never one
 * generic "send" abstraction spanning all three.
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly (already channel-agnostic: "is this URL safe to POST to") --
 * applying Batch 3's own Tier C SSRF lesson proactively, rather than waiting
 * for a future review to catch it here too.
 */

import { getNotificationDispatchInfo, getNotificationProviderCredential, type NotificationQueryRpcClient } from "../../server/queries/notification.ts";
import { recordNotificationDeliveryAttempt, type NotificationMutationRpcClient } from "../../server/mutations/notification.ts";
import { completeJob, type BackgroundJobMutationRpcClient } from "../../server/mutations/background-job.ts";
import { recordJobFailure, type ImportExportMutationRpcClient } from "../../server/mutations/import-export.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const DELIVERY_TIMEOUT_MS = 10_000;

export type NotificationDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type ProcessNotificationDeliveryJobRpcClient = NotificationQueryRpcClient & NotificationMutationRpcClient & BackgroundJobMutationRpcClient & ImportExportMutationRpcClient;

export interface NotificationDeliveryJobOutcome {
  readonly outcome: "delivered" | "already_terminal" | "failed";
  readonly errorMessage: string | null;
}

function extractNotificationId(job: ImportExportJob): string | null {
  const value = job.payload.notification_id;
  return typeof value === "string" ? value : null;
}

interface ProviderDispatchResult {
  readonly success: boolean;
  readonly errorMessage: string | null;
  /** A real, disclosed placeholder unit cost -- no live provider pricing feed exists anywhere in this repository (disclosed). Proportional to payload size only so the +20% markup (RPD-028) has a genuine, non-constant number to compute against. */
  readonly providerUnitCostAmount: number;
}

function placeholderCost(payloadLength: number): number {
  return Math.round((0.005 + payloadLength * 0.00001) * 10000) / 10000;
}

async function dispatchEmail(apiUrl: string, credential: string, to: string, subject: string, body: string, signal: AbortSignal): Promise<ProviderDispatchResult> {
  const payload = JSON.stringify({ to, subject, body });
  const response = await fetch(apiUrl, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${credential}` },
    body: payload,
    signal,
    redirect: "manual",
  });
  return { success: response.status >= 200 && response.status < 300, errorMessage: response.ok ? null : `email provider responded with HTTP ${response.status}`, providerUnitCostAmount: placeholderCost(payload.length) };
}

async function dispatchWhatsApp(apiUrl: string, credential: string, to: string, body: string, signal: AbortSignal): Promise<ProviderDispatchResult> {
  const payload = JSON.stringify({ to, message: body, type: "text" });
  const response = await fetch(apiUrl, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${credential}` },
    body: payload,
    signal,
    redirect: "manual",
  });
  return { success: response.status >= 200 && response.status < 300, errorMessage: response.ok ? null : `WhatsApp provider responded with HTTP ${response.status}`, providerUnitCostAmount: placeholderCost(payload.length) };
}

async function dispatchSms(apiUrl: string, credential: string, to: string, body: string, signal: AbortSignal): Promise<ProviderDispatchResult> {
  const payload = JSON.stringify({ to, text: body });
  const response = await fetch(apiUrl, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${credential}` },
    body: payload,
    signal,
    redirect: "manual",
  });
  return { success: response.status >= 200 && response.status < 300, errorMessage: response.ok ? null : `SMS provider responded with HTTP ${response.status}`, providerUnitCostAmount: placeholderCost(payload.length) };
}

/**
 * One real dispatch attempt for one already-claimed notification_batch job.
 * Never throws for a delivery-side failure (HTTP error, timeout, missing
 * connection/credential/recipient address) -- those are real, expected
 * outcomes reported back to app.record_notification_delivery_attempt/
 * app.record_job_failure. DOES throw for a genuine wiring/programming
 * invariant violation (a malformed payload this repository's own
 * app.queue_notification never produces).
 */
export async function processNotificationDeliveryJob(client: ProcessNotificationDeliveryJobRpcClient, job: ImportExportJob, workerId: string, actorLabel: string, checkUrlSafety: NotificationDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<NotificationDeliveryJobOutcome> {
  if (!job.requestedByAuthUserId) {
    throw new Error(`notification_batch job ${job.jobId} has no requested_by_auth_user_id -- this job was not enqueued by app.queue_notification`);
  }
  const actorAuthUserId = job.requestedByAuthUserId;

  const notificationId = extractNotificationId(job);
  if (!notificationId) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: "notification_batch job payload is missing notification_id", actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage: "missing notification_id in job payload" };
  }

  const dispatchInfo = await getNotificationDispatchInfo(client, notificationId);
  if (!dispatchInfo) {
    await recordJobFailure(client, { jobId: job.jobId, errorMessage: `notification ${notificationId} not found`, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage: "notification not found" };
  }

  if (dispatchInfo.status === "sent" || dispatchInfo.status === "skipped") {
    await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
    return { outcome: "already_terminal", errorMessage: null };
  }

  const recipientAddress = dispatchInfo.effectiveChannel === "email" ? dispatchInfo.recipientEmail : dispatchInfo.recipientContactAddress;
  if (!recipientAddress) {
    const errorMessage = `no ${dispatchInfo.effectiveChannel === "email" ? "email address" : "contact address"} on file for this recipient`;
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage };
  }

  if (!dispatchInfo.connectionId || dispatchInfo.connectionStatus !== "active") {
    const errorMessage = `no active ${dispatchInfo.effectiveChannel} provider connection configured for this tenant`;
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage };
  }

  const apiUrl = typeof dispatchInfo.connectionConfig?.apiUrl === "string" ? dispatchInfo.connectionConfig.apiUrl : null;
  if (!apiUrl) {
    const errorMessage = `${dispatchInfo.effectiveChannel} provider connection has no apiUrl configured`;
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage };
  }

  const urlSafety = await checkUrlSafety(apiUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to dispatch: ${urlSafety.reason ?? "provider apiUrl failed the delivery-time safety check"}`;
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage };
  }

  const credential = await getNotificationProviderCredential(client, dispatchInfo.connectionId);
  if (!credential) {
    const errorMessage = `${dispatchInfo.effectiveChannel} provider connection has no stored credential`;
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage };
  }

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), DELIVERY_TIMEOUT_MS);
  let result: ProviderDispatchResult;
  try {
    if (dispatchInfo.effectiveChannel === "email") {
      result = await dispatchEmail(apiUrl, credential, recipientAddress, dispatchInfo.subject, dispatchInfo.body, controller.signal);
    } else if (dispatchInfo.effectiveChannel === "whatsapp") {
      result = await dispatchWhatsApp(apiUrl, credential, recipientAddress, dispatchInfo.body, controller.signal);
    } else if (dispatchInfo.effectiveChannel === "sms") {
      result = await dispatchSms(apiUrl, credential, recipientAddress, dispatchInfo.body, controller.signal);
    } else {
      throw new Error(`notification_batch job ${job.jobId} has effectiveChannel=${dispatchInfo.effectiveChannel} -- in_app never reaches this worker`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error && error.name === "AbortError" ? `request timed out after ${DELIVERY_TIMEOUT_MS}ms` : error instanceof Error ? error.message : "unknown fetch error";
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    await recordJobFailure(client, { jobId: job.jobId, errorMessage, actorAuthUserId, actorLabel });
    return { outcome: "failed", errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (result.success) {
    await recordNotificationDeliveryAttempt(client, { notificationId, status: "success", errorMessage: null, actorAuthUserId, actorLabel, providerUnitCostAmount: result.providerUnitCostAmount, currency: "USD" });
    await completeJob(client, { jobId: job.jobId, workerId, resultUrl: null, actorLabel });
    return { outcome: "delivered", errorMessage: null };
  }

  await recordNotificationDeliveryAttempt(client, { notificationId, status: "failed", errorMessage: result.errorMessage, actorAuthUserId, actorLabel });
  await recordJobFailure(client, { jobId: job.jobId, errorMessage: result.errorMessage ?? "unknown delivery failure", actorAuthUserId, actorLabel });
  return { outcome: "failed", errorMessage: result.errorMessage };
}
