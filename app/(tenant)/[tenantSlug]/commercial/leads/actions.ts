"use server";

/**
 * Lead Management Server Actions (COM-143, CG-S7-COM-002). Uses the RLS-scoped
 * `authenticated` client (never service-role) -- app.capture_lead/app.qualify_lead/
 * app.disqualify_lead are all granted directly to `authenticated` and perform their own
 * entitlement (app.evaluate_permission) and record-scope (app.can_access_record) checks
 * in-body, the deliberate design choice this capability's migration documents (unlike
 * the master-data engine's service-role-only convention).
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { captureLead, qualifyLead, disqualifyLead, LeadMutationError } from "../../../../../server/mutations/lead.ts";
import { convertLeadToProspect, ProspectMutationError } from "../../../../../server/mutations/prospect.ts";

export interface LeadFormState {
  readonly error: string | null;
}

export async function captureLeadAction(tenantSlug: string, _prevState: LeadFormState, formData: FormData): Promise<LeadFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to capture a lead in this organization." };
  }

  const contactName = String(formData.get("contactName") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const companyName = String(formData.get("companyName") ?? "").trim();

  if (!contactName) {
    return { error: "Contact name is required." };
  }
  if (!email && !phone) {
    return { error: "At least one of email or phone is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await captureLead(supabase, {
      tenantId: access.tenant.id,
      source: "manual",
      contactName,
      email: email || null,
      phone: phone || null,
      companyName: companyName || null,
      ownerUserId: access.authUserId,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LeadMutationError) {
      return { error: `Could not capture lead: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/leads`);
  redirect(`/${tenantSlug}/commercial/leads`);
}

export async function qualifyLeadAction(tenantSlug: string, leadId: string, expectedVersion: number): Promise<LeadFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await qualifyLead(supabase, { leadId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeadMutationError) {
      return { error: `Could not qualify lead: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/leads/${leadId}`);
  return { error: null };
}

/** Main flow (COM-144, Prompt 144 §21): a qualified lead converts to a prospect. Redirects to the new prospect's detail page on success -- idempotent, so a retried click after a slow response never creates a second prospect. */
export async function convertLeadToProspectAction(
  tenantSlug: string,
  leadId: string,
  legalName: string,
): Promise<LeadFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }
  if (!legalName.trim()) {
    return { error: "A legal name is required to convert this lead to a prospect." };
  }

  const supabase = await createSupabaseServerClient();
  let prospectId: string;
  try {
    const prospect = await convertLeadToProspect(supabase, { leadId, legalName, actorAuthUserId: access.authUserId, createdBy: access.authUserId });
    prospectId = prospect.id;
  } catch (error) {
    if (error instanceof ProspectMutationError) {
      return { error: `Could not convert lead to prospect: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/leads/${leadId}`);
  revalidatePath(`/${tenantSlug}/commercial/prospects`);
  redirect(`/${tenantSlug}/commercial/prospects/${prospectId}`);
}

export async function disqualifyLeadAction(tenantSlug: string, leadId: string, expectedVersion: number, reason: string): Promise<LeadFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }
  if (!reason.trim()) {
    return { error: "A disqualification reason is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await disqualifyLead(supabase, { leadId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeadMutationError) {
      return { error: `Could not disqualify lead: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/leads/${leadId}`);
  return { error: null };
}
