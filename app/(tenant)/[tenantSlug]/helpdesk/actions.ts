"use server";

/**
 * Tenant-to-CargoGrid helpdesk Server Actions (HRT-288, CG-S12-HRT-016).
 * Reuses `lib/portal/ticket-guard.ts`'s existing `org_user`/`tenant_admin`
 * portal-entry guard (the same audience the internal ticket workspace
 * already uses, sibling of `tickets/`) -- this route group is a UX boundary
 * only; the REAL authority check is `app._is_tenant_helpdesk_authorized`
 * (tenant_admin OR a real, tenant-scoped TKT:Edit role), enforced server-side
 * on every RPC call, never trusted from this layer alone.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveTicketAccessForRequest } from "../../../../lib/portal/resolve-ticket-access.server.ts";
import {
  createHelpdeskTicket,
  replyToHelpdeskTicket,
  transitionTicketStatus,
  TicketMutationError,
} from "../../../../server/mutations/ticketing.ts";
import type { HelpdeskEnvironment, HelpdeskSeverity, TicketPriority, TicketStatus } from "../../../../server/contracts/ticketing/ticketing.ts";

export interface HelpdeskActionState {
  readonly error: string | null;
}

const OK: HelpdeskActionState = { error: null };
const NO_ACCESS: HelpdeskActionState = { error: "You don't have access to this organization's helpdesk workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/helpdesk`;
}

function detailPath(tenantSlug: string, ticketId: string): string {
  return `/${tenantSlug}/helpdesk/${ticketId}`;
}

function errorMessage(prefix: string, error: unknown): HelpdeskActionState {
  if (error instanceof TicketMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

function nullableField(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length > 0 ? raw : null;
}

export async function createHelpdeskTicketAction(tenantSlug: string, _prevState: HelpdeskActionState, formData: FormData): Promise<HelpdeskActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const categoryId = String(formData.get("categoryId") ?? "").trim();
  const priority = String(formData.get("priority") ?? "normal") as TicketPriority;
  const severity = nullableField(formData, "severity") as HelpdeskSeverity | null;
  const environment = nullableField(formData, "environment") as HelpdeskEnvironment | null;
  const productArea = nullableField(formData, "productArea");
  const externalReference = nullableField(formData, "externalReference");
  const subject = String(formData.get("subject") ?? "").trim();
  const body = String(formData.get("body") ?? "").trim();
  if (!categoryId || !subject || !body) return { error: "Category, subject, and description are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createHelpdeskTicket(supabase, {
      tenantId: access.tenant.id,
      categoryId,
      priority,
      severity,
      productArea,
      environment,
      externalReference,
      subject,
      body,
      idempotencyKey: `create-helpdesk-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not open this support case", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function replyToHelpdeskTicketAction(tenantSlug: string, ticketId: string, _prevState: HelpdeskActionState, formData: FormData): Promise<HelpdeskActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const body = String(formData.get("body") ?? "").trim();
  if (!body) return { error: "A non-empty message is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await replyToHelpdeskTicket(supabase, {
      ticketId,
      body,
      attachmentFileIds: null,
      idempotencyKey: `reply-helpdesk-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not post this message", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function transitionHelpdeskTicketStatusAction(
  tenantSlug: string,
  ticketId: string,
  expectedVersion: number,
  toStatus: TicketStatus,
  _prevState: HelpdeskActionState,
  formData: FormData,
): Promise<HelpdeskActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await transitionTicketStatus(supabase, { ticketId, expectedVersion, toStatus, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update this support case's status", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}
