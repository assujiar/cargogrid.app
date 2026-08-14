"use server";

/**
 * CargoGrid Platform support (Supreme Admin) helpdesk Server Actions
 * (HRT-288, CG-S12-HRT-016). Gated by `resolveSupremeAdminAccessForRequest`
 * (the SAME Supreme Admin portal-entry guard `supreme/tenants` already
 * uses) -- the real, enforcing authority for every RPC below is
 * `app.is_supreme_admin`, checked server-side, never trusted from this
 * layer alone. `linkHelpdeskSupportGrantAction` is display/audit
 * CORRELATION ONLY (`app.link_helpdesk_support_grant`) -- it never creates,
 * approves, starts, extends, or revokes a PLT-115 support access grant or
 * session; that remains the separate, unmodified
 * `app.request_support_access`/`app.approve_support_access`/`app.
 * start_support_session` flow, out of this route's own scope.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import {
  replyToTicket,
  transitionTicketStatus,
  assignHelpdeskTicket,
  transferHelpdeskSupportQueue,
  updateHelpdeskTicketClassification,
  linkHelpdeskSupportGrant,
  createSupportQueue,
  TicketMutationError,
} from "../../../../server/mutations/ticketing.ts";
import type { HelpdeskEnvironment, HelpdeskSeverity, MessageVisibility, TicketPriority, TicketStatus } from "../../../../server/contracts/ticketing/ticketing.ts";

export interface SupremeHelpdeskActionState {
  readonly error: string | null;
}

const OK: SupremeHelpdeskActionState = { error: null };
const NO_ACCESS: SupremeHelpdeskActionState = { error: "You don't have Platform support authority for this action." };

async function requireAccess() {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(ticketId: string): string {
  return `/supreme/helpdesk/${ticketId}`;
}

function errorMessage(prefix: string, error: unknown): SupremeHelpdeskActionState {
  if (error instanceof TicketMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

function nullableField(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length > 0 ? raw : null;
}

export async function replyToHelpdeskTicketAsStaffAction(ticketId: string, _prevState: SupremeHelpdeskActionState, formData: FormData): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const body = String(formData.get("body") ?? "").trim();
  const visibility = (String(formData.get("visibility") ?? "public") as MessageVisibility) ?? "public";
  if (!body) return { error: "A non-empty message is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await replyToTicket(supabase, {
      ticketId,
      body,
      visibility,
      attachmentFileIds: null,
      idempotencyKey: `reply-staff-helpdesk-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not post this message", error);
  }
  revalidatePath(detailPath(ticketId));
  return OK;
}

export async function transitionHelpdeskTicketStatusAsStaffAction(
  ticketId: string,
  expectedVersion: number,
  toStatus: TicketStatus,
  _prevState: SupremeHelpdeskActionState,
  formData: FormData,
): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await transitionTicketStatus(supabase, { ticketId, expectedVersion, toStatus, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update this case's status", error);
  }
  revalidatePath(detailPath(ticketId));
  return OK;
}

export async function assignHelpdeskTicketAction(ticketId: string, expectedVersion: number, _prevState: SupremeHelpdeskActionState, formData: FormData): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const assigneeAuthUserId = nullableField(formData, "assigneeAuthUserId");

  const supabase = await createSupabaseServerClient();
  try {
    await assignHelpdeskTicket(supabase, { ticketId, expectedVersion, assigneeAuthUserId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not assign this case", error);
  }
  revalidatePath(detailPath(ticketId));
  return OK;
}

export async function transferHelpdeskSupportQueueAction(ticketId: string, expectedVersion: number, _prevState: SupremeHelpdeskActionState, formData: FormData): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const newSupportQueueId = String(formData.get("supportQueueId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!newSupportQueueId || !reason) return { error: "A target support queue and a reason are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await transferHelpdeskSupportQueue(supabase, { ticketId, expectedVersion, newSupportQueueId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not transfer this case", error);
  }
  revalidatePath(detailPath(ticketId));
  return OK;
}

export async function updateHelpdeskTicketClassificationAction(ticketId: string, expectedVersion: number, _prevState: SupremeHelpdeskActionState, formData: FormData): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const categoryId = String(formData.get("categoryId") ?? "").trim();
  const priority = String(formData.get("priority") ?? "normal") as TicketPriority;
  const severity = nullableField(formData, "severity") as HelpdeskSeverity | null;
  const productArea = nullableField(formData, "productArea");
  const environment = nullableField(formData, "environment") as HelpdeskEnvironment | null;
  if (!categoryId) return { error: "A category is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await updateHelpdeskTicketClassification(supabase, {
      ticketId,
      expectedVersion,
      categoryId,
      priority,
      severity,
      productArea,
      environment,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not reclassify this case", error);
  }
  revalidatePath(detailPath(ticketId));
  return OK;
}

export async function linkHelpdeskSupportGrantAction(ticketId: string, expectedVersion: number, _prevState: SupremeHelpdeskActionState, formData: FormData): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const caseRef = nullableField(formData, "caseRef");

  const supabase = await createSupabaseServerClient();
  try {
    await linkHelpdeskSupportGrant(supabase, { ticketId, expectedVersion, caseRef, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update the support-access correlation", error);
  }
  revalidatePath(detailPath(ticketId));
  return OK;
}

export async function createSupportQueueAction(_prevState: SupremeHelpdeskActionState, formData: FormData): Promise<SupremeHelpdeskActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = nullableField(formData, "description");
  if (!code || !name) return { error: "A code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createSupportQueue(supabase, { code, name, description, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this support queue", error);
  }
  revalidatePath("/supreme/helpdesk");
  return OK;
}
