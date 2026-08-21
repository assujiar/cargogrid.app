/**
 * Dashboard Builder mutation primitives (IAE-003, Prompt 331). Thin, typed
 * wrappers around app.create_tenant_dashboard_draft / app.add_dashboard_widget /
 * app.remove_dashboard_widget / app.publish_tenant_dashboard_version /
 * app.rollback_tenant_dashboard
 * (supabase/migrations/20260802020000_create_intelligence_dashboard_builder.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateTenantDashboardDraftInputSchema,
  AddDashboardWidgetInputSchema,
  RemoveDashboardWidgetInputSchema,
  PublishTenantDashboardVersionInputSchema,
  RollbackTenantDashboardInputSchema,
  parseTenantDashboard,
  parseTenantDashboardVersion,
  parseTenantDashboardWidget,
  type CreateTenantDashboardDraftInput,
  type AddDashboardWidgetInput,
  type RemoveDashboardWidgetInput,
  type PublishTenantDashboardVersionInput,
  type RollbackTenantDashboardInput,
  type TenantDashboard,
  type TenantDashboardVersion,
  type TenantDashboardWidget,
} from "../contracts/tenant-dashboard/tenant-dashboard.ts";

export type TenantDashboardMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const TENANT_DASHBOARD_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "dashboard_name_required",
  "dashboard_not_found",
  "dashboard_version_not_found",
  "dashboard_version_not_editable",
  "dashboard_no_draft_version",
  "dashboard_empty_version",
  "dashboard_widget_not_found",
  "dashboard_target_version_invalid",
  "report_type_unknown",
  "report_type_retired",
  "widget_unsafe_parameters",
  "widget_title_required",
] as const;
type KnownTenantDashboardMutationErrorCode = (typeof TENANT_DASHBOARD_KNOWN_MUTATION_ERROR_CODES)[number];
export type TenantDashboardMutationErrorCode = KnownTenantDashboardMutationErrorCode | "mutation_failed" | "invalid_response";

export class TenantDashboardMutationError extends Error {
  readonly code: TenantDashboardMutationErrorCode;

  constructor(code: TenantDashboardMutationErrorCode, message: string) {
    super(message);
    this.name = "TenantDashboardMutationError";
    this.code = code;
  }
}

function classifyError(message: string): TenantDashboardMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (TENANT_DASHBOARD_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownTenantDashboardMutationErrorCode)
    : "mutation_failed";
}

/** REP:Configure-gated. Creates the dashboard row plus its own version-1 draft in one transaction. */
export async function createTenantDashboardDraft(client: TenantDashboardMutationRpcClient, input: CreateTenantDashboardDraftInput): Promise<TenantDashboard> {
  const parsedInput = CreateTenantDashboardDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_tenant_dashboard_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TenantDashboardMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TenantDashboardMutationError("invalid_response", "create_tenant_dashboard_draft returned no row");
  }
  return parseTenantDashboard(data as Record<string, unknown>);
}

/** REP:Configure-gated, draft-only. Rejects an unknown/retired report_type_code and validates parameterOverrides against that report's own current parameter_schema. */
export async function addDashboardWidget(client: TenantDashboardMutationRpcClient, input: AddDashboardWidgetInput): Promise<TenantDashboardWidget> {
  const parsedInput = AddDashboardWidgetInputSchema.parse(input);
  const { data, error } = await client.rpc("add_dashboard_widget", {
    p_dashboard_version_id: parsedInput.dashboardVersionId,
    p_report_type_code: parsedInput.reportTypeCode,
    p_title: parsedInput.title,
    p_position: parsedInput.position,
    p_parameter_overrides: parsedInput.parameterOverrides,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TenantDashboardMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TenantDashboardMutationError("invalid_response", "add_dashboard_widget returned no row");
  }
  return parseTenantDashboardWidget(data as Record<string, unknown>);
}

/** REP:Configure-gated, draft-only, mirrors addDashboardWidget's own gate exactly. */
export async function removeDashboardWidget(client: TenantDashboardMutationRpcClient, input: RemoveDashboardWidgetInput): Promise<void> {
  const parsedInput = RemoveDashboardWidgetInputSchema.parse(input);
  const { error } = await client.rpc("remove_dashboard_widget", {
    p_widget_id: parsedInput.widgetId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TenantDashboardMutationError(classifyError(error.message), error.message);
  }
}

/** REP:Configure-gated. Publishes the current draft (rejecting an empty one), points current_version_id at it, then opens a fresh draft copying the just-published widgets. */
export async function publishTenantDashboardVersion(
  client: TenantDashboardMutationRpcClient,
  input: PublishTenantDashboardVersionInput,
): Promise<TenantDashboardVersion> {
  const parsedInput = PublishTenantDashboardVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_tenant_dashboard_version", {
    p_dashboard_id: parsedInput.dashboardId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TenantDashboardMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TenantDashboardMutationError("invalid_response", "publish_tenant_dashboard_version returned no row");
  }
  return parseTenantDashboardVersion(data as Record<string, unknown>);
}

/** REP:Configure-gated. Points current_version_id at an older PUBLISHED version only -- never a draft. */
export async function rollbackTenantDashboard(client: TenantDashboardMutationRpcClient, input: RollbackTenantDashboardInput): Promise<TenantDashboard> {
  const parsedInput = RollbackTenantDashboardInputSchema.parse(input);
  const { data, error } = await client.rpc("rollback_tenant_dashboard", {
    p_dashboard_id: parsedInput.dashboardId,
    p_target_version_id: parsedInput.targetVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TenantDashboardMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TenantDashboardMutationError("invalid_response", "rollback_tenant_dashboard returned no row");
  }
  return parseTenantDashboard(data as Record<string, unknown>);
}
