"use server";

/**
 * Customer Shipment Order Server Actions (CPL-304, CG-S13-CPL-006; extended
 * at CPL-306, CG-S13-CPL-008, Prompt 306 with subscribe/unsubscribe alert
 * actions). Mirrors app/(tenant)/[tenantSlug]/customer-bookings/actions.ts's
 * own shape -- resolve the portal guard first, forward to the typed
 * mutation wrapper, classify the error into a form-safe message, revalidate
 * the affected route. The only writes this capability exposes to a customer
 * are "request a change" and "subscribe/unsubscribe to a shipment alert" --
 * app.confirm_shipment_order/app.cancel_shipment_order remain completely
 * unreachable from here.
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer
 * 4 portal entry guard).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { requestCustomerShipmentOrderChange, CustomerShipmentOrderMutationError } from "../../../../server/mutations/customer-shipment-order.ts";
import { subscribeCustomerShipmentAlert, unsubscribeCustomerShipmentAlert, CustomerShipmentAlertMutationError } from "../../../../server/mutations/customer-shipment-alert.ts";
import type { CustomerShipmentAlertType } from "../../../../server/contracts/customer-shipment-alert/customer-shipment-alert.ts";
import { getCustomerEpod, CustomerEpodMutationError } from "../../../../server/mutations/customer-epod.ts";

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

// --- Shipment alert subscribe/unsubscribe (CPL-306) ---
//
// Neither action takes a client-supplied idempotency key -- both underlying
// RPCs are natural-key upserts (tenant, shipment_order, identity,
// alert_type), never a client-generated-token short-circuit (migration
// header decision 3). Each row is its own tiny form (one alert type, one
// direction) -- see customer-shipment-alert-subscriptions-panel.tsx.

function alertErrorMessage(prefix: string, error: unknown): CustomerShipmentOrderActionState {
  if (error instanceof CustomerShipmentAlertMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

export async function subscribeCustomerShipmentAlertAction(
  tenantSlug: string,
  shipmentOrderId: string,
  alertType: CustomerShipmentAlertType,
  _prevState: CustomerShipmentOrderActionState,
  _formData: FormData,
): Promise<CustomerShipmentOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await subscribeCustomerShipmentAlert(supabase, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      alertType,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return alertErrorMessage("Could not turn this alert on", error);
  }
  revalidatePath(detailPath(tenantSlug, shipmentOrderId));
  return OK;
}

export async function unsubscribeCustomerShipmentAlertAction(
  tenantSlug: string,
  shipmentOrderId: string,
  alertType: CustomerShipmentAlertType,
  _prevState: CustomerShipmentOrderActionState,
  _formData: FormData,
): Promise<CustomerShipmentOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await unsubscribeCustomerShipmentAlert(supabase, {
      tenantId: access.tenant.id,
      shipmentOrderId,
      alertType,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return alertErrorMessage("Could not turn this alert off", error);
  }
  revalidatePath(detailPath(tenantSlug, shipmentOrderId));
  return OK;
}

// --- ePOD access (CPL-307) ---
//
// A real, audited access attempt (app.get_customer_epod itself writes an
// app.file_access_logs/app.capture_audit_event row on every call, migration
// design decision 3) -- never a decorative no-op button. Returns no payload
// of its own; revalidatePath refreshes the page's own eager
// getCustomerEpod fetch, exactly like every other action in this file.

function epodErrorMessage(prefix: string, error: unknown): CustomerShipmentOrderActionState {
  if (error instanceof CustomerEpodMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

export async function accessCustomerEpodAction(
  tenantSlug: string,
  shipmentOrderId: string,
  _prevState: CustomerShipmentOrderActionState,
  _formData: FormData,
): Promise<CustomerShipmentOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await getCustomerEpod(supabase, access.tenant.id, access.authUserId, shipmentOrderId);
  } catch (error) {
    return epodErrorMessage("Could not access delivery evidence", error);
  }
  revalidatePath(detailPath(tenantSlug, shipmentOrderId));
  return OK;
}
