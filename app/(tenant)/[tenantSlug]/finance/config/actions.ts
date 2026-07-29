"use server";

/**
 * Finance Configuration Server Actions (FIN-191, CG-S9-FIN-002). Uses the
 * RLS-scoped `authenticated` client -- app.create_finance_config_draft/
 * app.set_finance_config_items/app.publish_finance_config_version/
 * app.discard_finance_config_draft/app.rollback_finance_config_version are all
 * granted directly to `authenticated` and perform their own FIN:Edit/FIN:Approve
 * plus tenant_admin/Supreme authority check in-body, the same convention every
 * prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  createFinanceConfigDraft,
  setFinanceConfigItems,
  publishFinanceConfigVersion,
  discardFinanceConfigDraft,
  rollbackFinanceConfigVersion,
  FinanceConfigMutationError,
} from "../../../../../server/mutations/finance-config.ts";
import { FinanceConfigClassSchema, type FinanceConfigClass } from "../../../../../server/contracts/finance-config/finance-config.ts";

export interface FinanceConfigFormState {
  readonly error: string | null;
}

export async function createFinanceConfigDraftAction(
  tenantSlug: string,
  configClass: FinanceConfigClass,
  _prevState: FinanceConfigFormState,
  _formData: FormData,
): Promise<FinanceConfigFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const parsedClass = FinanceConfigClassSchema.safeParse(configClass);
  if (!parsedClass.success) {
    return { error: "Unknown Finance Configuration class." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createFinanceConfigDraft(supabase, {
      configTypeCode: parsedClass.data,
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof FinanceConfigMutationError) {
      return { error: `Could not create a draft: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/config`);
  return { error: null };
}

export async function setFinanceConfigItemsAction(
  tenantSlug: string,
  versionId: string,
  _prevState: FinanceConfigFormState,
  formData: FormData,
): Promise<FinanceConfigFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const rawItemsJson = String(formData.get("itemsJson") ?? "");
  let itemsMap: Record<string, unknown>;
  try {
    itemsMap = JSON.parse(rawItemsJson);
    if (typeof itemsMap !== "object" || itemsMap === null || Array.isArray(itemsMap)) {
      throw new Error("not an object");
    }
  } catch {
    return { error: "Items must be valid JSON: an object mapping each item key to its value object." };
  }

  const items = Object.entries(itemsMap).map(([key, value]) => ({ key, value: value as Record<string, unknown> }));

  const supabase = await createSupabaseServerClient();
  try {
    await setFinanceConfigItems(supabase, { versionId, items, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FinanceConfigMutationError) {
      return { error: `Could not save items: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/config`);
  return { error: null };
}

export async function publishFinanceConfigVersionAction(
  tenantSlug: string,
  versionId: string,
  _prevState: FinanceConfigFormState,
  _formData: FormData,
): Promise<FinanceConfigFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishFinanceConfigVersion(supabase, { versionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FinanceConfigMutationError) {
      return { error: `Could not publish: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/config`);
  return { error: null };
}

export async function discardFinanceConfigDraftAction(
  tenantSlug: string,
  versionId: string,
  _prevState: FinanceConfigFormState,
  formData: FormData,
): Promise<FinanceConfigFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) {
    return { error: "A reason is required to discard a draft." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceConfigDraft(supabase, { versionId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FinanceConfigMutationError) {
      return { error: `Could not discard: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/config`);
  return { error: null };
}

export async function rollbackFinanceConfigVersionAction(
  tenantSlug: string,
  targetVersionId: string,
  _prevState: FinanceConfigFormState,
  formData: FormData,
): Promise<FinanceConfigFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) {
    return { error: "A reason is required to roll back to a prior version." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await rollbackFinanceConfigVersion(supabase, { targetVersionId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FinanceConfigMutationError) {
      return { error: `Could not roll back: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/config`);
  return { error: null };
}
