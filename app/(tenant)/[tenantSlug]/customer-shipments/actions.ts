"use server";

/**
 * Customer Shipment Order Server Actions (CPL-304, CG-S13-CPL-006). Mirrors
 * app/(tenant)/[tenantSlug]/customer-bookings/actions.ts's own shape --
 * resolve the portal guard first, forward to the typed mutation wrapper,
 * classify the error into a form-safe message, revalidate the affected
 * route. The only write this capability exposes to a customer is "request a
 * change" -- app.confirm_shipment_order/app.cancel_shipment_order remain
 * completely unreachable from here.
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer
 * 4 portal entry guard).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { requestCustomerShipmentOrderChange, CustomerShipmentOrderMutationError } from "../../../../server/mutations/customer-shipment-order.ts";

export interface CustomerShipmentOrderActionState {
  readonly error: string | null;
}

const OK: CustomerShipmentOrderActionState = { error: null };
const NO_ACCESS: CustomerShipmentOrderActionState = { error: "You don't have access to this organization's customer portal." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, shipmentOrderId: string): string {
  return `/${tenantSlug}/customer-shipments/${shipmentOrderId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerShipmentOrderActionState {
  if (error instanceof CustomerShipmentOrderMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

function orNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  return text.length === 0 ? null : text;
}

export async function requestCustomerShipmentOrderChangeAction(
  tenantSlug: string,
  shipmentOrderId: string,
  idempotencyKey: string,
  _prevState: CustomerShipmentOrderActionState,
  formData: FormData,
): Promise<CustomerShipmentOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const requestType = orNull(formData.get("requestType"));
  if (requestType !== "reschedule" && requestType !== "cancel" && requestType !== "other") {
    return { error: "Select a request type." };
  }
  const details = orNull(formData.get("details"));
  if (!details) return { error: "Describe the change you're requesting." };

  const supabase = await createSupabaseServerClient();
  try {
    await requestCustomerShipmentOrderChange(supabase, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      requestType,
      details,
      // Tier C fix (spec-compliance): idempotencyKey is now generated ONCE
      // per Server Component render (see page.tsx's own randomUUID() call)
      // and bound into this action's closure -- not regenerated here on
      // every invocation. A `Date.now()`-derived key computed inside the
      // action body produced a DIFFERENT key on every physical
      // re-invocation, defeating the double-submit protection this
      // parameter exists for. Mirrors CPL-302/303's identical fix.
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not submit this change request", error);
  }
  revalidatePath(detailPath(tenantSlug, shipmentOrderId));
  return OK;
}
