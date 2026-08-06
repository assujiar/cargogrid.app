"use server";

/**
 * Vendor self-registration Server Action (PRC-251, CG-S11-PRC-002). Mirrors
 * app/(public)/vendor-intake/[token]/actions.ts's own service-role-client shape --
 * the visitor has no auth.users session at all. Calls
 * app.submit_vendor_profile_self_registration, a genuinely anonymous RPC gated only
 * by the tenant's own published procurement.vendor_self_registration.enabled config
 * flag (already re-checked server-side by the RPC itself, not merely trusted from
 * the page's earlier resolve call). Writes ONLY a new, staged vendor_profiles row --
 * never reads any existing vendor/tenant data (Prompt 251 §16).
 */

import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { submitVendorProfileSelfRegistration } from "../../../../../server/mutations/vendor-profile.ts";
import type { VendorIntakeSubmitResult } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";

export interface VendorSelfRegistrationFormState {
  readonly error: string | null;
  readonly result: VendorIntakeSubmitResult | null;
}

export async function submitVendorSelfRegistrationAction(tenantId: string, _prevState: VendorSelfRegistrationFormState, formData: FormData): Promise<VendorSelfRegistrationFormState> {
  const legalName = String(formData.get("legalName") ?? "").trim();
  const tradeName = String(formData.get("tradeName") ?? "").trim() || null;
  const legalEntityType = String(formData.get("legalEntityType") ?? "").trim() || null;
  const businessRegistrationNumber = String(formData.get("businessRegistrationNumber") ?? "").trim() || null;
  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();
  const contactName = String(formData.get("contactName") ?? "").trim() || null;
  const contactEmail = String(formData.get("contactEmail") ?? "").trim() || null;
  const contactPhone = String(formData.get("contactPhone") ?? "").trim() || null;
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;

  if (!legalName) {
    return { error: "Your company's legal name is required.", result: null };
  }

  // client_key is a sha256 hash of the caller's own best-effort IP address, never the
  // raw IP itself -- same disclosed shape as the token-redemption action and
  // app/(public)/tracking/[token]/page.tsx before it.
  const requestHeaders = await headers();
  const ipAddress = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const client = createSupabaseServiceRoleClient();
  const result = await submitVendorProfileSelfRegistration(client, {
    tenantId,
    clientKey,
    legalName,
    tradeName,
    legalEntityType,
    businessRegistrationNumber,
    vendorCategory,
    paymentTermDays: paymentTermDaysRaw.length === 0 ? null : Number(paymentTermDaysRaw),
    contactName,
    contactEmail,
    contactPhone,
    idempotencyKey,
  });

  if (result.submitStatus !== "ok") {
    const message: Record<string, string> = {
      not_found: "Vendor registration is not available for this organization.",
      invalid: "Please provide your company's legal name.",
      rate_limited: "Too many attempts from this connection. Please try again later.",
      conflict: "This submission conflicts with an earlier one using the same details request. Please refresh and try again.",
      disabled: "Vendor registration is not available for this organization.",
    };
    return { error: message[result.submitStatus] ?? "This submission could not be completed.", result };
  }

  return { error: null, result };
}
