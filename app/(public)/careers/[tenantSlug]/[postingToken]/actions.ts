"use server";

/**
 * Public job application Server Action (HRT-276, CG-S12-HRT-004). Mirrors
 * app/(public)/vendor-intake/[token]/actions.ts's own service-role-client shape --
 * the applying candidate has no auth.users session at all. Calls
 * app.submit_public_job_application, a genuinely anonymous RPC bound to an OPEN
 * vacancy's own multi-use posting token. Writes only a new candidate/application pair
 * -- never reads any existing tenant/candidate data (section 16).
 */

import { createHash, randomUUID } from "node:crypto";
import { headers } from "next/headers";
import { cookies } from "next/headers";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { submitPublicJobApplication } from "../../../../../server/mutations/recruitment.ts";
import type { PublicSubmitResult } from "../../../../../server/contracts/recruitment/recruitment.ts";

export interface PublicApplicationFormState {
  readonly error: string | null;
  readonly result: PublicSubmitResult | null;
}

const IDEMPOTENCY_COOKIE_PREFIX = "cg_apply_idem_";

export async function submitPublicJobApplicationAction(postingToken: string, _prevState: PublicApplicationFormState, formData: FormData): Promise<PublicApplicationFormState> {
  const fullName = String(formData.get("fullName") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const consentGiven = formData.get("consentGiven") === "on";
  const consentVersion = "careers-page-v1";

  if (!fullName || !email) {
    return { error: "Your full name and email are required.", result: null };
  }
  if (!consentGiven) {
    return { error: "You must consent to your data being processed to apply.", result: null };
  }

  // client_key is a sha256 hash of the caller's own best-effort IP address, never the
  // raw IP itself, mirroring app/(public)/vendor-intake/[token]/actions.ts exactly.
  const requestHeaders = await headers();
  const ipAddress = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  // A stable per-browser idempotency key (a fresh cookie, not derived from any
  // personal data) -- a resubmission of the SAME form (double-click, back-button
  // retry) is a true replay; a genuinely new submission from the same browser later
  // gets a fresh key.
  const cookieStore = await cookies();
  const cookieName = IDEMPOTENCY_COOKIE_PREFIX + postingToken.slice(0, 16);
  let idempotencyKey = cookieStore.get(cookieName)?.value ?? null;
  if (!idempotencyKey) {
    idempotencyKey = randomUUID();
    cookieStore.set(cookieName, idempotencyKey, { httpOnly: true, sameSite: "lax", maxAge: 60 * 60 });
  }

  const client = createSupabaseServiceRoleClient();
  const result = await submitPublicJobApplication(client, {
    postingToken,
    clientKey,
    fullName,
    email,
    phone,
    consentGiven,
    consentVersion,
    idempotencyKey,
  });

  if (result.submitStatus !== "ok") {
    const message: Record<string, string> = {
      not_found: "This job posting is no longer available.",
      invalid: "Please provide your full name, email, and consent to apply.",
      rate_limited: "Too many attempts from this connection. Please try again later.",
      conflict: "Your earlier submission for this role could not be matched. Please try again.",
    };
    return { error: message[result.submitStatus] ?? "This application could not be submitted.", result };
  }

  return { error: null, result };
}
