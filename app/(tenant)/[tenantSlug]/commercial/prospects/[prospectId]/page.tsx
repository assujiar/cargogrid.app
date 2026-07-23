import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getProspectById, getProspectConversionReadiness, ProspectQueryError } from "../../../../../../server/queries/prospect.ts";
import { ProspectActionsPanel } from "./prospect-actions-panel.tsx";

/**
 * Prospect Detail (COM-144, CG-S7-COM-003). `getProspectById` returns `null` for both
 * "does not exist" and "exists but RLS denies it" -- deliberately not distinguished, the
 * same posture COM-143's own Lead Detail page uses. Conversion readiness is read live
 * (never stored) since app.get_prospect_conversion_readiness is a real-time evaluator,
 * not a cached status.
 */
export default async function ProspectDetailPage({ params }: { params: Promise<{ tenantSlug: string; prospectId: string }> }) {
  const { tenantSlug, prospectId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let prospect;
  let readiness;
  try {
    prospect = await getProspectById(supabase, prospectId);
    if (prospect) {
      readiness = await getProspectConversionReadiness(supabase, prospectId);
    }
  } catch (error) {
    if (!(error instanceof ProspectQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this prospect. Please try again.</p>
      </div>
    );
  }

  if (!prospect || prospect.tenantId !== access.tenant.id) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{prospect.legalName}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Trade name</dt>
        <dd className="text-neutral-900">{prospect.tradeName ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Tax ID</dt>
        <dd className="text-neutral-900">{prospect.taxId ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Contact</dt>
        <dd className="text-neutral-900">{prospect.contactName}</dd>
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{prospect.status}</dd>
        {prospect.status === "disqualified" ? (
          <>
            <dt className="font-medium text-neutral-600">Disqualify reason</dt>
            <dd className="text-neutral-900">{prospect.disqualifyReason}</dd>
          </>
        ) : null}
        <dt className="font-medium text-neutral-600">Source lead</dt>
        <dd className="text-neutral-900">
          <a href={`/${tenantSlug}/commercial/leads/${prospect.leadId}`} className="font-medium text-primary underline">
            View lead
          </a>
        </dd>
      </dl>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Customer conversion readiness</h2>
        {readiness?.ready ? (
          <p className="mt-2 text-sm text-neutral-600">Ready — all mandatory fields are present.</p>
        ) : (
          <p className="mt-2 text-sm text-neutral-600">
            Not ready — missing: {readiness?.missing.join(", ") ?? "unknown"}.
          </p>
        )}
      </div>

      <ProspectActionsPanel tenantSlug={tenantSlug} prospectId={prospect.id} recordVersion={prospect.recordVersion} status={prospect.status} />
    </div>
  );
}
