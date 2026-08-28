/**
 * Automation Rule Engine read queries (IAE-007, Prompt 335). All direct,
 * RLS-scoped reads -- no wrapper RPC needed, mirroring app.tenant_dashboards'
 * own precedent (IAE-003).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseAutomationRule,
  parseAutomationRuleVersion,
  parseAutomationRuleExecution,
  type AutomationRule,
  type AutomationRuleVersion,
  type AutomationRuleExecution,
} from "../contracts/automation-rule/automation-rule.ts";
import { parseApprovalRequest, parseApprovalRequestStep, type ApprovalRequest, type ApprovalRequestStep } from "../contracts/approval/approval.ts";

export type AutomationRuleQueryClient = Pick<SupabaseClient, "from">;

export class AutomationRuleQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AutomationRuleQueryError";
  }
}

/** Every automation rule for one tenant, most recently updated first. */
export async function listAutomationRules(client: AutomationRuleQueryClient, tenantId: string): Promise<AutomationRule[]> {
  const { data, error } = await client.from("automation_rules").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false });
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAutomationRule(row));
}

/** A single rule by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getAutomationRuleById(client: AutomationRuleQueryClient, ruleId: string): Promise<AutomationRule | null> {
  const { data, error } = await client.from("automation_rules").select("*").eq("id", ruleId).maybeSingle();
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseAutomationRule(data as Record<string, unknown>);
}

/** Every version of one rule, newest first -- the currently-open draft is versionNumber === max. */
export async function listAutomationRuleVersions(client: AutomationRuleQueryClient, ruleId: string): Promise<AutomationRuleVersion[]> {
  const { data, error } = await client.from("automation_rule_versions").select("*").eq("automation_rule_id", ruleId).order("version_number", { ascending: false });
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAutomationRuleVersion(row));
}

/** Execution history for one rule, newest first -- completed/suppressed/failed evidence. */
export async function listAutomationRuleExecutions(client: AutomationRuleQueryClient, ruleId: string, limit = 25): Promise<AutomationRuleExecution[]> {
  const { data, error } = await client
    .from("automation_rule_executions")
    .select("*")
    .eq("automation_rule_id", ruleId)
    .order("executed_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAutomationRuleExecution(row));
}

/**
 * The most recent app.approval_requests row opened for one specific
 * automation_rule_version (entity_type='automation_rule_version'), if any --
 * a direct, RLS-scoped read of the shared Approval Engine's own table
 * (PLT-123), never forked. Returns null when this exact draft has never had
 * a publish approval requested.
 *
 * ISS-2026-237: `ended_reason` is deliberately excluded from `authenticated`'s
 * column grant on app.approval_requests (20260731210000, Finding 5 CRITICAL) --
 * it can carry a free-text cancellation/rejection narrative readable by ANY
 * active tenant member with zero permission, and this query runs as the
 * ordinary session-authenticated client. A bare `select("*")` therefore fails
 * outright (`permission denied for table approval_requests`), degrading the
 * entire Automation Rule detail page. The explicit list below mirrors that
 * grant exactly (verified against the currently-applied grant statement
 * before writing this fix); `ended_reason` is synthesized as `null` before
 * parsing rather than selected, since automation-rule-detail-panel.tsx never
 * renders `endedReason` for this caller -- confirmed by direct read, zero
 * occurrences. This keeps the shared `ApprovalRequest` contract/type
 * unchanged (no new narrower type needed) while this specific read path
 * never requests the restricted column, matching the DB's own intent rather
 * than working around it.
 */
export async function getLatestAutomationRulePublishApprovalRequest(client: AutomationRuleQueryClient, automationRuleVersionId: string): Promise<ApprovalRequest | null> {
  const { data, error } = await client
    .from("approval_requests")
    .select(
      "id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key, requested_by_auth_user_id, requested_by, started_at, ended_at, record_version, created_at, updated_at",
    )
    .eq("entity_type", "automation_rule_version")
    .eq("entity_id", automationRuleVersionId)
    .order("started_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseApprovalRequest({ ...(data as Record<string, unknown>), ended_reason: null });
}

/** Every step of one approval request, in step_order -- a direct, RLS-scoped read of the shared Approval Engine's own table (PLT-123). */
export async function listApprovalRequestSteps(client: AutomationRuleQueryClient, requestId: string): Promise<ApprovalRequestStep[]> {
  const { data, error } = await client.from("approval_request_steps").select("*").eq("request_id", requestId).order("step_order", { ascending: true });
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseApprovalRequestStep(row));
}
