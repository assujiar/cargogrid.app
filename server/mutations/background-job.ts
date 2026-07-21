/**
 * Background job framework mutation entry points (PLT-132, CG-S6-PLT-029). Thin, typed
 * wrappers around app.enqueue_job / app.claim_next_job / app.heartbeat_job /
 * app.complete_job / app.append_event_log / app.dispatch_event_as_job /
 * app.mark_event_dispatch_failed
 * (supabase/migrations/20260719180000_create_background_job_framework.sql). Every one
 * of these is service_role-only -- app.claim_next_job/app.heartbeat_job/
 * app.complete_job are worker-context functions (a live worker is a service identity,
 * never an authenticated tenant user), the same server-mediated design this session's
 * every prior capability established. cancelImportExportJob/acknowledgeJobCancellation/
 * recordJobFailure/requeueDeadLetterJob are reused directly from
 * ../mutations/import-export.ts for the generic job lifecycle too (PLT-131's own
 * functions already operate on any app.jobs row regardless of job_type) -- not
 * re-exported here to avoid a duplicate binding, import them from that module instead.
 */

import {
  EnqueueJobInputSchema,
  ClaimNextJobInputSchema,
  HeartbeatJobInputSchema,
  CompleteJobInputSchema,
  AppendEventLogInputSchema,
  DispatchEventAsJobInputSchema,
  MarkEventDispatchFailedInputSchema,
  parseEventLog,
  type EnqueueJobInput,
  type ClaimNextJobInput,
  type HeartbeatJobInput,
  type CompleteJobInput,
  type AppendEventLogInput,
  type DispatchEventAsJobInput,
  type MarkEventDispatchFailedInput,
  type EventLog,
} from "../contracts/background-job/background-job.ts";
import { parseImportExportJob, type ImportExportJob } from "../contracts/import-export/import-export.ts";

