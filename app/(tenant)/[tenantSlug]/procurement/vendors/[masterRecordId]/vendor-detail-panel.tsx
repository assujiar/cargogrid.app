"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { Timeline, type ActivityItemData } from "../../../../../../components/ui/timeline.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { VendorActionState } from "../actions.ts";
import type {
  VendorProfile,
  VendorContact,
  VendorAddress,
  VendorService,
  VendorCoverage,
  VendorDuplicateCandidate,
  VendorDuplicateSearchRow,
  VendorLifecycleEvent,
  VendorLifecycleStatus,
} from "../../../../../../server/contracts/vendor-profile/vendor-profile.ts";

const INITIAL_STATE: VendorActionState = { error: null };

const STATUS_TONE: Record<VendorLifecycleStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  under_review: "info",
  approved: "info",
  active: "success",
  suspended: "warning",
  archived: "neutral",
  blacklisted: "danger",
};

type PlainAction = (prevState: VendorActionState, formData: FormData) => Promise<VendorActionState>;

function ActionButton({ action, label, variant = "primary", confirmField }: { action: PlainAction; label: string; variant?: "primary" | "secondary" | "destructive"; confirmField?: { name: string; label: string; required?: boolean } }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {confirmField ? (
        <input name={confirmField.name} type="text" placeholder={confirmField.label} required={confirmField.required !== false} className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      ) : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={`${label}…`}>
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function DecisionButtons({ action }: { action: (prevState: VendorActionState, formData: FormData) => Promise<VendorActionState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const [reason, setReason] = useState("");
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <label htmlFor="review-reason" className="text-xs font-medium text-neutral-600">
        Reason (required to reject)
      </label>
      <input id="review-reason" name="reason" value={reason} onChange={(event) => setReason(event.currentTarget.value)} className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      <div className="flex gap-2">
        <Button type="submit" name="decision" value="approve" loading={pending} loadingLabel="Approving…">
          Approve
        </Button>
        <Button type="submit" name="decision" value="reject" variant="destructive" loading={pending} loadingLabel="Rejecting…">
          Reject
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function LifecycleActions({
  profile,
  submitAction,
  beginReviewAction,
  decideReviewAction,
  activateAction,
  suspendAction,
  reactivateAction,
  archiveAction,
  blacklistAction,
}: {
  profile: VendorProfile;
  submitAction: PlainAction;
  beginReviewAction: PlainAction;
  decideReviewAction: PlainAction;
  activateAction: PlainAction;
  suspendAction: PlainAction;
  reactivateAction: PlainAction;
  archiveAction: PlainAction;
  blacklistAction: PlainAction;
}) {
  switch (profile.lifecycleStatus) {
    case "draft":
      return <ActionButton action={submitAction} label="Submit for review" />;
    case "submitted":
      return <ActionButton action={beginReviewAction} label="Begin review" />;
    case "under_review":
      return <DecisionButtons action={decideReviewAction} />;
    case "approved":
      return <ActionButton action={activateAction} label="Activate" />;
    case "active":
      return (
        <div className="flex flex-col gap-2">
          <ActionButton action={suspendAction} label="Suspend" variant="secondary" confirmField={{ name: "reason", label: "Suspend reason" }} />
          <ActionButton action={blacklistAction} label="Blacklist" variant="destructive" confirmField={{ name: "reason", label: "Blacklist reason" }} />
        </div>
      );
    case "suspended":
      return (
        <div className="flex flex-col gap-2">
          <ActionButton action={reactivateAction} label="Reactivate" />
          <ActionButton action={archiveAction} label="Archive" variant="secondary" confirmField={{ name: "reason", label: "Archive reason (optional)", required: false }} />
          <ActionButton action={blacklistAction} label="Blacklist" variant="destructive" confirmField={{ name: "reason", label: "Blacklist reason" }} />
        </div>
      );
    case "archived":
    case "blacklisted":
      return <p className="text-sm text-neutral-500">No further lifecycle actions -- this vendor is in a terminal state.</p>;
    default:
      return null;
  }
}

export function VendorDetailPanel({
  tenantSlug: _tenantSlug,
  profile,
  contacts,
  addresses,
  services,
  coverage,
  duplicateCandidates,
  duplicateSuggestions,
  history,
  submitAction,
  beginReviewAction,
  decideReviewAction,
  activateAction,
  suspendAction,
  reactivateAction,
  archiveAction,
  blacklistAction,
  addContactAction,
  removeContactActionFor,
  addAddressAction,
  removeAddressActionFor,
  addServiceAction,
  removeServiceActionFor,
  addCoverageAction,
  removeCoverageActionFor,
  flagDuplicateActionFor,
  decideDuplicateActionFor,
}: {
  tenantSlug: string;
  profile: VendorProfile;
  contacts: readonly VendorContact[];
  addresses: readonly VendorAddress[];
  services: readonly VendorService[];
  coverage: readonly VendorCoverage[];
  duplicateCandidates: readonly VendorDuplicateCandidate[];
  duplicateSuggestions: readonly VendorDuplicateSearchRow[];
  history: readonly VendorLifecycleEvent[];
  submitAction: PlainAction;
  beginReviewAction: PlainAction;
  decideReviewAction: PlainAction;
  activateAction: PlainAction;
  suspendAction: PlainAction;
  reactivateAction: PlainAction;
  archiveAction: PlainAction;
  blacklistAction: PlainAction;
  addContactAction: PlainAction;
  removeContactActionFor: (contactId: string, expectedVersion: number) => PlainAction;
  addAddressAction: PlainAction;
  removeAddressActionFor: (addressId: string, expectedVersion: number) => PlainAction;
  addServiceAction: PlainAction;
  removeServiceActionFor: (serviceId: string, expectedVersion: number) => PlainAction;
  addCoverageAction: PlainAction;
  removeCoverageActionFor: (coverageId: string, expectedVersion: number) => PlainAction;
  flagDuplicateActionFor: (candidateMasterRecordId: string, similarityScore: number | null) => PlainAction;
  decideDuplicateActionFor: (candidateId: string, expectedVersion: number) => PlainAction;
}) {
  const isDraft = profile.lifecycleStatus === "draft";

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            {profile.legalName} <span className="text-sm font-normal text-neutral-500">({profile.vendorCode})</span>
          </h1>
          {profile.tradeName ? <p className="text-sm text-neutral-600">Trade name: {profile.tradeName}</p> : null}
          <div className="mt-1">
            <StatusBadge tone={STATUS_TONE[profile.lifecycleStatus]} label={profile.lifecycleStatus.replace(/_/g, " ")} />
          </div>
          {profile.revisionReason ? <p className="mt-1 text-xs text-warning">Revision requested: {profile.revisionReason}</p> : null}
          {profile.suspendReason ? <p className="mt-1 text-xs text-warning">Suspended: {profile.suspendReason}</p> : null}
          {profile.blacklistReason ? <p className="mt-1 text-xs text-danger">Blacklisted: {profile.blacklistReason}</p> : null}
        </div>
        <div className="w-64">
          <LifecycleActions
            profile={profile}
            submitAction={submitAction}
            beginReviewAction={beginReviewAction}
            decideReviewAction={decideReviewAction}
            activateAction={activateAction}
            suspendAction={suspendAction}
            reactivateAction={reactivateAction}
            archiveAction={archiveAction}
            blacklistAction={blacklistAction}
          />
        </div>
      </div>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">Identity</h2>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
          <dt className="text-neutral-500">Legal entity type</dt>
          <dd className="col-span-2 sm:col-span-1">{profile.legalEntityType ?? "—"}</dd>
          <dt className="text-neutral-500">Business registration number</dt>
          <dd className="col-span-2 sm:col-span-1">{profile.businessRegistrationNumber ?? "—"}</dd>
          <dt className="text-neutral-500">Category</dt>
          <dd className="col-span-2 sm:col-span-1">{profile.vendorCategory ?? "—"}</dd>
          <dt className="text-neutral-500">Payment term</dt>
          <dd className="col-span-2 sm:col-span-1">{profile.paymentTermDays !== null ? `${profile.paymentTermDays} days` : "—"}</dd>
          <dt className="text-neutral-500">Intake source</dt>
          <dd className="col-span-2 sm:col-span-1">{profile.intakeSource.replace(/_/g, " ")}</dd>
        </dl>
      </section>

      {isDraft && (duplicateCandidates.length > 0 || duplicateSuggestions.length > 0) ? (
        <section className="rounded-md border border-warning/40 bg-warning/5 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Possible duplicate vendors</h2>
          {duplicateCandidates.length === 0 ? (
            <p className="text-xs text-neutral-500">No candidates flagged yet. Submission will be blocked once one is flagged, until it is resolved below.</p>
          ) : (
            <ul className="mb-3 flex flex-col gap-2">
              {duplicateCandidates.map((candidate) => (
                <li key={candidate.id} className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2 text-xs">
                  <span>
                    Candidate {candidate.candidateMasterRecordId} — {candidate.similarityBasis} ({candidate.decision})
                  </span>
                  {candidate.decision === "pending" ? (
                    <DuplicateDecisionForm action={decideDuplicateActionFor(candidate.id, candidate.recordVersion)} />
                  ) : (
                    <span className="text-neutral-500">
                      Decided by {candidate.decidedBy}: {candidate.decidedReason}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
          {duplicateSuggestions.length > 0 ? (
            <div>
              <p className="mb-1 text-xs font-medium text-neutral-700">Similar existing vendors (not yet flagged):</p>
              <ul className="flex flex-col gap-1">
                {duplicateSuggestions.map((suggestion) => (
                  <li key={suggestion.masterRecordId} className="flex items-center justify-between gap-2 text-xs">
                    <span>
                      {suggestion.legalName} ({suggestion.vendorCode}) — similarity {suggestion.similarityScore.toFixed(2)}
                    </span>
                    <FlagButton action={flagDuplicateActionFor(suggestion.masterRecordId, suggestion.similarityScore)} />
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </section>
      ) : null}

      <ContactsSection contacts={contacts} isDraft={isDraft} addAction={addContactAction} removeActionFor={removeContactActionFor} />
      <AddressesSection addresses={addresses} isDraft={isDraft} addAction={addAddressAction} removeActionFor={removeAddressActionFor} />
      <ServicesSection services={services} isDraft={isDraft} addAction={addServiceAction} removeActionFor={removeServiceActionFor} />
      <CoverageSection coverage={coverage} isDraft={isDraft} addAction={addCoverageAction} removeActionFor={removeCoverageActionFor} />

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">Lifecycle timeline</h2>
        {history.length === 0 ? (
          <p className="text-sm text-neutral-500">No lifecycle events yet.</p>
        ) : (
          <Timeline
            items={history.map(
              (event): ActivityItemData => ({
                at: event.occurredAt,
                actor: event.actorLabel ?? "system",
                event: `${event.fromStatus} → ${event.toStatus}${event.reason ? ` (${event.reason})` : ""}`,
              }),
            )}
          />
        )}
      </section>
    </div>
  );
}

function FlagButton({ action }: { action: PlainAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Flagging…">
        Flag as duplicate
      </Button>
      {state.error ? <span className="text-danger">{state.error}</span> : null}
    </form>
  );
}

function DuplicateDecisionForm({ action }: { action: PlainAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      <input name="reason" type="text" required placeholder="Decision reason" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      <Button type="submit" name="decision" value="linked" variant="secondary" loading={pending} loadingLabel="Saving…">
        Link (same vendor)
      </Button>
      <Button type="submit" name="decision" value="dismissed" loading={pending} loadingLabel="Saving…">
        Dismiss (different vendor)
      </Button>
      {state.error ? <span className="text-danger">{state.error}</span> : null}
    </form>
  );
}

function ContactsSection({ contacts, isDraft, addAction, removeActionFor }: { contacts: readonly VendorContact[]; isDraft: boolean; addAction: PlainAction; removeActionFor: (id: string, version: number) => PlainAction }) {
  const [state, formAction, pending] = useActionState(addAction, INITIAL_STATE);
  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="mb-2 text-sm font-semibold text-neutral-900">Contacts</h2>
      {contacts.length === 0 ? (
        <p className="text-sm text-neutral-500">No contacts yet.</p>
      ) : (
        <ul className="mb-3 flex flex-col gap-1 text-sm">
          {contacts.map((contact) => (
            <li key={contact.id} className="flex items-center justify-between gap-2 rounded-md border border-neutral-100 p-2">
              <span>
                {contact.name}
                {contact.isPrimary ? <span className="ml-1 text-xs text-primary">(primary)</span> : null}
                {contact.title ? ` — ${contact.title}` : ""} {contact.email ?? contact.phone ? `(${[contact.email, contact.phone].filter(Boolean).join(", ")})` : ""}
              </span>
              {isDraft ? <RemoveButton action={removeActionFor(contact.id, contact.recordVersion)} /> : null}
            </li>
          ))}
        </ul>
      )}
      {isDraft ? (
        <form action={formAction} className="flex flex-wrap items-end gap-2">
          <input name="name" type="text" required placeholder="Name" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="title" type="text" placeholder="Title" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="email" type="email" placeholder="Email" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="phone" type="tel" placeholder="Phone" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <label className="flex items-center gap-1 text-xs text-neutral-600">
            <input name="isPrimary" type="checkbox" /> Primary
          </label>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
            Add contact
          </Button>
          {state.error ? <span className="text-xs text-danger">{state.error}</span> : null}
        </form>
      ) : (
        <p className="text-xs text-neutral-400">Contacts may only be edited while this vendor is a draft.</p>
      )}
    </section>
  );
}

function AddressesSection({ addresses, isDraft, addAction, removeActionFor }: { addresses: readonly VendorAddress[]; isDraft: boolean; addAction: PlainAction; removeActionFor: (id: string, version: number) => PlainAction }) {
  const [state, formAction, pending] = useActionState(addAction, INITIAL_STATE);
  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="mb-2 text-sm font-semibold text-neutral-900">Addresses</h2>
      {addresses.length === 0 ? (
        <p className="text-sm text-neutral-500">No addresses yet.</p>
      ) : (
        <ul className="mb-3 flex flex-col gap-1 text-sm">
          {addresses.map((address) => (
            <li key={address.id} className="flex items-center justify-between gap-2 rounded-md border border-neutral-100 p-2">
              <span>
                <span className="text-xs uppercase text-neutral-500">{address.addressType}</span> — {address.street}, {address.city}
                {address.province ? `, ${address.province}` : ""}, {address.country}
              </span>
              {isDraft ? <RemoveButton action={removeActionFor(address.id, address.recordVersion)} /> : null}
            </li>
          ))}
        </ul>
      )}
      {isDraft ? (
        <form action={formAction} className="flex flex-wrap items-end gap-2">
          <select name="addressType" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
            <option value="legal">legal</option>
            <option value="billing">billing</option>
            <option value="operational">operational</option>
          </select>
          <input name="street" type="text" required placeholder="Street" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="city" type="text" required placeholder="City" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="province" type="text" placeholder="Province" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="postalCode" type="text" placeholder="Postal code" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="country" type="text" required placeholder="Country" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
            Add address
          </Button>
          {state.error ? <span className="text-xs text-danger">{state.error}</span> : null}
        </form>
      ) : (
        <p className="text-xs text-neutral-400">Addresses may only be edited while this vendor is a draft.</p>
      )}
    </section>
  );
}

function ServicesSection({ services, isDraft, addAction, removeActionFor }: { services: readonly VendorService[]; isDraft: boolean; addAction: PlainAction; removeActionFor: (id: string, version: number) => PlainAction }) {
  const [state, formAction, pending] = useActionState(addAction, INITIAL_STATE);
  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="mb-2 text-sm font-semibold text-neutral-900">Services</h2>
      {services.length === 0 ? (
        <p className="text-sm text-neutral-500">No services yet.</p>
      ) : (
        <ul className="mb-3 flex flex-col gap-1 text-sm">
          {services.map((service) => (
            <li key={service.id} className="flex items-center justify-between gap-2 rounded-md border border-neutral-100 p-2">
              <span>{service.serviceType}</span>
              {isDraft ? <RemoveButton action={removeActionFor(service.id, service.recordVersion)} /> : null}
            </li>
          ))}
        </ul>
      )}
      {isDraft ? (
        <form action={formAction} className="flex flex-wrap items-end gap-2">
          <input name="serviceType" type="text" required placeholder="Service type (e.g. trucking)" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
            Add service
          </Button>
          {state.error ? <span className="text-xs text-danger">{state.error}</span> : null}
        </form>
      ) : (
        <p className="text-xs text-neutral-400">Services may only be edited while this vendor is a draft.</p>
      )}
    </section>
  );
}

function CoverageSection({ coverage, isDraft, addAction, removeActionFor }: { coverage: readonly VendorCoverage[]; isDraft: boolean; addAction: PlainAction; removeActionFor: (id: string, version: number) => PlainAction }) {
  const [state, formAction, pending] = useActionState(addAction, INITIAL_STATE);
  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="mb-2 text-sm font-semibold text-neutral-900">Coverage</h2>
      {coverage.length === 0 ? (
        <p className="text-sm text-neutral-500">No coverage lanes yet.</p>
      ) : (
        <ul className="mb-3 flex flex-col gap-1 text-sm">
          {coverage.map((lane) => (
            <li key={lane.id} className="flex items-center justify-between gap-2 rounded-md border border-neutral-100 p-2">
              <span>
                {lane.originLane}
                {lane.destinationLane ? ` → ${lane.destinationLane}` : ""}
              </span>
              {isDraft ? <RemoveButton action={removeActionFor(lane.id, lane.recordVersion)} /> : null}
            </li>
          ))}
        </ul>
      )}
      {isDraft ? (
        <form action={formAction} className="flex flex-wrap items-end gap-2">
          <input name="originLane" type="text" required placeholder="Origin lane / region" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <input name="destinationLane" type="text" placeholder="Destination lane (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
            Add coverage
          </Button>
          {state.error ? <span className="text-xs text-danger">{state.error}</span> : null}
        </form>
      ) : (
        <p className="text-xs text-neutral-400">Coverage may only be edited while this vendor is a draft.</p>
      )}
    </section>
  );
}

function RemoveButton({ action }: { action: PlainAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction}>
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Removing…">
        Remove
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
