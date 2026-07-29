/**
 * Fiscal Period mutation primitives (FIN-193, CG-S9-FIN-004). Thin, typed
 * wrappers around app.generate_finance_fiscal_calendar /
 * app.acknowledge_finance_period_checklist_item / app.soft_close_finance_period /
 * app.close_finance_period / app.reopen_finance_period
 * (supabase/migrations/20260728220000_create_finance_fiscal_period.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  GenerateFinanceFiscalCalendarInputSchema,
  AcknowledgeFinancePeriodChecklistItemInputSchema,
  SoftCloseFinancePeriodInputSchema,
  CloseFinancePeriodInputSchema,
  ReopenFinancePeriodInputSchema,
  parseFinanceFiscalCalendar,
  parseFinanceFiscalPeriod,
  parseFinancePeriodChecklistItem,
  type GenerateFinanceFiscalCalendarInput,
  type AcknowledgeFinancePeriodChecklistItemInput,
  type SoftCloseFinancePeriodInput,
  type CloseFinancePeriodInput,
  type ReopenFinancePeriodInput,
  type FinanceFiscalCalendar,
  type FinanceFiscalPeriod,
  type FinancePeriodChecklistItem,
} from "../contracts/fiscal-period/fiscal-period.ts";

export type FiscalPeriodMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const FISCAL_PERIOD_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_calendar_invalid_period_count",
  "finance_calendar_duplicate_code",
  "finance_period_overlap",
  "finance_period_not_found",
  "finance_period_closed",
  "finance_period_checklist_item_not_found",
  "finance_period_not_open",
  "finance_period_not_soft_closed",
  "finance_period_not_closed",
  "finance_period_checklist_incomplete",
  "finance_period_reopen_reason_required",
  "stale_version",
] as const;
type KnownFiscalPeriodMutationErrorCode = (typeof FISCAL_PERIOD_KNOWN_MUTATION_ERROR_CODES)[number];
export type FiscalPeriodMutationErrorCode = KnownFiscalPeriodMutationErrorCode | "mutation_failed" | "invalid_response";

export class FiscalPeriodMutationError extends Error {
  readonly code: FiscalPeriodMutationErrorCode;

  constructor(code: FiscalPeriodMutationErrorCode, message: string) {
    super(message);
    this.name = "FiscalPeriodMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FiscalPeriodMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FISCAL_PERIOD_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownFiscalPeriodMutationErrorCode)
    : "mutation_failed";
}

/** FIN:Edit-gated. Creates a calendar plus N sequential, non-overlapping periods, each pinning the tenant's currently-effective finance_close_policy items as its own checklist snapshot. */
export async function generateFinanceFiscalCalendar(client: FiscalPeriodMutationRpcClient, input: GenerateFinanceFiscalCalendarInput): Promise<FinanceFiscalCalendar> {
  const parsedInput = GenerateFinanceFiscalCalendarInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_finance_fiscal_calendar", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_start_date: parsedInput.startDate,
    p_period_count: parsedInput.periodCount,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
  if (error) {
    throw new FiscalPeriodMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FiscalPeriodMutationError("invalid_response", "generate_finance_fiscal_calendar returned no row");
  }
  return parseFinanceFiscalCalendar(data as Record<string, unknown>);
}

/** FIN:Edit-gated. Rejected once the period is closed. */
export async function acknowledgeFinancePeriodChecklistItem(client: FiscalPeriodMutationRpcClient, input: AcknowledgeFinancePeriodChecklistItemInput): Promise<FinancePeriodChecklistItem> {
  const parsedInput = AcknowledgeFinancePeriodChecklistItemInputSchema.parse(input);
  const { data, error } = await client.rpc("acknowledge_finance_period_checklist_item", {
    p_period_id: parsedInput.periodId,
    p_item_key: parsedInput.itemKey,
    p_satisfied: parsedInput.satisfied,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FiscalPeriodMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FiscalPeriodMutationError("invalid_response", "acknowledge_finance_period_checklist_item returned no row");
  }
  return parseFinancePeriodChecklistItem(data as Record<string, unknown>);
}

async function callAndParsePeriod(
  client: FiscalPeriodMutationRpcClient,
  fn: "soft_close_finance_period" | "close_finance_period" | "reopen_finance_period",
  args: Record<string, unknown>,
): Promise<FinanceFiscalPeriod> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new FiscalPeriodMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FiscalPeriodMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceFiscalPeriod(data as Record<string, unknown>);
}

/** FIN:Edit-gated. open -> soft_closed. */
export async function softCloseFinancePeriod(client: FiscalPeriodMutationRpcClient, input: SoftCloseFinancePeriodInput): Promise<FinanceFiscalPeriod> {
  const parsedInput = SoftCloseFinancePeriodInputSchema.parse(input);
  return callAndParsePeriod(client, "soft_close_finance_period", {
    p_period_id: parsedInput.periodId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. soft_closed -> closed. Requires every required checklist item satisfied. */
export async function closeFinancePeriod(client: FiscalPeriodMutationRpcClient, input: CloseFinancePeriodInput): Promise<FinanceFiscalPeriod> {
  const parsedInput = CloseFinancePeriodInputSchema.parse(input);
  return callAndParsePeriod(client, "close_finance_period", {
    p_period_id: parsedInput.periodId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated, mandatory reason. closed -> open (governed reopen). */
export async function reopenFinancePeriod(client: FiscalPeriodMutationRpcClient, input: ReopenFinancePeriodInput): Promise<FinanceFiscalPeriod> {
  const parsedInput = ReopenFinancePeriodInputSchema.parse(input);
  return callAndParsePeriod(client, "reopen_finance_period", {
    p_period_id: parsedInput.periodId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
