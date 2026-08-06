import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getVendorProfile,
  listVendorContacts,
  listVendorAddresses,
  listVendorServices,
  listVendorCoverage,
  listVendorDuplicateCandidates,
  searchVendorDuplicateCandidates,
  getVendorLifecycleHistory,
  VendorProfileQueryError,
} from "../../../../../../server/queries/vendor-profile.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorDetailPanel } from "./vendor-detail-panel.tsx";
import {
  submitVendorProfileAction,
  beginVendorProfileReviewAction,
  decideVendorProfileReviewAction,
  activateVendorProfileAction,
  suspendVendorProfileAction,
  reactivateVendorProfileAction,
  archiveVendorProfileAction,
  blacklistVendorProfileAction,
  addVendorContactAction,
  removeVendorContactAction,
  addVendorAddressAction,
  removeVendorAddressAction,
  addVendorServiceAction,
  removeVendorServiceAction,
  addVendorCoverageAction,
  removeVendorCoverageAction,
  flagVendorDuplicateCandidateAction,
  decideVendorDuplicateCandidateAction,
} from "../actions.ts";

/**
 * Vendor profile detail page (PRC-251, CG-S11-PRC-002): core identity, lifecycle
 * action buttons (each simply calling the gated RPC -- an unauthorized attempt
 * surfaces the RPC's own insufficient_authority message inline, the same
 * "authorization enforced server-side, not hidden client-side" precedent
 * app/(tenant)/[tenantSlug]/operations/fleet/ already established), a lifecycle
 * timeline, child-record management (draft-only), and the duplicate-candidate review
 * screen.
 */
export default async function VendorDetailPage({ params }: { params: Promise<{ tenantSlug: string; masterRecordId: string }> }) {
  const { tenantSlug, masterRecordId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type LoadedData = {
    profile: Awaited<ReturnType<typeof getVendorProfile>>;
    contacts: Awaited<ReturnType<typeof listVendorContacts>>;
    addresses: Awaited<ReturnType<typeof listVendorAddresses>>;
    services: Awaited<ReturnType<typeof listVendorServices>>;
    coverage: Awaited<ReturnType<typeof listVendorCoverage>>;
    duplicateCandidates: Awaited<ReturnType<typeof listVendorDuplicateCandidates>>;
    duplicateSuggestions: Awaited<ReturnType<typeof searchVendorDuplicateCandidates>>;
    history: Awaited<ReturnType<typeof getVendorLifecycleHistory>>;
  };

  let loaded: LoadedData | null = null;
  let loadFailed = false;
  try {
    const [profile, contacts, addresses, services, coverage, duplicateCandidates, history] = await Promise.all([
      getVendorProfile(supabase, masterRecordId, access.authUserId),
      listVendorContacts(supabase, masterRecordId, access.authUserId),
      listVendorAddresses(supabase, masterRecordId, access.authUserId),
      listVendorServices(supabase, masterRecordId, access.authUserId),
      listVendorCoverage(supabase, masterRecordId, access.authUserId),
      listVendorDuplicateCandidates(supabase, masterRecordId, access.authUserId),
      getVendorLifecycleHistory(supabase, masterRecordId, access.authUserId),
    ]);

    const duplicateSuggestions =
      profile.lifecycleStatus === "draft" ? await searchVendorDuplicateCandidates(supabase, access.tenant.id, profile.legalName, profile.tradeName, access.authUserId, 5) : [];

    loaded = { profile, contacts, addresses, services, coverage, duplicateCandidates, duplicateSuggestions, history };
  } catch (error) {
    if (!(error instanceof VendorProfileQueryError)) throw error;
    if (error.message.startsWith("vendor_profile_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this vendor. Please try again." />;
  }

  const { profile, contacts, addresses, services, coverage, duplicateCandidates, duplicateSuggestions, history } = loaded;

  return (
    <VendorDetailPanel
      tenantSlug={tenantSlug}
      profile={profile}
      contacts={contacts}
      addresses={addresses}
      services={services}
      coverage={coverage}
      duplicateCandidates={duplicateCandidates}
      duplicateSuggestions={duplicateSuggestions.filter((s) => s.masterRecordId !== masterRecordId)}
      history={history}
      submitAction={submitVendorProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      beginReviewAction={beginVendorProfileReviewAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      decideReviewAction={decideVendorProfileReviewAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      activateAction={activateVendorProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      suspendAction={suspendVendorProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      reactivateAction={reactivateVendorProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      archiveAction={archiveVendorProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      blacklistAction={blacklistVendorProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      addContactAction={addVendorContactAction.bind(null, tenantSlug, masterRecordId)}
      removeContactActionFor={(contactId, expectedVersion) => removeVendorContactAction.bind(null, tenantSlug, masterRecordId, contactId, expectedVersion)}
      addAddressAction={addVendorAddressAction.bind(null, tenantSlug, masterRecordId)}
      removeAddressActionFor={(addressId, expectedVersion) => removeVendorAddressAction.bind(null, tenantSlug, masterRecordId, addressId, expectedVersion)}
      addServiceAction={addVendorServiceAction.bind(null, tenantSlug, masterRecordId)}
      removeServiceActionFor={(serviceId, expectedVersion) => removeVendorServiceAction.bind(null, tenantSlug, masterRecordId, serviceId, expectedVersion)}
      addCoverageAction={addVendorCoverageAction.bind(null, tenantSlug, masterRecordId)}
      removeCoverageActionFor={(coverageId, expectedVersion) => removeVendorCoverageAction.bind(null, tenantSlug, masterRecordId, coverageId, expectedVersion)}
      flagDuplicateActionFor={(candidateMasterRecordId, similarityScore) => flagVendorDuplicateCandidateAction.bind(null, tenantSlug, masterRecordId, candidateMasterRecordId, similarityScore)}
      decideDuplicateActionFor={(candidateId, expectedVersion) => decideVendorDuplicateCandidateAction.bind(null, tenantSlug, masterRecordId, candidateId, expectedVersion)}
    />
  );
}
