import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getContactById, ContactQueryError } from "../../../../../../server/queries/contact.ts";

/**
 * Contact Detail (COM-145, CG-S7-COM-004). Read-only in this bounded first slice --
 * `app.link_contact_to_record`/`app.unlink_contact_from_record` are real, tested
 * mutation-layer capabilities without a dedicated UI button here, the same "core
 * management, not an all-actions mega task" scoping COM-143's own Lead Detail page used
 * for assign/merge.
 */
export default async function ContactDetailPage({ params }: { params: Promise<{ tenantSlug: string; contactId: string }> }) {
  const { tenantSlug, contactId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let contact;
  try {
    contact = await getContactById(supabase, contactId);
  } catch (error) {
    if (!(error instanceof ContactQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this contact. Please try again.</p>
      </div>
    );
  }

  if (!contact || contact.tenantId !== access.tenant.id) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{contact.fullName}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Title</dt>
        <dd className="text-neutral-900">{contact.title ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Email</dt>
        <dd className="text-neutral-900">{contact.email ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Phone</dt>
        <dd className="text-neutral-900">{contact.phone ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{contact.status}</dd>
      </dl>
    </div>
  );
}
