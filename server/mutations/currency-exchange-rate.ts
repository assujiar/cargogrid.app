/**
 * Currency and Exchange Rate mutation primitives (FIN-194, CG-S9-FIN-005).
 * Thin, typed wrappers around app.create_finance_exchange_rate_draft /
 * app.discard_finance_exchange_rate_draft / app.approve_finance_exchange_rate /
 * app.stage_finance_exchange_rate_import
 * (supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateFinanceExchangeRateDraftInputSchema,
  DiscardFinanceExchangeRateDraftInputSchema,
  ApproveFinanceExchangeRateInputSchema,
  parseFinanceExchangeRate,
  type CreateFinanceExchangeRateDraftInput,
  type DiscardFinanceExchangeRateDraftInput,
  type ApproveFinanceExchangeRateInput,
  type FinanceExchangeRate,
} from "../contracts/currency-exchange-rate/currency-exchange-rate.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type CurrencyExchangeRateMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CURRENCY_EXCHANGE_RATE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_exchange_rate_unsupported_currency",
  "finance_exchange_rate_invalid_rate",
  "finance_exchange_rate_not_found",
  "finance_exchange_rate_not_draft",
  "finance_exchange_rate_overlap",
  "finance_exchange_rate_missing",
  "stale_version",
] as const;
type KnownCurrencyExchangeRateMutationErrorCode = (typeof CURRENCY_EXCHANGE_RATE_KNOWN_MUTATION_ERROR_CODES)[number];
export type CurrencyExchangeRateMutationErrorCode = KnownCurrencyExchangeRateMutationErrorCode | "mutation_failed" | "invalid_response";

export class CurrencyExchangeRateMutationError extends Error {
  readonly code: CurrencyExchangeRateMutationErrorCode;

  constructor(code: CurrencyExchangeRateMutationErrorCode, message: string) {
    super(message);
    this.name = "CurrencyExchangeRateMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CurrencyExchangeRateMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CURRENCY_EXCHANGE_RATE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCurrencyExchangeRateMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRate(
  client: CurrencyExchangeRateMutationRpcClient,
  fn: "create_finance_exchange_rate_draft" | "discard_finance_exchange_rate_draft" | "approve_finance_exchange_rate",
  args: Record<string, unknown>,
): Promise<FinanceExchangeRate> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CurrencyExchangeRateMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CurrencyExchangeRateMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceExchangeRate(data as Record<string, unknown>);
}

/** FIN:Edit-gated. Rejects an unsupported/inactive currency or a non-positive rate. */
export async function createFinanceExchangeRateDraft(
  client: CurrencyExchangeRateMutationRpcClient,
  input: CreateFinanceExchangeRateDraftInput,
): Promise<FinanceExchangeRate> {
  const parsedInput = CreateFinanceExchangeRateDraftInputSchema.parse(input);
  return callAndParseRate(client, "create_finance_exchange_rate_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_rate_type: parsedInput.rateType,
    p_source_currency: parsedInput.sourceCurrency,
    p_target_currency: parsedInput.targetCurrency,
    p_rate: parsedInput.rate,
    p_source: parsedInput.source,
    p_effective_from: parsedInput.effectiveFrom,
    p_effective_to: parsedInput.effectiveTo,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** FIN:Edit-gated. draft -> archived. Rejected once the rate is approved. */
export async function discardFinanceExchangeRateDraft(
  client: CurrencyExchangeRateMutationRpcClient,
  input: DiscardFinanceExchangeRateDraftInput,
): Promise<FinanceExchangeRate> {
  const parsedInput = DiscardFinanceExchangeRateDraftInputSchema.parse(input);
  return callAndParseRate(client, "discard_finance_exchange_rate_draft", {
    p_rate_id: parsedInput.rateId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. draft -> approved. Rejected if it overlaps an already-approved window for the same scope/type/pair. */
export async function approveFinanceExchangeRate(
  client: CurrencyExchangeRateMutationRpcClient,
  input: ApproveFinanceExchangeRateInput,
): Promise<FinanceExchangeRate> {
  const parsedInput = ApproveFinanceExchangeRateInputSchema.parse(input);
  return callAndParseRate(client, "approve_finance_exchange_rate", {
    p_rate_id: parsedInput.rateId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

export interface StageFinanceExchangeRateImportRow {
  rateType?: string;
  sourceCurrency: string;
  targetCurrency: string;
  rate: number;
  source?: string;
  effectiveFrom: string;
  effectiveTo?: string | null;
}

export interface StageFinanceExchangeRateImportResult {
  id: string;
  tenantId: string | null;
  idempotencyKey: string;
  rowCount: number;
  createdBy: string | null;
  createdAt: string;
}

function parseStageFinanceExchangeRateImportResult(row: Record<string, unknown>): StageFinanceExchangeRateImportResult {
  return {
    id: row.id as string,
    tenantId: (row.tenant_id as string | null) ?? null,
    idempotencyKey: row.idempotency_key as string,
    rowCount: row.row_count as number,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at as string,
  };
}

/**
 * FIN:Edit-gated staged idempotent import (Prompt 194's own "imports use
 * staged idempotent jobs"). A retried call with the same idempotencyKey
 * returns the original batch rather than re-staging its rows.
 */
export async function stageFinanceExchangeRateImport(
  client: CurrencyExchangeRateMutationRpcClient,
  input: { tenantId: string | null; idempotencyKey: string; rows: StageFinanceExchangeRateImportRow[]; actorAuthUserId: string; actorLabel: string },
): Promise<StageFinanceExchangeRateImportResult> {
  const { data, error } = await client.rpc("stage_finance_exchange_rate_import", {
    p_tenant_id: input.tenantId,
    p_idempotency_key: input.idempotencyKey,
    p_rows: input.rows.map((row) => ({
      rate_type: row.rateType ?? "spot",
      source_currency: row.sourceCurrency,
      target_currency: row.targetCurrency,
      rate: row.rate,
      source: row.source ?? "import",
      effective_from: row.effectiveFrom,
      effective_to: row.effectiveTo ?? null,
    })),
    p_actor_auth_user_id: input.actorAuthUserId,
    p_actor_label: input.actorLabel,
  });
  if (error) {
    throw new CurrencyExchangeRateMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CurrencyExchangeRateMutationError("invalid_response", "stage_finance_exchange_rate_import returned no row");
  }
  return parseStageFinanceExchangeRateImportResult(data as Record<string, unknown>);
}
