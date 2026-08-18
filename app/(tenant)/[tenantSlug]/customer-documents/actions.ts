"use server";

/**
 * Customer Document Center Server Actions (CPL-308, CG-S13-CPL-010). Uses
 * lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard). The only action this capability exposes is a
 * per-document, scoped "download" access attempt -- there is no create/edit
 * action here at all (design decision 1: no new upload path; documents are
 * uploaded at their own source page, e.g. customer-quotes).
 */

import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { getCustomerDocument, CustomerDocumentMutationError } from "../../../../server/mutations/customer-document.ts";

export interface CustomerDocumentActionState {
  readonly error: string | null;
  readonly confirmedAt: string | null;
}

const NO_ACCESS: CustomerDocumentActionState = { error: "You don't have access to this organization's customer portal.", confirmedAt: null };

/**
 * A real Server Action re-invoking app.get_customer_document -- a genuine,
 * freshly-audited access attempt (migration design decision 7), not a
 * decorative control, mirroring accessCustomerEpodAction's own established
 * pattern (CPL-307). Returns no file bytes (no live Supabase Storage
 * integration exists anywhere in this repository, the same disclosed
 * boundary CPL-307 already established) -- on success the caller renders the
 * confirmed-fresh metadata/timestamp inline.
 */
export async function downloadCustomerDocumentAction(tenantSlug: string, documentId: string, _prevState: CustomerDocumentActionState, _formData: FormData): Promise<CustomerDocumentActionState> {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await getCustomerDocument(supabase, access.tenant.id, access.authUserId, documentId);
  } catch (error) {
    if (error instanceof CustomerDocumentMutationError) {
      return { error: error.message, confirmedAt: null };
    }
    throw error;
  }
  return { error: null, confirmedAt: new Date().toISOString() };
}
