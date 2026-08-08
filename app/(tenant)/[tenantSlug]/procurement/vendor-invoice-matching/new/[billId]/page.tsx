import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getFinanceVendorBillLines, VendorBillQueryError } from "../../../../../../../server/queries/vendor-bill.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { NewVendorBillMatchForm } from "./new-vendor-bill-match-form.tsx";
import { createVendorBillMatchCaseAction } from "./actions.ts";

/** New match case line-input form (PRC-265, CG-S11-PRC-016). Renders one row per real app.finance_vendor_bill_lines row -- vendor_stated_* is staff-transcribed off the vendor's own paper invoice (see the migration header). */
export default async function NewVendorBillMatchPage({ params }: { params: Promise<{ tenantSlug: string; billId: string }> }) {
  const { tenantSlug, billId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let lines: Awaited<ReturnType<typeof getFinanceVendorBillLines>> = [];
  try {
    lines = await getFinanceVendorBillLines(supabase, { billId, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof VendorBillQueryError)) throw error;
    return <ErrorState description="Could not load that bill's lines. It may not exist, or you may lack FIN:View." />;
  }

  if (lines.length === 0) {
    return <ErrorState description="That bill has no lines to match." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Start match case</h1>
        <p className="text-xs text-neutral-500">Bill {billId}. For each line, enter what the vendor&apos;s own invoice document actually states -- this is captured independently, never copied from the evidence side.</p>
      </div>
      <NewVendorBillMatchForm lines={lines} action={createVendorBillMatchCaseAction.bind(null, tenantSlug, billId, lines.map((l) => l.id))} />
    </div>
  );
}
