/**
 * Analytics and Materialized Views mutation primitives (IAE-005, Prompt
 * 333). Thin, typed wrappers around app.register_analytics_view /
 * app.refresh_analytics_view
 * (supabase/migrations/20260802040000_create_intelligence_analytics_materialized_views.sql).
 * Both are Supreme-only -- a materialized-view refresh is a single,
 * system-wide operation, not a tenant action.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RegisterAnalyticsViewInputSchema,
  RefreshAnalyticsViewInputSchema,
  parseAnalyticsViewRegistry,
  parseAnalyticsRefreshRun,
  type RegisterAnalyticsViewInput,
  type RefreshAnalyticsViewInput,
  type AnalyticsViewRegistry,
  type AnalyticsRefreshRun,
} from "../contracts/analytics/analytics.ts";

export type AnalyticsMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ANALYTICS_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "analytics_view_unknown",
  "analytics_view_retired",
] as const;
type KnownAnalyticsMutationErrorCode = (typeof ANALYTICS_KNOWN_MUTATION_ERROR_CODES)[number];
export type AnalyticsMutationErrorCode = KnownAnalyticsMutationErrorCode | "mutation_failed" | "invalid_response";

export class AnalyticsMutationError extends Error {
  readonly code: AnalyticsMutationErrorCode;

  constructor(code: AnalyticsMutationErrorCode, message: string) {
    super(message);
    this.name = "AnalyticsMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AnalyticsMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ANALYTICS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAnalyticsMutationErrorCode) : "mutation_failed";
}

/** Supreme-only, idempotent by viewCode. Validates viewName against pg_matviews server-side before registering. */
export async function registerAnalyticsView(client: AnalyticsMutationRpcClient, input: RegisterAnalyticsViewInput): Promise<AnalyticsViewRegistry> {
  const parsedInput = RegisterAnalyticsViewInputSchema.parse(input);
  const { data, error } = await client.rpc("register_analytics_view", {
    p_view_code: parsedInput.viewCode,
    p_view_name: parsedInput.viewName,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_source_domain: parsedInput.sourceDomain,
    p_refresh_frequency_minutes: parsedInput.refreshFrequencyMinutes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AnalyticsMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AnalyticsMutationError("invalid_response", "register_analytics_view returned no row");
  }
  return parseAnalyticsViewRegistry(data as Record<string, unknown>);
}

/** Supreme-only. Uses REFRESH MATERIALIZED VIEW CONCURRENTLY -- a failure returns a real status="failed" run, never throws for a data-side failure (only for authority/validation errors, which do throw). */
export async function refreshAnalyticsView(client: AnalyticsMutationRpcClient, input: RefreshAnalyticsViewInput): Promise<AnalyticsRefreshRun> {
  const parsedInput = RefreshAnalyticsViewInputSchema.parse(input);
  const { data, error } = await client.rpc("refresh_analytics_view", {
    p_view_code: parsedInput.viewCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AnalyticsMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AnalyticsMutationError("invalid_response", "refresh_analytics_view returned no row");
  }
  return parseAnalyticsRefreshRun(data as Record<string, unknown>);
}
