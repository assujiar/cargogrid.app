"use server";

/**
 * Approval-definition authoring Server Actions (audit remediation A3b;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A3b:
 * "publishApprovalDefinition has no caller anywhere, so no definition can be
 * created in the product"). Every mutation here (PLT-121's Configuration
 * Engine plus PLT-123's app.publish_approval_definition) already existed,
 * fully implemented and tested, but is `service_role`-only -- this file uses
 * the service-role client, the same "explicit actor, service-role execution"
 * pattern `admin/roles/actions.ts` already established.
 *
 * An approval definition is not its own row type -- it is a PLT-121
 * ConfigVersion/config_items object with config_type_code='approval',
 * scope_level='tenant' (the approval engine migration's own header). One
 * tenant-scoped definition satisfies all 8 of A3b's named dependent
 * functions: `app._resolve_approval_config_type_code` falls back to the
 * plain 'approval' config type whenever a tenant has not published a
 * narrower per-domain override (supabase/migrations/
 * 20260831250000_scope_approval_routing_per_domain.sql) -- so this single
 * generic authoring page, not eight domain-specific ones, is what actually
 * unblocks every one of A3b's flows.
 *
 * The structural item shape (`pattern`, `steps`, `threshold_required_steps`,
 * `allow_self_approval`) is authored as one JSON object rather than a
 * bespoke step-builder UI, mirroring `finance/config/finance-config-forms.tsx`'s
 * own `FinanceConfigItemsForm` precedent exactly -- `app.publish_approval_definition`
 * (via `app.validate_approval_definition`) already performs full structural
 * validation server-side regardless of input source, so a raw JSON editor is
 * genuinely real authoring, not a fake stand-in for one.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createConfigDraft, setConfigItems, rollbackConfigVersion, ConfigMutationError, type ConfigMutationRpcClient } from "../../../../../server/mutations/config.ts";
import { publishApprovalDefinition, ApprovalMutationError, type ApprovalMutationRpcClient } from "../../../../../server/mutations/approval.ts";
import type { ConfigValue } from "../../../../../server/contracts/config/config.ts";

const APPROVAL_CONFIG_TYPE_CODE = "approval";

export interface ApprovalDefinitionActionState {
  readonly error: string | null;
}

const OK: ApprovalDefinitionActionState = { error: null };
const NO_ACCESS: ApprovalDefinitionActionState = { error: "You don't have access to manage approval routing for this organization." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function parseItemsJson(rawJson: string): { items: Record<string, unknown> } | { error: string } {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJson);
  } catch {
    return { error: "itemsJson is not valid JSON." };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { error: "itemsJson must be a single JSON object with pattern/steps keys (see the example above)." };
  }
  return { items: parsed as Record<string, unknown> };
}

/**
 * Idempotent end to end: `createConfigDraft` returns the tenant's already-pending
 * draft instead of creating a second one, so a retry after a validation failure
 * safely overwrites and republishes the same draft rather than accumulating
 * abandoned rows.
 */
export async function publishApprovalDefinitionAction(tenantSlug: string, _prevState: ApprovalDefinitionActionState, formData: FormData): Promise<ApprovalDefinitionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const parsedItems = parseItemsJson(String(formData.get("itemsJson") ?? ""));
  if ("error" in parsedItems) {
    return { error: `Could not publish this approval definition: ${parsedItems.error}` };
  }

  const supabaseClient = createSupabaseServiceRoleClient();
  const configClient: ConfigMutationRpcClient = { rpc: async (fn, args) => await supabaseClient.rpc(fn, args) };
  const approvalClient: ApprovalMutationRpcClient = { rpc: async (fn, args) => await supabaseClient.rpc(fn, args) };

  try {
    const draft = await createConfigDraft(configClient, {
      configTypeCode: APPROVAL_CONFIG_TYPE_CODE,
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    await setConfigItems(configClient, {
      versionId: draft.id,
      items: Object.entries(parsedItems.items).map(([key, value]) => ({ key, value: value as ConfigValue, canonicalRef: null })),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishApprovalDefinition(approvalClient, {
      versionId: draft.id,
      actorAuthUserId: access.authUserId,
      effectiveFrom: null,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ConfigMutationError) return { error: `Could not publish this approval definition: ${error.message}` };
    if (error instanceof ApprovalMutationError) return { error: `Could not publish this approval definition: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/approvals`);
  return OK;
}

export async function rollbackApprovalDefinitionAction(tenantSlug: string, versionId: string, _prevState: ApprovalDefinitionActionState, formData: FormData): Promise<ApprovalDefinitionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to roll back a published approval definition." };

  const supabaseClient = createSupabaseServiceRoleClient();
  const configClient: ConfigMutationRpcClient = { rpc: async (fn, args) => await supabaseClient.rpc(fn, args) };
  try {
    await rollbackConfigVersion(configClient, { targetVersionId: versionId, actorAuthUserId: access.authUserId, reason, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError) return { error: `Could not roll back: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/approvals`);
  return OK;
}
