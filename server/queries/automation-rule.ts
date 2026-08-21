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
 */
export async function getLatestAutomationRulePublishApprovalRequest(client: AutomationRuleQueryClient, automationRuleVersionId: string): Promise<ApprovalRequest | null> {
  const { data, error } = await client
    .from("approval_requests")
    .select("*")
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
  return parseApprovalRequest(data as Record<string, unknown>);
}

/** Every step of one approval request, in step_order -- a direct, RLS-scoped read of the shared Approval Engine's own table (PLT-123). */
export async function listApprovalRequestSteps(client: AutomationRuleQueryClient, requestId: string): Promise<ApprovalRequestStep[]> {
  const { data, error } = await client.from("approval_request_steps").select("*").eq("request_id", requestId).order("step_order", { ascending: true });
  if (error) {
    throw new AutomationRuleQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseApprovalRequestStep(row));
}
