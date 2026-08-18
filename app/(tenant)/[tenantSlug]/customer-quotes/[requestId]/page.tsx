import { randomUUID } from "node:crypto";
import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerQuoteRequest, listCustomerQuoteRequestFiles, CustomerQuoteRequestQueryError } from "../../../../../server/queries/customer-quote-request.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerQuoteDetailPanel } from "./customer-quote-detail-panel.tsx";
import {
  updateCustomerQuoteRequestDraftAction,
  submitCustomerQuoteRequestAction,
  cancelCustomerQuoteRequestAction,
  uploadCustomerQuoteRequestAttachmentAction,
} from "../actions.ts";

/**
 * Customer quote request detail/status-timeline view (CPL-302, CG-S13-CPL-
 * 004). Uses ONLY the customer-safe get RPC (app.get_customer_quote_
 * request) -- an out-of-scope request id and a genuinely nonexistent id are
 * indistinguishable here (both raise the identical anti-enumerating
 * record_not_found), which is why this page renders a plain 404 rather than
 * a "forbidden" state that would disclose which case occurred (mirrors
 * app/(tenant)/[tenantSlug]/customer-tickets/[ticketId]/page.tsx exactly).
 */
export default async function CustomerQuoteDetailPage({ params }: { params: Promise<{ tenantSlug: string; requestId: string }> }) {
  const { tenantSlug, requestId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let detail: Awaited<ReturnType<typeof getCustomerQuoteRequest>> | null = null;
  let files: Awaited<ReturnType<typeof listCustomerQuoteRequestFiles>> = [];

  try {
    detail = await getCustomerQuoteRequest(supabase, access.tenant.id, requestId, access.authUserId);
    files = await listCustomerQuoteRequestFiles(supabase, access.tenant.id, requestId, access.authUserId);
  } catch (error) {
    if (!(error instanceof CustomerQuoteRequestQueryError)) throw error;
    if (error.code === "record_not_found") {
      notFoundResult = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundResult) {
    notFound();
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this quote request. Please try again." />;
  }

  const recordVersion = detail.recordVersion;
  // Fresh per render, not regenerated per submit -- a genuine retry of the
  // SAME rendered form reuses this same key, mirroring the operations
  // Shipment Order detail page's own established `randomUUID()`-per-render
  // idempotency-key convention exactly.
  const submitIdempotencyKey = randomUUID();
  // Independent key for the attachment-upload form (a different resource,
  // a different idempotency domain) -- Tier C fix (spec-compliance):
  // previously generated inside uploadCustomerQuoteRequestAttachmentAction's
  // own body from Date.now(), which produced a different key on every
  // physical re-invocation. revalidatePath(detailPath) after a successful
  // upload re-renders this page and mints a fresh key for the NEXT
  // attachment, while a retry of the SAME upload attempt reuses this one.
  const attachIdempotencyKey = randomUUID();

  return (
    <CustomerQuoteDetailPanel
      detail={detail}
      files={files}
      updateAction={updateCustomerQuoteRequestDraftAction.bind(null, tenantSlug, requestId, recordVersion)}
      submitAction={submitCustomerQuoteRequestAction.bind(null, tenantSlug, requestId, recordVersion, submitIdempotencyKey)}
      cancelAction={cancelCustomerQuoteRequestAction.bind(null, tenantSlug, requestId, recordVersion)}
      uploadAction={uploadCustomerQuoteRequestAttachmentAction.bind(null, tenantSlug, requestId, attachIdempotencyKey)}
    />
  );
}
