import { notFound } from "next/navigation";
import { randomUUID } from "node:crypto";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getJobOrder, JobOrderQueryError } from "../../../../../../server/queries/job-order.ts";
import { getJobShipmentAllocationBalance, listShipmentOrdersForJobOrder, ShipmentOrderQueryError } from "../../../../../../server/queries/shipment-order.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { CreateShipmentOrderForm } from "./create-shipment-order-form.tsx";
import { createShipmentOrderFromJobAction } from "./actions.ts";

/**
 * Shipment Order creation from a confirmed Job Order (OPS-169, Prompt 169 §21's own
 * main flow). Shows the governed allocation balance (basis/allocated/remaining, per
 * dimension) before the one atomic create action -- the same "readiness before
 * action" shape the Job Order conversion review page (OPS-168) already established.
 */
export default async function CreateShipmentOrderPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ jobOrderId?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { jobOrderId } = await searchParams;
  if (!jobOrderId) {
    return <ErrorState title="No Job Order selected" description="Open this page from a confirmed Job Order's own detail page." />;
  }

  const supabase = await createSupabaseServerClient();

  let jobOrder;
  try {
    jobOrder = await getJobOrder(supabase, jobOrderId);
  } catch (error) {
    if (!(error instanceof JobOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading this Job Order. Please try again." />;
  }

  if (!jobOrder || jobOrder.tenantId !== access.tenant.id) {
    notFound();
  }

  if (jobOrder.status !== "confirmed") {
    return <ErrorState title="Job Order not confirmed" description={`Job Order ${jobOrder.jobNumber} is ${jobOrder.status} -- only a confirmed Job Order is eligible for Shipment Order creation.`} />;
  }

  let balance;
  let existingShipments;
  try {
    [balance, existingShipments] = await Promise.all([
      getJobShipmentAllocationBalance(supabase, { jobOrderId: jobOrder.id, actorAuthUserId: access.authUserId }),
      listShipmentOrdersForJobOrder(supabase, jobOrder.id),
    ]);
  } catch (error) {
    if (!(error instanceof ShipmentOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the allocation balance. Please try again." />;
  }
  const isFirstShipment = existingShipments.length === 0;
  const idempotencyKey = randomUUID();

  const boundAction = createShipmentOrderFromJobAction.bind(null, tenantSlug, jobOrder.id, idempotencyKey);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Create Shipment Order from {jobOrder.jobNumber}</h1>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Allocation balance</h2>
        {balance.basisQuantity === null && balance.basisWeightKg === null && balance.basisVolumeCbm === null ? (
          <p className="text-sm text-neutral-500">No allocation basis has been declared yet -- this will be the first Shipment Order for this Job Order.</p>
        ) : (
          <dl className="grid grid-cols-3 gap-x-4 gap-y-1 text-sm">
            <dt className="text-neutral-600">Quantity remaining</dt>
            <dd className="text-neutral-900">{balance.remainingQuantity ?? "—"}</dd>
            <dt className="text-neutral-600">Weight remaining (kg)</dt>
            <dd className="text-neutral-900">{balance.remainingWeightKg ?? "—"}</dd>
            <dt className="text-neutral-600">Volume remaining (cbm)</dt>
            <dd className="text-neutral-900">{balance.remainingVolumeCbm ?? "—"}</dd>
          </dl>
        )}
      </section>

      <CreateShipmentOrderForm action={boundAction} isFirstShipment={isFirstShipment} />
    </div>
  );
}
