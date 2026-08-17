"use server";

/**
 * Customer ticket Server Actions (HRT-287, CG-S12-HRT-015). Mirrors
 * app/(tenant)/[tenantSlug]/tickets/actions.ts's own shape, but calls only
 * the customer-facing mutation wrappers -- createCustomerTicket,
 * replyToCustomerTicket, and the SAME generic transitionTicketStatus the
 * internal surface uses (close/reopen-as-configured reaches the customer
 * channel through the identical RPC, decision 9 of the HRT-287 migration).
 * Every write is permission/scope-gated at the RPC layer itself
 * (app.resolve_customer_owner_account_scope) -- this file never re-derives
 * or trusts a client-supplied account/site id, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerTicketAccessForRequest } from "../../../../lib/portal/resolve-customer-ticket-access.server.ts";
import {
  createCustomerTicket,
  replyToCustomerTicket,
  transitionTicketStatus,
  linkTicketRecord,
  unlinkTicketRecord,
  recordTicketLinkAccessDenial,
  linkTicketPortalRecord,
  unlinkTicketPortalRecord,
  TicketMutationError,
} from "../../../../server/mutations/ticketing.ts";
import { searchTicketLinkCandidates, searchCustomerTicketLinkCandidatesPrecreate, searchTicketPortalLinkCandidates, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES, TICKET_LINK_RELATIONSHIPS, TICKET_PORTAL_LINK_ENTITY_TYPES, TICKET_PRECREATE_LINK_ENTITY_TYPES } from "../../../../server/contracts/ticketing/ticketing.ts";
import type {
  TicketPriority,
  TicketStatus,
  TicketLinkEntityType,
  TicketLinkRelationship,
  TicketLinkCandidateRow,
  TicketPortalLinkEntityType,
  TicketPortalLinkCandidateRow,
  TicketPrecreateLinkEntityType,
} from "../../../../server/contracts/ticketing/ticketing.ts";

export interface CustomerTicketActionState {
  readonly error: string | null;
}

const OK: CustomerTicketActionState = { error: null };
const NO_ACCESS: CustomerTicketActionState = { error: "You don't have access to this organization's customer support workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/customer-tickets`;
}

function detailPath(tenantSlug: string, ticketId: string): string {
  return `/${tenantSlug}/customer-tickets/${ticketId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerTicketActionState {
  if (error instanceof TicketMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

export async function createCustomerTicketAction(tenantSlug: string, _prevState: CustomerTicketActionState, formData: FormData): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const accountId = String(formData.get("accountId") ?? "").trim();
  const categoryId = String(formData.get("categoryId") ?? "").trim();
  const priority = String(formData.get("priority") ?? "normal") as TicketPriority;
  const subject = String(formData.get("subject") ?? "").trim();
  const body = String(formData.get("body") ?? "").trim();
  // CPL-311 (Invoice and Billing Visibility): an optional dispute deep link
  // from the customer invoice detail page -- see ./page.tsx's own header
  // comment. Never trusted as authorization on its own; linkTicketRecord
  // below re-proves this actor's own independent eligibility for this
  // exact invoice id, the identical anti-enumerating gate the existing
  // search-and-link flow already uses.
  const disputeInvoiceId = String(formData.get("disputeInvoiceId") ?? "").trim() || null;
  // CPL-313 (Complaint and Ticket): the generic linked-record picker on the
  // create form (see customer-tickets-panel.tsx's own LinkRecordPicker) --
  // independent of, and never overridden by, the disputeInvoiceId deep-link
  // mechanism above. Never trusted as authorization on its own -- both
  // linkTicketRecord/linkTicketPortalRecord below re-prove this actor's own
  // independent eligibility for the exact candidate selected, the identical
  // anti-enumerating gate the dispute flow and the detail-page picker both
  // already use.
  const rawLinkEntityType = String(formData.get("linkEntityType") ?? "").trim();
  const linkEntityId = String(formData.get("linkEntityId") ?? "").trim() || null;
  const linkRelationship = (String(formData.get("linkRelationship") ?? "related").trim() || "related") as TicketLinkRelationship;
  const isTicketLinkType = (TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES as readonly string[]).includes(rawLinkEntityType);
  const isPortalLinkType = (TICKET_PORTAL_LINK_ENTITY_TYPES as readonly string[]).includes(rawLinkEntityType);
  if (!accountId || !categoryId || !subject || !body) return { error: "Account, category, subject, and description are all required." };
  if (rawLinkEntityType && !isTicketLinkType && !isPortalLinkType) return { error: "Select a valid record type to link." };

  const supabase = await createSupabaseServerClient();
  let createdTicketId: string;
  try {
    const created = (await createCustomerTicket(supabase, {
      tenantId: access.tenant.id,
      accountId,
      categoryId,
      priority,
      subject,
      body,
      idempotencyKey: `create-customer-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    })) as { id: string };
    createdTicketId = created.id;
  } catch (error) {
    return errorMessage("Could not create this ticket", error);
  }

  if (disputeInvoiceId) {
    try {
      await linkTicketRecord(supabase, {
        ticketId: createdTicketId,
        entityType: "invoice",
        entityId: disputeInvoiceId,
        relationship: "primary_subject",
        actorAuthUserId: access.authUserId,
        actorLabel: access.authUserId,
      });
    } catch (error) {
      // Best-effort: the ticket itself was already created successfully. A
      // failed auto-link (e.g. the invoice has since left this customer's
      // own finance scope) must not block or hide the ticket they just
      // raised -- they can still link it manually from the ticket detail
      // page's own search-and-link UI. Mirrors linkCustomerTicketRecordAction's
      // own best-effort denial-audit convention below.
      if (error instanceof TicketMutationError && (error.code === "record_not_eligible" || error.code === "entity_type_not_permitted")) {
        void recordTicketLinkAccessDenial(supabase, {
          tenantId: access.tenant.id,
          ticketId: createdTicketId,
          actorAuthUserId: access.authUserId,
          actorLabel: access.authUserId,
          entityType: "invoice",
          entityId: disputeInvoiceId,
          reason: error.code,
        }).catch(() => {});
      }
    }
    revalidatePath(listPath(tenantSlug));
    redirect(detailPath(tenantSlug, createdTicketId));
  } else if (linkEntityId && (isTicketLinkType || isPortalLinkType)) {
    try {
      if (isTicketLinkType) {
        await linkTicketRecord(supabase, {
          ticketId: createdTicketId,
          entityType: rawLinkEntityType as TicketLinkEntityType,
          entityId: linkEntityId,
          relationship: linkRelationship,
          actorAuthUserId: access.authUserId,
          actorLabel: access.authUserId,
        });
      } else {
        await linkTicketPortalRecord(supabase, {
          ticketId: createdTicketId,
          entityType: rawLinkEntityType as TicketPortalLinkEntityType,
          entityId: linkEntityId,
          relationship: linkRelationship,
          actorAuthUserId: access.authUserId,
          actorLabel: access.authUserId,
        });
      }
    } catch (error) {
      // Best-effort, mirrors the disputeInvoiceId branch above exactly: the
      // ticket itself was already created successfully. A failed link (the
      // candidate left this customer's own scope between search and
      // submit) must not block or hide the ticket they just raised.
      if (isTicketLinkType && error instanceof TicketMutationError && (error.code === "record_not_eligible" || error.code === "entity_type_not_permitted")) {
        void recordTicketLinkAccessDenial(supabase, {
          tenantId: access.tenant.id,
          ticketId: createdTicketId,
          actorAuthUserId: access.authUserId,
          actorLabel: access.authUserId,
          entityType: rawLinkEntityType as TicketLinkEntityType,
          entityId: linkEntityId,
          reason: error.code,
        }).catch(() => {});
      }
      // No denial-audit follow-up exists for the portal-link surface -- see
      // the migration's own design decision 6 (no ticket_id exists yet at
      // search time to scope a durable ledger row to; the failed link
      // ATTEMPT itself is simply not persisted, matching every other
      // best-effort auto-link path in this file).
    }
    revalidatePath(listPath(tenantSlug));
    redirect(detailPath(tenantSlug, createdTicketId));
  }

  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function replyToCustomerTicketAction(tenantSlug: string, ticketId: string, _prevState: CustomerTicketActionState, formData: FormData): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const body = String(formData.get("body") ?? "").trim();
  if (!body) return { error: "A non-empty message is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await replyToCustomerTicket(supabase, {
      ticketId,
      body,
      attachmentFileIds: null,
      idempotencyKey: `reply-customer-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not post this message", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function transitionCustomerTicketStatusAction(
  tenantSlug: string,
  ticketId: string,
  expectedVersion: number,
  toStatus: TicketStatus,
  _prevState: CustomerTicketActionState,
  formData: FormData,
): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await transitionTicketStatus(supabase, { ticketId, expectedVersion, toStatus, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update this ticket's status", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- Typed Ticket-Linked Records (HRT-292, CG-S12-HRT-020). Same shared
// RPCs the internal staff surface uses (server/{queries,mutations}/
// ticketing.ts) -- the customer-safe entity-type narrowing and the
// account-owner-scope narrowing are BOTH enforced server-side, at the RPC
// layer, regardless of what this file offers; this file only forwards. ---

export interface CustomerTicketLinkSearchActionState {
  readonly error: string | null;
  readonly entityType: TicketLinkEntityType | null;
  readonly relationship: TicketLinkRelationship;
  readonly results: readonly TicketLinkCandidateRow[];
}

export async function searchCustomerTicketLinkCandidatesAction(
  tenantSlug: string,
  ticketId: string,
  _prevState: CustomerTicketLinkSearchActionState,
  formData: FormData,
): Promise<CustomerTicketLinkSearchActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, entityType: null, relationship: "related", results: [] };

  const entityType = String(formData.get("entityType") ?? "") as TicketLinkEntityType;
  const relationship = (String(formData.get("relationship") ?? "related") || "related") as TicketLinkRelationship;
  const searchText = String(formData.get("searchText") ?? "").trim() || null;
  if (!(TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES as readonly string[]).includes(entityType)) {
    return { error: "Select a record type to search.", entityType: null, relationship, results: [] };
  }
  if (!(TICKET_LINK_RELATIONSHIPS as readonly string[]).includes(relationship)) {
    return { error: "Select a valid relationship.", entityType, relationship: "related", results: [] };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const results = await searchTicketLinkCandidates(supabase, ticketId, entityType, searchText, access.authUserId, 20);
    return { error: null, entityType, relationship, results };
  } catch (error) {
    if (error instanceof TicketQueryError) return { error: `Could not search: ${error.message}`, entityType, relationship, results: [] };
    throw error;
  }
}

export async function linkCustomerTicketRecordAction(
  tenantSlug: string,
  ticketId: string,
  entityType: TicketLinkEntityType,
  entityId: string,
  relationship: TicketLinkRelationship,
  _prevState: CustomerTicketActionState,
  _formData: FormData,
): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await linkTicketRecord(supabase, { ticketId, entityType, entityId, relationship, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TicketMutationError) {
      if (error.code === "record_not_eligible" || error.code === "entity_type_not_permitted") {
        void recordTicketLinkAccessDenial(supabase, {
          tenantId: access.tenant.id, ticketId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
          entityType, entityId, reason: error.code,
        }).catch(() => {});
      }
      return { error: `Could not link this record: ${error.message}` };
    }
    throw error;
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function unlinkCustomerTicketRecordAction(
  tenantSlug: string,
  ticketId: string,
  linkId: string,
  expectedVersion: number,
  _prevState: CustomerTicketActionState,
  formData: FormData,
): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to unlink a record." };

  const supabase = await createSupabaseServerClient();
  try {
    await unlinkTicketRecord(supabase, { linkId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not unlink this record", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- CPL-313 (CG-S13-CPL-015): the SEPARATE, parallel warehouse_order/
// document portal-link surface (app.ticket_portal_links) -- see
// server/contracts/ticketing/ticketing.ts's own header comment for why this
// is not folded into the HRT-292 actions above. Same forward-only shape:
// every scope/authority/anti-enumeration decision is enforced server-side,
// at the RPC layer, regardless of what this file offers. ---

export interface CustomerTicketPortalLinkSearchActionState {
  readonly error: string | null;
  readonly entityType: TicketPortalLinkEntityType | null;
  readonly relationship: TicketLinkRelationship;
  readonly results: readonly TicketPortalLinkCandidateRow[];
}

const EMPTY_PORTAL_SEARCH_STATE: CustomerTicketPortalLinkSearchActionState = { error: null, entityType: null, relationship: "related", results: [] };

// The ticket DETAIL page's own search (post-creation, ticket-scoped) -- a
// customer_portal_links-only counterpart to searchCustomerTicketLinkCandidatesAction.
export async function searchCustomerTicketPortalLinkCandidatesAction(
  tenantSlug: string,
  ticketId: string,
  _prevState: CustomerTicketPortalLinkSearchActionState,
  formData: FormData,
): Promise<CustomerTicketPortalLinkSearchActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { ...EMPTY_PORTAL_SEARCH_STATE, error: NO_ACCESS.error };

  const entityType = String(formData.get("entityType") ?? "") as TicketPortalLinkEntityType;
  const relationship = (String(formData.get("relationship") ?? "related") || "related") as TicketLinkRelationship;
  const searchText = String(formData.get("searchText") ?? "").trim() || null;
  if (!(TICKET_PORTAL_LINK_ENTITY_TYPES as readonly string[]).includes(entityType)) {
    return { error: "Select a record type to search.", entityType: null, relationship, results: [] };
  }
  if (!(TICKET_LINK_RELATIONSHIPS as readonly string[]).includes(relationship)) {
    return { error: "Select a valid relationship.", entityType, relationship: "related", results: [] };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const results = await searchTicketPortalLinkCandidates(supabase, ticketId, entityType, searchText, access.authUserId, 20);
    return { error: null, entityType, relationship, results };
  } catch (error) {
    if (error instanceof TicketQueryError) return { error: `Could not search: ${error.message}`, entityType, relationship, results: [] };
    throw error;
  }
}

// Exactly the four types the ticket CREATE form's own picker offers --
// deliberately spans both the existing HRT-292 registry (shipment/invoice)
// and this checkpoint's own new app.ticket_portal_links registry
// (warehouse_order/document), mirroring app.search_customer_ticket_link_
// candidates_precreate's own identical span (see that function's own
// comment). Not the full TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES set --
// 'warehouse'(facility)/'customer'(own account) stay reachable only from the
// ticket DETAIL page's own existing picker (post-creation), unchanged.
// TICKET_PRECREATE_LINK_ENTITY_TYPES itself lives in server/contracts/
// ticketing/ticketing.ts, not here -- see that file's own comment for why
// (a "use server" file may only export async functions).

export interface CustomerTicketPrecreateLinkSearchActionState {
  readonly error: string | null;
  readonly entityType: TicketPrecreateLinkEntityType | null;
  readonly relationship: TicketLinkRelationship;
  readonly results: readonly TicketPortalLinkCandidateRow[];
}

const EMPTY_PRECREATE_SEARCH_STATE: CustomerTicketPrecreateLinkSearchActionState = { error: null, entityType: null, relationship: "related", results: [] };

// The ticket CREATE form's own picker search -- no ticket exists yet, so
// this calls app.search_customer_ticket_link_candidates_precreate, never
// the ticket-scoped RPCs above (which both require a real, already-created
// ticket to check app.can_access_ticket against).
export async function searchCustomerTicketPortalLinkCandidatesPrecreateAction(
  tenantSlug: string,
  _prevState: CustomerTicketPrecreateLinkSearchActionState,
  formData: FormData,
): Promise<CustomerTicketPrecreateLinkSearchActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { ...EMPTY_PRECREATE_SEARCH_STATE, error: NO_ACCESS.error };

  const entityType = String(formData.get("entityType") ?? "") as TicketPrecreateLinkEntityType;
  const relationship = (String(formData.get("relationship") ?? "related") || "related") as TicketLinkRelationship;
  const searchText = String(formData.get("searchText") ?? "").trim() || null;
  if (!(TICKET_PRECREATE_LINK_ENTITY_TYPES as readonly string[]).includes(entityType)) {
    return { error: "Select a record type to search.", entityType: null, relationship, results: [] };
  }
  if (!(TICKET_LINK_RELATIONSHIPS as readonly string[]).includes(relationship)) {
    return { error: "Select a valid relationship.", entityType, relationship: "related", results: [] };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const results = await searchCustomerTicketLinkCandidatesPrecreate(supabase, access.tenant.id, entityType, searchText, access.authUserId, 20);
    return { error: null, entityType, relationship, results };
  } catch (error) {
    if (error instanceof TicketQueryError) return { error: `Could not search: ${error.message}`, entityType, relationship, results: [] };
    throw error;
  }
}

export async function linkCustomerTicketPortalRecordAction(
  tenantSlug: string,
  ticketId: string,
  entityType: TicketPortalLinkEntityType,
  entityId: string,
  relationship: TicketLinkRelationship,
  _prevState: CustomerTicketActionState,
  _formData: FormData,
): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await linkTicketPortalRecord(supabase, { ticketId, entityType, entityId, relationship, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TicketMutationError) return { error: `Could not link this record: ${error.message}` };
    throw error;
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function unlinkCustomerTicketPortalRecordAction(
  tenantSlug: string,
  ticketId: string,
  linkId: string,
  expectedVersion: number,
  _prevState: CustomerTicketActionState,
  formData: FormData,
): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to unlink a record." };

  const supabase = await createSupabaseServerClient();
  try {
    await unlinkTicketPortalRecord(supabase, { linkId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not unlink this record", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}
