"use server";

/**
 * Contact Directory Server Actions (COM-145, CG-S7-COM-004). Uses the RLS-scoped
 * `authenticated` client -- app.create_contact is granted directly to `authenticated`
 * and performs its own entitlement check in-body, the same convention COM-143/144's own
 * actions.ts files established.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createContact, ContactMutationError } from "../../../../../server/mutations/contact.ts";

export interface ContactFormState {
  readonly error: string | null;
}

export async function createContactAction(tenantSlug: string, _prevState: ContactFormState, formData: FormData): Promise<ContactFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to create a contact in this organization." };
  }

  const fullName = String(formData.get("fullName") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();

  if (!fullName) {
    return { error: "Full name is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createContact(supabase, {
      tenantId: access.tenant.id,
      fullName,
      title: title || null,
      email: email || null,
      phone: phone || null,
      ownerUserId: access.authUserId,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ContactMutationError) {
      return { error: `Could not create contact: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/contacts`);
  redirect(`/${tenantSlug}/commercial/contacts`);
}
