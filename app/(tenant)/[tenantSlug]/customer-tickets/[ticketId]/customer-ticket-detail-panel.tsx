"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { CustomerTicketActionState, CustomerTicketLinkSearchActionState, CustomerTicketPortalLinkSearchActionState } from "../actions.ts";
import type {
  CustomerTicketDetail,
  CustomerTicketMessageRow,
  TicketStatus,
  TicketLinkRow,
  TicketLinkEntityType,
  TicketLinkRelationship,
  TicketPortalLinkRow,
  TicketPortalLinkEntityType,
  TicketSlaStatusForRequesterRow,
  TicketEscalationStatusForRequesterRow,
} from "../../../../../server/contracts/ticketing/ticketing.ts";
import { TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES, TICKET_LINK_RELATIONSHIPS, TICKET_PORTAL_LINK_ENTITY_TYPES } from "../../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: CustomerTicketActionState = { error: null };

const CUSTOMER_LINK_ENTITY_TYPE_LABELS: Record<TicketLinkEntityType, string> = {
  shipment: "Shipment",
  invoice: "Invoice",
  warehouse: "Warehouse",
  vendor: "Vendor",
  customer: "My account",
  user: "User",
};

// CPL-313: a SEPARATE label map for the SEPARATE app.ticket_portal_links
// registry -- see server/contracts/ticketing/ticketing.ts's own header
// comment for why warehouse_order/document are not folded into
// TicketLinkEntityType above.
const CUSTOMER_PORTAL_LINK_ENTITY_TYPE_LABELS: Record<TicketPortalLinkEntityType, string> = {
  warehouse_order: "Warehouse order",
  document: "Document",
};

const CUSTOMER_LINK_RELATIONSHIP_LABELS: Record<TicketLinkRelationship, string> = {
  primary_subject: "Primary subject",
  related: "Related",
  affected: "Affected",
  context: "Context",
};

