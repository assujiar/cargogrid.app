import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listContacts, ContactQueryError, type ListContactsResult } from "../../../../../server/queries/contact.ts";
import type { Contact } from "../../../../../server/contracts/contact/contact.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { createContactAction } from "./actions.ts";
import { CreateContactForm } from "./create-contact-form.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

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

  const columns: readonly DataTableColumn<Contact>[] = [
    {
      key: "name",
      header: "Name",
      render: (contact) => (
        <a href={`/${tenantSlug}/commercial/contacts/${contact.id}`} className="font-medium text-primary underline">
          {contact.fullName}
        </a>
      ),
    },
    { key: "title", header: "Title", render: (contact) => contact.title ?? "—" },
    { key: "email", header: "Email", render: (contact) => contact.email ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Contacts</h1>

      <CreateContactForm action={boundCreateContactAction} />

      {loadFailed || !result ? (
        <ErrorState description="Something went wrong loading contacts. Please try again." />
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Contacts"
            columns={columns}
            rows={result.contacts}
            rowKey={(contact) => contact.id}
            emptyMessage="No contacts found for this organization yet."
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} total contact{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/commercial/contacts?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
