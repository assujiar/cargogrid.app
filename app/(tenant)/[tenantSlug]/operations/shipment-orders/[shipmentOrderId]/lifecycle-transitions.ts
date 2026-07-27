import type { ShipmentOrderStatus } from "../../../../../../server/contracts/shipment-order/shipment-order.ts";
import type { TransitionableStatus } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";

/**
 * UI-affordance-only restatement of app.transition_shipment_order's own canonical
 * matrix (supabase/migrations/20260727110000_create_operations_shipment_lifecycle.sql)
 * -- never authoritative. The database re-validates every edge itself regardless of
 * what this module offers; a stale or bypassed client can never reach an illegal
 * transition, it would simply be rejected server-side.
 *
 * assigned -> dispatched is deliberately omitted from the forward edge here (OPS-175):
 * that edge now has its own dedicated, readiness-gated command
 * (app.dispatch_shipment_order, surfaced by this page's own DispatchPanel), the same
 * "a dedicated command supersedes the generic transition matrix in this UI" precedent
 * draft -> confirmed already set with ConfirmShipmentOrderForm. The database itself
 * still accepts assigned -> dispatched via the generic app.transition_shipment_order
 * RPC (the readiness gate is an application-level guard in front of an already-legal
 * edge, not a second parallel state machine) -- this module only controls which forms
 * this page renders.
 */
export function permittedNextStatuses(status: ShipmentOrderStatus, heldFromStatus: ShipmentOrderStatus | null): readonly TransitionableStatus[] {
  switch (status) {
    case "confirmed":
    case "planned":
    case "assigned":
    case "dispatched":
    case "in_transit":
      return ["held", "cancelled", ...nextForwardStatus(status)];
    case "held":
      return heldFromStatus ? [heldFromStatus as TransitionableStatus, "cancelled"] : ["cancelled"];
    case "delivered":
      return ["epod", "cancelled"];
    case "epod":
      return ["closed"];
    case "closed":
      // Reopen is a Supreme Admin-only correction (RPD-022) -- shown here for
      // affordance, the server rejects it for any other actor regardless.
      return ["delivered", "epod"];
    default:
      return [];
  }
}

function nextForwardStatus(status: ShipmentOrderStatus): readonly TransitionableStatus[] {
  const forward: Partial<Record<ShipmentOrderStatus, TransitionableStatus>> = {
    confirmed: "planned",
    planned: "assigned",
    dispatched: "in_transit",
    in_transit: "delivered",
  };
  const next = forward[status];
  return next ? [next] : [];
}

export const REASON_REQUIRED_STATUSES: readonly TransitionableStatus[] = ["held", "cancelled"];
export const EVIDENCE_REQUIRED_STATUSES: readonly TransitionableStatus[] = ["delivered", "epod", "closed"];
