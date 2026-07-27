import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listCreditProfileApprovalInboxForActor, getCreditProfileById, CreditQueryError } from "../../../../../server/queries/credit.ts";
import { getAccountById } from "../../../../../server/queries/account.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";

/**
 * Credit profile approval inbox (COM-157, CG-S7-COM-016, Prompt 157 §16/§26). Mirrors the
 * Quotation Approval inbox (COM-153, commercial/approvals/) exactly, filtered to
 * entity_type=credit_profile requests instead -- a routing list, not a second decision
 * surface. Deciding happens on the Account Detail page's own CreditPanel, where the
 * reauth-freshness gate this capability's own privileged-approver actions require lives.
 */
export default async function CreditApprovalsInboxPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let items: Awaited<ReturnType<typeof listCreditProfileApprovalInboxForActor>>;
  let loadFailed = false;
  try {
    items = await listCreditProfileApprovalInboxForActor(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof CreditQueryError)) {
      throw error;
    }
    loadFailed = true;
    items = [];
  }

  const profiles = await Promise.all(items.map((item) => getCreditProfileById(supabase, item.creditProfileId)));
  const accounts = await Promise.all(profiles.map((profile) => (profile ? getAccountById(supabase, profile.accountId) : null)));
  const rows = items.map((item, index) => ({ item, account: accounts[index] }));

  const columns: readonly DataTableColumn<(typeof rows)[number]>[] = [
    { key: "account", header: "Account", render: (row) => row.account?.legalName ?? row.item.creditProfileId },
    { key: "step", header: "Step", render: (row) => `Step ${row.item.stepOrder}` },
    {
      key: "action",
      header: "Action",
      render: (row) =>
        row.account ? (
          <a href={`/${tenantSlug}/commercial/accounts/${row.account.id}`} className="text-sm font-medium text-primary underline">
            Review
          </a>
        ) : (
          "—"
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Credit Approvals</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading your credit approval inbox. Please try again.</p>
        </div>
      ) : (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Waiting on your decision</h2>
          <div className="mt-2">
            <DataTable
              caption="Credit approvals waiting on your decision"
              columns={columns}
              rows={rows}
              rowKey={(row) => row.item.stepId}
              emptyMessage="Nothing is waiting on you right now."
            />
          </div>
        </div>
      )}
    </div>
  );
}
