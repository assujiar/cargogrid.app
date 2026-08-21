/**
 * Scheduled Reports mutation primitives (IAE-006, Prompt 334). Thin, typed
 * wrappers around app.create_scheduled_report / app.set_scheduled_report_status /
 * app.add_scheduled_report_recipient / app.remove_scheduled_report_recipient /
 * app.run_scheduled_report
 * (supabase/migrations/20260802050000_create_intelligence_scheduled_reports.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateScheduledReportInputSchema,
  SetScheduledReportStatusInputSchema,
  AddScheduledReportRecipientInputSchema,
  RemoveScheduledReportRecipientInputSchema,
  RunScheduledReportInputSchema,
  parseScheduledReport,
  parseScheduledReportRecipient,
  parseScheduledReportRun,
  type CreateScheduledReportInput,
  type SetScheduledReportStatusInput,
  type AddScheduledReportRecipientInput,
  type RemoveScheduledReportRecipientInput,
  type RunScheduledReportInput,
  type ScheduledReport,
  type ScheduledReportRecipient,
  type ScheduledReportRun,
} from "../contracts/scheduled-report/scheduled-report.ts";

export type ScheduledReportMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SCHEDULED_REPORT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "report_type_unknown",
  "report_type_retired",
  "name_required",
  "scheduled_report_invalid_timezone",
  "scheduled_report_invalid_cron",
  "scheduled_report_unsafe_filters",
  "scheduled_report_not_found",
  "scheduled_report_invalid_status",
  "scheduled_report_not_active",
  "scheduled_report_recipient_not_member",
  "scheduled_report_recipient_not_found",
] as const;
type KnownScheduledReportMutationErrorCode = (typeof SCHEDULED_REPORT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ScheduledReportMutationErrorCode = KnownScheduledReportMutationErrorCode | "mutation_failed" | "invalid_response";

export class ScheduledReportMutationError extends Error {
  readonly code: ScheduledReportMutationErrorCode;

  constructor(code: ScheduledReportMutationErrorCode, message: string) {
    super(message);
    this.name = "ScheduledReportMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ScheduledReportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SCHEDULED_REPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownScheduledReportMutationErrorCode)
    : "mutation_failed";
}

/** REP:Configure-gated. Validates timezone/cron shape/filters server-side; computes a real next_run_at. */
export async function createScheduledReport(client: ScheduledReportMutationRpcClient, input: CreateScheduledReportInput): Promise<ScheduledReport> {
  const parsedInput = CreateScheduledReportInputSchema.parse(input);
  const { data, error } = await client.rpc("create_scheduled_report", {
    p_tenant_id: parsedInput.tenantId,
    p_report_type_code: parsedInput.reportTypeCode,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_cron_minute: parsedInput.cronMinute,
    p_cron_hour: parsedInput.cronHour,
    p_cron_day_of_month: parsedInput.cronDayOfMonth,
    p_cron_day_of_week: parsedInput.cronDayOfWeek,
    p_timezone: parsedInput.timezone,
    p_filters: parsedInput.filters,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScheduledReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScheduledReportMutationError("invalid_response", "create_scheduled_report returned no row");
  }
  return parseScheduledReport(data as Record<string, unknown>);
}

/** REP:Configure-gated. Pause/resume/archive -- Prompt 334's own "unsubscribe/suspend controls". */
export async function setScheduledReportStatus(client: ScheduledReportMutationRpcClient, input: SetScheduledReportStatusInput): Promise<ScheduledReport> {
  const parsedInput = SetScheduledReportStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_scheduled_report_status", {
    p_scheduled_report_id: parsedInput.scheduledReportId,
    p_status: parsedInput.status,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScheduledReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScheduledReportMutationError("invalid_response", "set_scheduled_report_status returned no row");
  }
  return parseScheduledReport(data as Record<string, unknown>);
}

/** REP:Configure-gated. Rejects a recipient with no active tenant membership at add time -- re-validated again at every run. */
export async function addScheduledReportRecipient(client: ScheduledReportMutationRpcClient, input: AddScheduledReportRecipientInput): Promise<ScheduledReportRecipient> {
  const parsedInput = AddScheduledReportRecipientInputSchema.parse(input);
  const { data, error } = await client.rpc("add_scheduled_report_recipient", {
    p_scheduled_report_id: parsedInput.scheduledReportId,
    p_recipient_auth_user_id: parsedInput.recipientAuthUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScheduledReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScheduledReportMutationError("invalid_response", "add_scheduled_report_recipient returned no row");
  }
  return parseScheduledReportRecipient(data as Record<string, unknown>);
}

/** REP:Configure-gated. */
export async function removeScheduledReportRecipient(client: ScheduledReportMutationRpcClient, input: RemoveScheduledReportRecipientInput): Promise<void> {
  const parsedInput = RemoveScheduledReportRecipientInputSchema.parse(input);
  const { error } = await client.rpc("remove_scheduled_report_recipient", {
    p_recipient_row_id: parsedInput.recipientRowId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScheduledReportMutationError(classifyError(error.message), error.message);
  }
}

/** REP:Configure-gated. Reauthorizes every recipient live, enqueues via the shared app.jobs queue with an occurrence-scoped idempotency key (never a duplicate for the same due occurrence), and advances next_run_at forward. */
export async function runScheduledReport(client: ScheduledReportMutationRpcClient, input: RunScheduledReportInput): Promise<ScheduledReportRun> {
  const parsedInput = RunScheduledReportInputSchema.parse(input);
  const { data, error } = await client.rpc("run_scheduled_report", {
    p_scheduled_report_id: parsedInput.scheduledReportId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScheduledReportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScheduledReportMutationError("invalid_response", "run_scheduled_report returned no row");
  }
  return parseScheduledReportRun(data as Record<string, unknown>);
}
