"use server";

/**
 * Vendor intake token redemption Server Action (PRC-251, CG-S11-PRC-002). Mirrors
 * app/(public)/quote-decision/[token]/actions.ts's own service-role-client shape --
 * the invited party presenting this token has no auth.users session at all. Calls
 * app.redeem_vendor_intake_token_and_submit, a genuinely anonymous RPC: no actor, no
 * PRC:* permission check, authorization is the raw bearer token alone. Writes ONLY a
 * new, staged vendor_profiles row -- never reads any existing vendor/tenant data
 * (Prompt 251 §16).
 */

import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { redeemVendorIntakeToken } from "../../../../server/mutations/vendor-profile.ts";
import type { VendorIntakeSubmitResult } from "../../../../server/contracts/vendor-profile/vendor-profile.ts";

export interface VendorIntakeFormState {
  readonly error: string | null;
  readonly result: VendorIntakeSubmitResult | null;
}

export async function redeemVendorIntakeTokenAction(rawToken: string, _prevState: VendorIntakeFormState, formData: FormData): Promise<VendorIntakeFormState> {
  const legalName = String(formData.get("legalName") ?? "").trim();
  const tradeName = String(formData.get("tradeName") ?? "").trim() || null;
  const legalEntityType = String(formData.get("legalEntityType") ?? "").trim() || null;
  const businessRegistrationNumber = String(formData.get("businessRegistrationNumber") ?? "").trim() || null;
  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();
  const contactName = String(formData.get("contactName") ?? "").trim() || null;
  const contactEmail = String(formData.get("contactEmail") ?? "").trim() || null;
  const contactPhone = String(formData.get("contactPhone") ?? "").trim() || null;

  if (!legalName) {
    return { error: "Your company's legal name is required.", result: null };
  }

  // client_key is a sha256 hash of the caller's own best-effort IP address, never the
  // raw IP itself (app.vendor_intake_attempts is retained as rate-limit evidence) --
  // the same disclosed "no verified identity" shape app/(public)/tracking/[token]/
  // page.tsx already established.
  const requestHeaders = await headers();
  const ipAddress = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const client = createSupabaseServiceRoleClient();
  const result = await redeemVendorIntakeToken(client, {
    rawToken,
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
  });

  if (result.submitStatus !== "ok") {
    const message: Record<string, string> = {
      not_found: "This invitation link is no longer valid.",
      invalid: "Please provide your company's legal name.",
      rate_limited: "Too many attempts from this connection. Please try again later.",
      conflict: "This invitation has already been used to submit different vendor details.",
      disabled: "This invitation link is no longer valid.",
    };
    return { error: message[result.submitStatus] ?? "This submission could not be completed.", result };
  }

  return { error: null, result };
}
