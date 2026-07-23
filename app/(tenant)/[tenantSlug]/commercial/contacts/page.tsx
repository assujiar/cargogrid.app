import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listContacts, ContactQueryError, type ListContactsResult } from "../../../../../server/queries/contact.ts";
import { createContactAction } from "./actions.ts";
import { CreateContactForm } from "./create-contact-form.tsx";

/**
 * Contact directory (COM-145, CG-S7-COM-004) -- mirrors the Lead List page's own
 * "read-only table plus one bounded create form" shape (COM-143).
 */
export default async function CommercialContactsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListContactsResult | null = null;
  let loadFailed = false;
  try {
    result = await listContacts(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof ContactQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const boundCreateContactAction = createContactAction.bind(null, tenantSlug);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Contacts</h1>

      <CreateContactForm action={boundCreateContactAction} />

      {loadFailed || !result ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading contacts. Please try again.</p>
        </div>
      ) : result.contacts.length === 0 ? (
        <p className="text-sm text-neutral-600">No contacts found for this organization yet.</p>
      ) : (
        <div className="flex flex-col gap-4">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Name
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Title
                </th>
                <th scope="col" className="py-2 font-medium">
                  Email
                </th>
              </tr>
            </thead>
            <tbody>
              {result.contacts.map((contact) => (
                <tr key={contact.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">
                    <a href={`/${tenantSlug}/commercial/contacts/${contact.id}`} className="font-medium text-primary underline">
                      {contact.fullName}
                    </a>
                  </td>
                  <td className="py-2 pr-4 text-neutral-600">{contact.title ?? "—"}</td>
                  <td className="py-2 text-neutral-600">{contact.email ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="text-xs text-neutral-500">
            Page {result.page} — {result.totalCount} total contact{result.totalCount === 1 ? "" : "s"}
          </p>
        </div>
      )}
    </div>
  );
}