type LinkBoundAction = (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;

// A narrower customer-facing counterpart to the staff LinkedRecordsSection
// (ticket-detail-panel.tsx) -- same shared RPCs underneath (app.
// search_ticket_link_candidates/app.link_ticket_record/app.
// unlink_ticket_record/app.list_ticket_links), but scoped to the
// customer-safe entity types (shipment/invoice/warehouse/customer -- never
// vendor/user, decision 7 of the migration), which the server independently
// enforces regardless of what this component offers.
function CustomerLinkedRecordsSection({
  links,
  searchAction,
  linkAction,
  unlinkAction,
}: {
  links: readonly TicketLinkRow[];
  searchAction: (prevState: CustomerTicketLinkSearchActionState, formData: FormData) => Promise<CustomerTicketLinkSearchActionState>;
  linkAction: (entityType: TicketLinkEntityType, entityId: string, relationship: TicketLinkRelationship) => LinkBoundAction;
  unlinkAction: (linkId: string, expectedVersion: number) => LinkBoundAction;
}) {
  const [searchState, searchFormAction, searchPending] = useActionState(searchAction, { error: null, entityType: null, relationship: "related", results: [] } as CustomerTicketLinkSearchActionState);
  const linkedEntityIds = new Set(links.filter((l) => l.entityType === searchState.entityType).map((l) => l.entityId));

  return (
    <section aria-label="Linked records" className="flex flex-col gap-3">
      <h2 className="text-sm font-semibold text-neutral-900">Linked records</h2>
      <p className="text-xs text-neutral-500">Shipments, invoices, warehouses, and your account referenced by this ticket.</p>

      {links.length === 0 ? (
        <p className="text-xs text-neutral-500">No records linked yet.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {links.map((l) => (
            <CustomerLinkedRecordRow key={l.id} link={l} unlinkAction={unlinkAction} />
          ))}
        </ul>
      )}

      <form action={searchFormAction} className="flex flex-col gap-2 rounded bg-neutral-50 p-2">
        <h3 className="text-xs font-semibold text-neutral-700">Find a record to link</h3>
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Record type
            <select name="entityType" required defaultValue={searchState.entityType ?? ""} className="rounded border border-neutral-300 p-1.5 text-xs">
              <option value="" disabled>
                Select…
              </option>
              {TICKET_LINK_CUSTOMER_SAFE_ENTITY_TYPES.map((t) => (
                <option key={t} value={t}>
                  {CUSTOMER_LINK_ENTITY_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Relationship
            <select name="relationship" defaultValue={searchState.relationship} className="rounded border border-neutral-300 p-1.5 text-xs">
              {TICKET_LINK_RELATIONSHIPS.map((r) => (
                <option key={r} value={r}>
                  {CUSTOMER_LINK_RELATIONSHIP_LABELS[r]}
                </option>
              ))}
            </select>
          </label>
          <input name="searchText" placeholder="Search by number/name…" className="min-w-[12rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
          <Button type="submit" variant="secondary" loading={searchPending} loadingLabel="Searching…">
            Search
          </Button>
        </div>
        {searchState.error ? (
          <p role="alert" className="text-xs text-danger">
            {searchState.error}
          </p>
        ) : null}
        {searchState.entityType ? (
          searchState.results.length === 0 ? (
            <p className="text-xs text-neutral-500">No matching records found on your account.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {searchState.results.map((c) => (
                <CustomerLinkCandidateRow
                  key={c.entityId}
                  candidate={c}
                  alreadyLinked={linkedEntityIds.has(c.entityId)}
                  linkAction={linkAction(searchState.entityType as TicketLinkEntityType, c.entityId, searchState.relationship)}
                />
              ))}
            </ul>
          )
        ) : null}
      </form>
    </section>
  );
}

function CustomerLinkedRecordRow({ link, unlinkAction }: { link: TicketLinkRow; unlinkAction: (linkId: string, expectedVersion: number) => LinkBoundAction }) {
  const [state, formAction, pending] = useActionState(unlinkAction(link.id, link.recordVersion), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-1 rounded border border-neutral-100 p-2 text-xs">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="neutral" label={CUSTOMER_LINK_ENTITY_TYPE_LABELS[link.entityType]} />
        {link.liveAvailable ? (
          <>
            <span className="font-medium text-neutral-900">{link.label}</span>
            {link.detail ? <span className="text-neutral-500">— {link.detail}</span> : null}
          </>
        ) : (
          <StatusBadge tone="warning" label="Unavailable" />
        )}
      </div>
      <form action={formAction} className="flex items-center gap-2">
        <input name="reason" required placeholder="Unlink reason (required)" className="min-w-[10rem] rounded border border-neutral-300 p-1 text-xs" />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Unlinking…">
          Unlink
        </Button>
      </form>
      {state.error ? (
        <p role="alert" className="text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

function CustomerLinkCandidateRow({
  candidate,
  alreadyLinked,
  linkAction,
}: {
  candidate: { entityId: string; primaryLabel: string; secondaryLabel: string | null; statusLabel: string | null };
  alreadyLinked: boolean;
  linkAction: LinkBoundAction;
}) {
  const [state, formAction, pending] = useActionState(linkAction, INITIAL_STATE);
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 rounded bg-white p-1.5 text-xs">
      <div>
        <span className="font-medium text-neutral-900">{candidate.primaryLabel}</span>
        {candidate.secondaryLabel ? <span className="text-neutral-500"> — {candidate.secondaryLabel}</span> : null}
      </div>
      <form action={formAction}>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Linking…" disabled={alreadyLinked}>
          {alreadyLinked ? "Already linked" : "Link"}
        </Button>
      </form>
      {state.error ? (
        <p role="alert" className="w-full text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

// CPL-313: a SEPARATE section for the SEPARATE app.ticket_portal_links
// registry (warehouse_order/document) -- mirrors CustomerLinkedRecordsSection
// above structurally, but calls the SEPARATE search/link/unlink RPCs
// (app.search_ticket_portal_link_candidates/app.link_ticket_portal_record/
// app.unlink_ticket_portal_record/app.list_ticket_portal_links). Rendered as
// its own section, never merged into the list above -- the two registries
// remain genuinely separate all the way to the UI.
function CustomerPortalLinkedRecordsSection({
  links,
  searchAction,
  linkAction,
  unlinkAction,
}: {
  links: readonly TicketPortalLinkRow[];
  searchAction: (prevState: CustomerTicketPortalLinkSearchActionState, formData: FormData) => Promise<CustomerTicketPortalLinkSearchActionState>;
  linkAction: (entityType: TicketPortalLinkEntityType, entityId: string, relationship: TicketLinkRelationship) => LinkBoundAction;
  unlinkAction: (linkId: string, expectedVersion: number) => LinkBoundAction;
}) {
  const [searchState, searchFormAction, searchPending] = useActionState(searchAction, { error: null, entityType: null, relationship: "related", results: [] } as CustomerTicketPortalLinkSearchActionState);
  const linkedEntityIds = new Set(links.filter((l) => l.entityType === searchState.entityType).map((l) => l.entityId));

  return (
    <section aria-label="Linked warehouse orders and documents" className="flex flex-col gap-3">
      <h2 className="text-sm font-semibold text-neutral-900">Linked warehouse orders &amp; documents</h2>
      <p className="text-xs text-neutral-500">Warehouse orders and documents (quote attachments, ePOD evidence) referenced by this ticket.</p>

      {links.length === 0 ? (
        <p className="text-xs text-neutral-500">None linked yet.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {links.map((l) => (
            <CustomerPortalLinkedRecordRow key={l.id} link={l} unlinkAction={unlinkAction} />
          ))}
        </ul>
      )}

      <form action={searchFormAction} className="flex flex-col gap-2 rounded bg-neutral-50 p-2">
        <h3 className="text-xs font-semibold text-neutral-700">Find a record to link</h3>
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Record type
            <select name="entityType" required defaultValue={searchState.entityType ?? ""} className="rounded border border-neutral-300 p-1.5 text-xs">
              <option value="" disabled>
                Select…
              </option>
              {TICKET_PORTAL_LINK_ENTITY_TYPES.map((t) => (
                <option key={t} value={t}>
                  {CUSTOMER_PORTAL_LINK_ENTITY_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Relationship
            <select name="relationship" defaultValue={searchState.relationship} className="rounded border border-neutral-300 p-1.5 text-xs">
              {TICKET_LINK_RELATIONSHIPS.map((r) => (
                <option key={r} value={r}>
                  {CUSTOMER_LINK_RELATIONSHIP_LABELS[r]}
                </option>
              ))}
            </select>
          </label>
          <input name="searchText" placeholder="Search by number/name…" className="min-w-[12rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
          <Button type="submit" variant="secondary" loading={searchPending} loadingLabel="Searching…">
            Search
          </Button>
        </div>
        {searchState.error ? (
          <p role="alert" className="text-xs text-danger">
            {searchState.error}
          </p>
        ) : null}
        {searchState.entityType ? (
          searchState.results.length === 0 ? (
            <p className="text-xs text-neutral-500">No matching records found on your account.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {searchState.results.map((c) => (
                <CustomerLinkCandidateRow
                  key={c.entityId}
                  candidate={c}
                  alreadyLinked={linkedEntityIds.has(c.entityId)}
                  linkAction={linkAction(searchState.entityType as TicketPortalLinkEntityType, c.entityId, searchState.relationship)}
                />
              ))}
            </ul>
          )
        ) : null}
      </form>
    </section>
  );
}

function CustomerPortalLinkedRecordRow({ link, unlinkAction }: { link: TicketPortalLinkRow; unlinkAction: (linkId: string, expectedVersion: number) => LinkBoundAction }) {
  const [state, formAction, pending] = useActionState(unlinkAction(link.id, link.recordVersion), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-1 rounded border border-neutral-100 p-2 text-xs">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="neutral" label={CUSTOMER_PORTAL_LINK_ENTITY_TYPE_LABELS[link.entityType]} />
        {link.liveAvailable ? (
          <>
            <span className="font-medium text-neutral-900">{link.label}</span>
            {link.detail ? <span className="text-neutral-500">— {link.detail}</span> : null}
          </>
        ) : (
          <StatusBadge tone="warning" label="Unavailable" />
        )}
      </div>
      <form action={formAction} className="flex items-center gap-2">
        <input name="reason" required placeholder="Unlink reason (required)" className="min-w-[10rem] rounded border border-neutral-300 p-1 text-xs" />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Unlinking…">
          Unlink
        </Button>
      </form>
      {state.error ? (
        <p role="alert" className="text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

// CPL-313: SLA target/status, sourced ONLY from app.get_ticket_sla_status_
// for_requester (HRT-289, already-VERIFIED) -- never a second, invented SLA
// source. `slaStatus === null` means no SLA clock has been started for this
// ticket yet (the common case immediately after a customer files a new
// ticket, before staff triage) -- rendered as an honest "not yet tracked"
// state, never a fabricated target/countdown.
const SLA_PHASE_TONE: Record<"pending" | "met" | "breached", StatusTone> = {
  pending: "info",
  met: "success",
  breached: "danger",
};

function SlaStatusSection({ slaStatus }: { slaStatus: TicketSlaStatusForRequesterRow | null }) {
  if (!slaStatus) {
    return (
      <div className="rounded bg-neutral-50 p-2 text-xs text-neutral-500">
        <span className="font-medium text-neutral-700">Service level: </span>
        Not yet tracked -- a target is assigned once your ticket is triaged.
      </div>
    );
  }
  return (
    <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-4">
      <div>
        <dt className="font-medium">Response target</dt>
        <dd className="flex items-center gap-1">
          {slaStatus.responseTargetMinutes} min <StatusBadge tone={SLA_PHASE_TONE[slaStatus.responseStatus]} label={slaStatus.responseStatus} />
        </dd>
      </div>
      <div>
        <dt className="font-medium">Resolution target</dt>
        <dd className="flex items-center gap-1">
          {slaStatus.resolutionTargetMinutes} min <StatusBadge tone={SLA_PHASE_TONE[slaStatus.resolutionStatus]} label={slaStatus.resolutionStatus} />
        </dd>
      </div>
    </dl>
  );
}

// ISS-2026-101 (Track B Batch 6): sourced ONLY from
// app.get_ticket_escalation_status_for_requester (HRT-291, already-VERIFIED)
// -- never derived from the staff-only get_ticket_escalation. A single
// boolean by construction (decision 12) -- no level/target/trigger/
// hierarchy can leak here because the RPC itself never returns one.
// `escalationStatus === null` covers both "not escalated" and "ticket not
// found/not a party" (the RPC returns no row for either) -- rendered as
// simply omitting the badge, mirroring SlaStatusSection's own
// no-fabricated-state discipline.
function EscalationBadge({ escalationStatus }: { escalationStatus: TicketEscalationStatusForRequesterRow | null }) {
  if (!escalationStatus?.isEscalated) {
    return null;
  }
  return <StatusBadge tone="warning" label="Escalated" />;
}

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

// Client-side convenience mirror of the subset of app.ticket_status_
// transitions that are requester_allowed (cancel, reopen) -- the SERVER
// (app.transition_ticket_status, via app._ticket_transition_authority) is
// the real, enforcing source of truth; this only decides which button to
// offer so a customer is not routinely shown a control that would just come
// back as insufficient_authority/invalid_transition.
function nextCustomerActions(status: TicketStatus): readonly { toStatus: TicketStatus; label: string; requiresReason: boolean }[] {
  if (status === "new" || status === "open" || status === "pending" || status === "on_hold") {
    return [{ toStatus: "cancelled", label: "Cancel ticket", requiresReason: true }];
  }
  if (status === "resolved" || status === "closed") {
    return [{ toStatus: "open", label: "Reopen ticket", requiresReason: true }];
  }
  return [];
}

type BoundAction = (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;

function MessageBubble({ message }: { message: CustomerTicketMessageRow }) {
  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-500">
        <span>{message.authorRole === "staff" ? message.authorDisplay : "You"}</span>
        <span>{new Date(message.createdAt).toLocaleString()}</span>
      </div>
      <p className="whitespace-pre-wrap text-sm text-neutral-900">{message.body}</p>
    </li>
  );
}

function ReplyForm({ replyAction }: { replyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(replyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <label className="text-xs text-neutral-500">
        Add a reply
        <textarea name="body" required minLength={1} rows={3} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div>
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Sending…">
          Send
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

function TransitionForm({ toStatus, label, requiresReason, transitionAction }: { toStatus: TicketStatus; label: string; requiresReason: boolean; transitionAction: (toStatus: TicketStatus) => BoundAction }) {
  const [state, formAction, pending] = useActionState(transitionAction(toStatus), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      {requiresReason ? <input name="reason" required placeholder="Reason (required)" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" /> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…">
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

// CPL-313 (Complaint and Ticket): closure confirmation UX. app.ticket_
// status_transitions (HRT-286) does NOT mark resolved->closed
// requester_allowed -- only staff may actually close a ticket (a canonical
// Ticketing lifecycle decision this checkpoint's own bounded scope does not
// reopen or widen). "Closure confirmation" from the portal side is
// therefore this explicit, disclosed banner plus the ALREADY-existing
// reopen action below (requester_allowed=true for resolved/closed->open) --
// a customer who does NOT reopen is treated as having implicitly confirmed
// the resolution; a customer who disagrees has a real, working action.
function ClosureConfirmationBanner({ status }: { status: TicketStatus }) {
  if (status === "resolved") {
    return (
      <p className="rounded bg-info/10 p-2 text-xs text-neutral-700">
        This ticket has been marked resolved. If the resolution above solves your issue, no action is needed -- our team will close it. If it does not, use <span className="font-medium">Reopen ticket</span> below and tell us why.
      </p>
    );
  }
  if (status === "closed") {
    return (
      <p className="rounded bg-neutral-50 p-2 text-xs text-neutral-500">
        This ticket is closed. If your issue returns or was not fully resolved, use <span className="font-medium">Reopen ticket</span> below.
      </p>
    );
  }
  return null;
}

export function CustomerTicketDetailPanel({
  detail,
  messages,
  replyAction,
  transitionAction,
  slaStatus,
  escalationStatus,
  ticketLinks,
  searchTicketLinksAction,
  linkTicketRecordAction,
  unlinkTicketRecordAction,
  ticketPortalLinks,
  searchTicketPortalLinksAction,
  linkTicketPortalRecordAction,
  unlinkTicketPortalRecordAction,
}: {
  detail: CustomerTicketDetail;
  messages: readonly CustomerTicketMessageRow[];
  replyAction: BoundAction;
  transitionAction: (toStatus: TicketStatus) => BoundAction;
  slaStatus: TicketSlaStatusForRequesterRow | null;
  escalationStatus: TicketEscalationStatusForRequesterRow | null;
  ticketLinks: readonly TicketLinkRow[];
  searchTicketLinksAction: (prevState: CustomerTicketLinkSearchActionState, formData: FormData) => Promise<CustomerTicketLinkSearchActionState>;
  linkTicketRecordAction: (entityType: TicketLinkEntityType, entityId: string, relationship: TicketLinkRelationship) => LinkBoundAction;
  unlinkTicketRecordAction: (linkId: string, expectedVersion: number) => LinkBoundAction;
  ticketPortalLinks: readonly TicketPortalLinkRow[];
  searchTicketPortalLinksAction: (prevState: CustomerTicketPortalLinkSearchActionState, formData: FormData) => Promise<CustomerTicketPortalLinkSearchActionState>;
  linkTicketPortalRecordAction: (entityType: TicketPortalLinkEntityType, entityId: string, relationship: TicketLinkRelationship) => LinkBoundAction;
  unlinkTicketPortalRecordAction: (linkId: string, expectedVersion: number) => LinkBoundAction;
}) {
  const actions = nextCustomerActions(detail.status);

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-lg font-semibold text-neutral-900">{detail.ticketNumber}</h1>
          <StatusBadge tone={STATUS_TONE[detail.status]} label={detail.status.replace(/_/g, " ")} />
          <EscalationBadge escalationStatus={escalationStatus} />
        </div>
        <p className="text-sm text-neutral-700">{detail.subject}</p>
        <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-4">
          <div>
            <dt className="font-medium">Category</dt>
            <dd>{detail.categoryName}</dd>
          </div>
          <div>
            <dt className="font-medium">Priority</dt>
            <dd>{detail.priority}</dd>
          </div>
          <div>
            <dt className="font-medium">Account</dt>
            <dd>{detail.accountName}</dd>
          </div>
          <div>
            <dt className="font-medium">Updated</dt>
            <dd>{new Date(detail.updatedAt).toLocaleString()}</dd>
          </div>
        </dl>
        <SlaStatusSection slaStatus={slaStatus} />
        {detail.resolutionSummary ? (
          <p className="rounded bg-success/10 p-2 text-sm text-neutral-800">
            <span className="font-medium">Resolution: </span>
            {detail.resolutionSummary}
          </p>
        ) : null}
        <ClosureConfirmationBanner status={detail.status} />
        {actions.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {actions.map((a) => (
              <TransitionForm key={a.toStatus} toStatus={a.toStatus} label={a.label} requiresReason={a.requiresReason} transitionAction={transitionAction} />
            ))}
          </div>
        ) : null}
      </header>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Conversation</h2>
        <ul className="flex flex-col gap-2">
          {messages.map((m) => (
            <MessageBubble key={m.id} message={m} />
          ))}
        </ul>
        {detail.status !== "cancelled" ? <ReplyForm replyAction={replyAction} /> : <p className="text-xs text-neutral-500">This ticket is cancelled and can no longer receive new messages.</p>}
      </section>

      <CustomerLinkedRecordsSection
        links={ticketLinks}
        searchAction={searchTicketLinksAction}
        linkAction={linkTicketRecordAction}
        unlinkAction={unlinkTicketRecordAction}
      />

      <CustomerPortalLinkedRecordsSection
        links={ticketPortalLinks}
        searchAction={searchTicketPortalLinksAction}
        linkAction={linkTicketPortalRecordAction}
        unlinkAction={unlinkTicketPortalRecordAction}
      />
    </div>
  );
}
