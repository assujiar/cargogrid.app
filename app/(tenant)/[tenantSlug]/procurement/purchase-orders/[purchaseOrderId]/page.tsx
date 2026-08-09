import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getPurchaseOrder, listPurchaseOrderLines, getPurchaseOrderHistory, PurchaseOrderQueryError } from "../../../../../../server/queries/purchase-order.ts";
import { evaluateProcurementApprovalRequirement, ProcurementApprovalQueryError } from "../../../../../../server/queries/procurement-approval.ts";
import type { ProcurementApprovalRequirement } from "../../../../../../server/contracts/procurement-approval/procurement-approval.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PurchaseOrderDetailPanel } from "./purchase-order-detail-panel.tsx";
import {
  submitPurchaseOrderForApprovalAction,
  issuePurchaseOrderAction,
  acknowledgePurchaseOrderAction,
  recordPurchaseOrderFulfillmentStatusAction,
  amendPurchaseOrderAction,
  cancelPurchaseOrderAction,
} from "../actions.ts";

/**
 * Purchase Order detail (PRC-260, CG-S11-PRC-011): inherited source lines, exact
 * totals, terms/documents, approval/version timeline, vendor acknowledgement, amendment
 * chain, and fulfillment/match status. Every mutating action below binds the CURRENT
 * record_version at render time (mirrors app/(tenant)/[tenantSlug]/procurement/vendor-
 * comparison/[comparisonId]/page.tsx's own `.bind()`-per-row convention) -- a concurrent
 * edit between render and submit surfaces as a real stale_version error from the RPC
 * itself, not a silently-accepted overwrite.
 */
export default async function PurchaseOrderDetailPage({ params }: { params: Promise<{ tenantSlug: string; purchaseOrderId: string }> }) {
  const { tenantSlug, purchaseOrderId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let purchaseOrder: Awaited<ReturnType<typeof getPurchaseOrder>> | null = null;
  let lines: Awaited<ReturnType<typeof listPurchaseOrderLines>> = [];
  let history: Awaited<ReturnType<typeof getPurchaseOrderHistory>> = [];
  let approvalPreview: ProcurementApprovalRequirement | null = null;
  try {
    purchaseOrder = await getPurchaseOrder(supabase, purchaseOrderId, access.authUserId);
    lines = await listPurchaseOrderLines(supabase, purchaseOrderId, access.authUserId);
    history = await getPurchaseOrderHistory(supabase, purchaseOrderId, access.authUserId);
    // C-20 discipline (mirrors the vendor-comparison detail page's own already-fixed
    // precedent): app.evaluate_procurement_approval_requirement needs a real UI caller
    // for entity_type=purchase_order, not just a policy/context dimension nobody reads.
    // Best-effort preview only, shown before submit -- the real routing decision happens
    // server-side inside app.submit_purchase_order_for_approval itself regardless.
    if (purchaseOrder.status === "draft" && purchaseOrder.totalAmount !== null) {
      try {
        approvalPreview = await evaluateProcurementApprovalRequirement(supabase, {
          entityType: "purchase_order",
          tenantId: purchaseOrder.tenantId,
          valueAmount: purchaseOrder.totalAmount,
          actorAuthUserId: access.authUserId,
          // Full-regression review (Prompt 269 follow-up): threads the PO's own
          // currency through so a genuine cross-currency preview normalizes via FX
          // (ISS-2026-045, Fix 3) instead of comparing raw numerics -- matches
          // exactly what app.submit_purchase_order_for_approval itself passes.
          valueCurrency: purchaseOrder.currency,
        });
      } catch (previewError) {
        if (!(previewError instanceof ProcurementApprovalQueryError)) throw previewError;
      }
    }
  } catch (error) {
    if (!(error instanceof PurchaseOrderQueryError)) throw error;
    if (error.message.includes("purchase_order_not_found")) {
      notFoundOrDenied = true;
    } else if (error.message.includes("insufficient_authority")) {
      notFoundOrDenied = false;
      loadFailed = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundOrDenied) {
    notFound();
  }
  if (loadFailed || !purchaseOrder || !purchaseOrder.id) {
    return <ErrorState description="Something went wrong loading this purchase order. Please try again." />;
  }

  return (
    <PurchaseOrderDetailPanel
      purchaseOrder={purchaseOrder}
      lines={lines}
      history={history}
      approvalPreview={approvalPreview}
      submitAction={submitPurchaseOrderForApprovalAction.bind(null, tenantSlug, purchaseOrderId, purchaseOrder.recordVersion)}
      issueAction={issuePurchaseOrderAction.bind(null, tenantSlug, purchaseOrderId, purchaseOrder.recordVersion)}
      acknowledgeAction={acknowledgePurchaseOrderAction.bind(null, tenantSlug, purchaseOrderId, purchaseOrder.recordVersion)}
      recordFulfillmentAction={recordPurchaseOrderFulfillmentStatusAction.bind(null, tenantSlug, purchaseOrderId, purchaseOrder.recordVersion)}
      amendAction={amendPurchaseOrderAction.bind(null, tenantSlug, purchaseOrderId, purchaseOrder.recordVersion)}
      cancelAction={cancelPurchaseOrderAction.bind(null, tenantSlug, purchaseOrderId, purchaseOrder.recordVersion)}
    />
  );
}
