"use server";

/** Vendor Invoice Matching new-case server action (PRC-265, CG-S11-PRC-016). */

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createVendorBillMatchCase, VendorInvoiceMatchingMutationError } from "../../../../../../../server/mutations/vendor-invoice-matching.ts";

export interface NewVendorBillMatchActionState {
  readonly error: string | null;
}

const NO_ACCESS: NewVendorBillMatchActionState = { error: "You don't have access to this organization's Procurement workspace." };

export async function createVendorBillMatchCaseAction(tenantSlug: string, billId: string, lineIds: readonly string[], _prevState: NewVendorBillMatchActionState, formData: FormData): Promise<NewVendorBillMatchActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const purchaseOrderIdRaw = String(formData.get("purchaseOrderId") ?? "").trim();
  const isPartialInvoice = formData.get("isPartialInvoice") === "on";
  const isConsolidatedInvoice = formData.get("isConsolidatedInvoice") === "on";

  const lineInputs = lineIds.map((lineId) => {
    const amountRaw = String(formData.get(`amount_${lineId}`) ?? "").trim();
    const quantityRaw = String(formData.get(`quantity_${lineId}`) ?? "").trim();
    const rateRaw = String(formData.get(`rate_${lineId}`) ?? "").trim();
    const uomRaw = String(formData.get(`uom_${lineId}`) ?? "").trim();
    return {
      billLineId: lineId,
      vendorStatedAmount: Number(amountRaw),
      vendorStatedQuantity: quantityRaw.length > 0 ? Number(quantityRaw) : null,
      vendorStatedRate: rateRaw.length > 0 ? Number(rateRaw) : null,
      vendorStatedUom: uomRaw.length > 0 ? uomRaw : null,
    };
  });

  const missing = lineInputs.find((l) => Number.isNaN(l.vendorStatedAmount));
  if (missing) {
    return { error: "Every line requires a valid vendor-stated amount (what the vendor's own invoice states for that line)." };
  }

  const supabase = await createSupabaseServerClient();
  let matchCaseId: string;
  try {
    const matchCase = await createVendorBillMatchCase(supabase, {
      tenantId: access.tenant.id,
      billId,
      purchaseOrderId: purchaseOrderIdRaw.length > 0 ? purchaseOrderIdRaw : null,
      isPartialInvoice,
      isConsolidatedInvoice,
      lineInputs,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    matchCaseId = matchCase.id;
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not create the match case: ${error.message}` };
    throw error;
  }

  redirect(`/${tenantSlug}/procurement/vendor-invoice-matching/${matchCaseId}`);
}