export interface BackgroundJobMutationRpcClient {
  rpc(
    fn:
      | "enqueue_job"
      | "claim_next_job"
      | "heartbeat_job"
      | "complete_job"
      | "append_event_log"
      | "dispatch_event_as_job"
      | "mark_event_dispatch_failed",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const BACKGROUND_JOB_KNOWN_MUTATION_ERROR_CODES = [
  "job_actor_unauthorized",
  "job_type_requires_dedicated_entrypoint",
  "job_invalid_type",
  "job_unsafe_payload",
  "job_invalid_max_attempts",
  "job_worker_id_required",
  "job_invalid_lease_duration",
  "job_not_found",
  "job_lease_not_held",
  "event_missing_type",
  "event_missing_resource_type",
  "event_unsafe_payload",
  "event_not_found",
  "event_invalid_job_type",
] as const;
type KnownBackgroundJobMutationErrorCode = (typeof BACKGROUND_JOB_KNOWN_MUTATION_ERROR_CODES)[number];
export type BackgroundJobMutationErrorCode = KnownBackgroundJobMutationErrorCode | "mutation_failed" | "invalid_response";

export class BackgroundJobMutationError extends Error {
  readonly code: BackgroundJobMutationErrorCode;

  constructor(code: BackgroundJobMutationErrorCode, message: string) {
    super(message);
    this.name = "BackgroundJobMutationError";
    this.code = code;
  }
}

function classifyError(message: string): BackgroundJobMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (BACKGROUND_JOB_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownBackgroundJobMutationErrorCode)
    : "mutation_failed";
}

/** The generic enqueue entrypoint for the eight non-import/export job_type codes. Idempotent per (tenantId, idempotencyKey). */
export async function enqueueJob(client: BackgroundJobMutationRpcClient, input: EnqueueJobInput): Promise<ImportExportJob> {
  const parsedInput = EnqueueJobInputSchema.parse(input);
  const { data, error } = await client.rpc("enqueue_job", {
    p_tenant_id: parsedInput.tenantId,
    p_job_type: parsedInput.jobType,
    p_payload: parsedInput.payload,
    p_priority: parsedInput.priority,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_max_attempts: parsedInput.maxAttempts,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "enqueue_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** SELECT ... FOR UPDATE SKIP LOCKED under the hood -- returns null when nothing is claimable, never throws for "no work available." */
export async function claimNextJob(client: BackgroundJobMutationRpcClient, input: ClaimNextJobInput): Promise<ImportExportJob | null> {
  const parsedInput = ClaimNextJobInputSchema.parse(input);
  const { data, error } = await client.rpc("claim_next_job", {
    p_worker_id: parsedInput.workerId,
    p_job_types: parsedInput.jobTypes,
    p_lease_duration_seconds: parsedInput.leaseDurationSeconds,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (data === null) {
    return null;
  }
  if (typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "claim_next_job returned a non-object, non-null result");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** Extends the lease -- throws job_lease_not_held if the caller no longer holds it (another worker may have already reclaimed a job whose lease this caller let expire). */
export async function heartbeatJob(client: BackgroundJobMutationRpcClient, input: HeartbeatJobInput): Promise<ImportExportJob> {
  const parsedInput = HeartbeatJobInputSchema.parse(input);
  const { data, error } = await client.rpc("heartbeat_job", {
    p_job_id: parsedInput.jobId,
    p_worker_id: parsedInput.workerId,
    p_lease_duration_seconds: parsedInput.leaseDurationSeconds,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "heartbeat_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** Terminal success -- only the current lease holder may complete a job. */
export async function completeJob(client: BackgroundJobMutationRpcClient, input: CompleteJobInput): Promise<ImportExportJob> {
  const parsedInput = CompleteJobInputSchema.parse(input);
  const { data, error } = await client.rpc("complete_job", {
    p_job_id: parsedInput.jobId,
    p_worker_id: parsedInput.workerId,
    p_result_url: parsedInput.resultUrl,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "complete_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** The outbox write path -- any future domain capability calls this to record a business event. */
export async function appendEventLog(client: BackgroundJobMutationRpcClient, input: AppendEventLogInput): Promise<EventLog> {
  const parsedInput = AppendEventLogInputSchema.parse(input);
  const { data, error } = await client.rpc("append_event_log", {
    p_tenant_id: parsedInput.tenantId,
    p_event_type: parsedInput.eventType,
    p_resource_type: parsedInput.resourceType,
    p_resource_id: parsedInput.resourceId,
    p_payload: parsedInput.payload,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "append_event_log returned no row");
  }
  return parseEventLog(data as Record<string, unknown>);
}

/** The real outbox-drain mechanic -- idempotent, re-dispatching an already-dispatched event returns the same linked job. The live scheduler that would call this periodically is disclosed NOT_RUN (no cron/poll infrastructure exists anywhere in this repository yet). */
export async function dispatchEventAsJob(client: BackgroundJobMutationRpcClient, input: DispatchEventAsJobInput): Promise<ImportExportJob> {
  const parsedInput = DispatchEventAsJobInputSchema.parse(input);
  const { data, error } = await client.rpc("dispatch_event_as_job", {
    p_event_id: parsedInput.eventId,
    p_job_type: parsedInput.jobType,
    p_priority: parsedInput.priority,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_max_attempts: parsedInput.maxAttempts,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "dispatch_event_as_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

export async function markEventDispatchFailed(client: BackgroundJobMutationRpcClient, input: MarkEventDispatchFailedInput): Promise<EventLog> {
  const parsedInput = MarkEventDispatchFailedInputSchema.parse(input);
  const { data, error } = await client.rpc("mark_event_dispatch_failed", {
    p_event_id: parsedInput.eventId,
    p_error: parsedInput.error,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BackgroundJobMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BackgroundJobMutationError("invalid_response", "mark_event_dispatch_failed returned no row");
  }
  return parseEventLog(data as Record<string, unknown>);
}
