"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { EMPLOYMENT_TYPES, type EmployeeLifecycleStatus, type EmployeeProfile, type EmployeeEmergencyContact, type EmployeeLifecycleEvent, type EmployeeDuplicateCandidate, type EmployeeChangeRequest } from "../../../../../../server/contracts/employee/employee.ts";
import type { File as HrisFile } from "../../../../../../server/contracts/document/document.ts";
import type { EmployeeActionState } from "../actions.ts";

const INITIAL_STATE: EmployeeActionState = { error: null };

const STATUS_TONE: Record<EmployeeLifecycleStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  approved: "info",
  active: "success",
  on_leave: "warning",
  suspended: "warning",
  terminated: "danger",
  archived: "neutral",
};

type BoundAction = (prevState: EmployeeActionState, formData: FormData) => Promise<EmployeeActionState>;

type OrgUnit = { id: string; name: string; unitType: string };

/**
 * Generic `useActionState`-backed form wrapper for the sites below that need custom
 * field layout rather than the fixed `ActionForm`/`ReasonActionForm` shapes -- React
 * 19's `<form action={fn}>` requires a single-argument `(formData) => void` function,
 * never the two-argument `(prevState, formData)` signature `useActionState` itself
 * consumes, so every raw form below is wrapped here rather than passed a `BoundAction`
 * directly.
 */
function FormWithState({ action, className, children }: { action: BoundAction; className?: string; children: (pending: boolean, error: string | null) => React.ReactNode }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className={className}>
      {children(pending, state.error)}
    </form>
  );
}

/** Small, reusable action-button form -- every lifecycle transition below is one of these. */
function ActionForm({ action, label, variant = "secondary", confirmReason, extraFields }: { action: BoundAction; label: string; variant?: "primary" | "secondary" | "destructive"; confirmReason?: string; extraFields?: React.ReactNode }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      {extraFields}
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Working…" onClick={confirmReason ? (e) => { if (!confirm(confirmReason)) e.preventDefault(); } : undefined}>
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

function ReasonActionForm({ action, label, variant = "secondary", reasonLabel = "Reason", requireReason = true, extraDateField }: { action: BoundAction; label: string; variant?: "primary" | "secondary" | "destructive"; reasonLabel?: string; requireReason?: boolean; extraDateField?: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2">
      <label className="text-xs font-medium text-neutral-600">
        {reasonLabel}
        <input name="reason" type="text" required={requireReason} className="mt-1 block w-full rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      </label>
      {extraDateField ? (
        <label className="text-xs font-medium text-neutral-600">
          Effective date
          <input name="employmentEndDate" type="date" required className="mt-1 block w-full rounded-md border border-neutral-300 px-2 py-1 text-sm" />
        </label>
      ) : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Working…">
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

function LifecycleActions({
  status,
  submitAction,
  activateAction,
  startLeaveAction,
  endLeaveAction,
  suspendAction,
  reactivateAction,
  terminateAction,
  reactivateAccessAction,
  archiveAction,
}: {
  status: EmployeeLifecycleStatus;
  submitAction: BoundAction;
  activateAction: BoundAction;
  startLeaveAction: BoundAction;
  endLeaveAction: BoundAction;
  suspendAction: BoundAction;
  reactivateAction: BoundAction;
  terminateAction: BoundAction;
  reactivateAccessAction: BoundAction;
  archiveAction: BoundAction;
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {status === "draft" ? <ActionForm action={submitAction} label="Submit for approval" variant="primary" /> : null}
      {status === "approved" ? <ActionForm action={activateAction} label="Activate" variant="primary" /> : null}
      {status === "active" ? <ActionForm action={startLeaveAction} label="Start leave" /> : null}
      {status === "on_leave" ? <ActionForm action={endLeaveAction} label="End leave" variant="primary" /> : null}
      {(status === "active" || status === "on_leave") ? <ReasonActionForm action={suspendAction} label="Suspend" variant="destructive" reasonLabel="Suspension reason (required)" /> : null}
      {status === "suspended" ? <ActionForm action={reactivateAction} label="Reactivate" variant="primary" /> : null}
      {(status === "active" || status === "on_leave" || status === "suspended") ? (
        <ReasonActionForm action={terminateAction} label="Terminate" variant="destructive" reasonLabel="Termination reason (required)" extraDateField />
      ) : null}
      {/* HRT-295 (ISS-2026-108 fix, Tier C review wiring): restores a REHIRED
          employee's own Platform/ESS/MSS access -- app.reactivate_user_after_rehire
          requires the employee's CURRENT status to already be 'active' (mirroring
          this same gate here) AND a real, on-file terminated->active rehire event;
          there is no client-visible signal distinguishing "a normal always-active
          employee" from "a rehired employee whose access is still revoked" (the
          RPC itself is the only source of truth for that), so this action is
          offered alongside "Start leave" for every active employee and the RPC's
          own real, already-tested validation (no_rehire_event) surfaces plainly to
          the caller when it does not apply -- never a silent, always-hidden dead
          feature. */}
      {status === "active" ? (
        <ReasonActionForm action={reactivateAccessAction} label="Restore Platform access (rehire)" reasonLabel="Rehire access restoration reason (required)" />
      ) : null}
      {(status === "draft" || status === "submitted" || status === "approved" || status === "terminated") ? <ReasonActionForm action={archiveAction} label="Archive" reasonLabel="Archive reason (optional)" requireReason={false} /> : null}
    </div>
  );
}

/** Unsaved-change protection: the exact real `beforeunload` pattern
 * app/(tenant)/[tenantSlug]/finance/config/finance-config-forms.tsx already
 * established -- a browser-native "leave site?" prompt while any field has
 * diverged from its last-saved value, cleared once the save action completes
 * without error. */
function EmployeeEditForm({ profile, orgUnits, action }: { profile: EmployeeProfile; orgUnits: readonly OrgUnit[]; action: BoundAction }) {
  const initial = {
    fullName: profile.fullName,
    employmentType: profile.employmentType,
    workEmail: profile.workEmail ?? "",
    personalEmail: profile.personalEmail ?? "",
    personalPhone: profile.personalPhone ?? "",
    nationalIdNumber: profile.nationalIdNumber ?? "",
    dateOfBirth: profile.dateOfBirth ?? "",
    gender: profile.gender ?? "",
    hireDate: profile.hireDate ?? "",
    probationEndDate: profile.probationEndDate ?? "",
    companyOrgUnitId: profile.companyOrgUnitId ?? "",
    branchOrgUnitId: profile.branchOrgUnitId ?? "",
    departmentOrgUnitId: profile.departmentOrgUnitId ?? "",
    positionTitle: profile.positionTitle ?? "",
    managerEmployeeId: profile.managerEmployeeId ?? "",
  };
  const [values, setValues] = useState(initial);
  const [savedValues, setSavedValues] = useState(initial);
  const dirty = JSON.stringify(values) !== JSON.stringify(savedValues);
  const valuesRef = useRef(values);
  const wasPendingRef = useRef(false);
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [dirty]);

  useEffect(() => {
    if (wasPendingRef.current && !pending && state.error === null) {
      setSavedValues(valuesRef.current);
    }
    wasPendingRef.current = pending;
  }, [pending, state.error]);

  function field<K extends keyof typeof values>(key: K) {
    return { value: values[key], onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setValues((v) => ({ ...v, [key]: e.target.value })) };
  }

  return (
    <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      {dirty ? <p className="col-span-full text-xs text-warning">You have unsaved changes.</p> : null}
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Full name
        <input name="fullName" type="text" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("fullName")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Employment type
        <select name="employmentType" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("employmentType")}>
          {EMPLOYMENT_TYPES.map((t) => (
            <option key={t} value={t}>
              {t.replace(/_/g, " ")}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Work email
        <input name="workEmail" type="email" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("workEmail")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Personal email
        <input name="personalEmail" type="email" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("personalEmail")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Personal phone
        <input name="personalPhone" type="tel" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("personalPhone")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        National ID number
        <input name="nationalIdNumber" type="text" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("nationalIdNumber")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Date of birth
        <input name="dateOfBirth" type="date" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("dateOfBirth")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Gender
        <input name="gender" type="text" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("gender")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Hire date
        <input name="hireDate" type="date" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("hireDate")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Probation end date
        <input name="probationEndDate" type="date" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("probationEndDate")} />
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Company
        <select name="companyOrgUnitId" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("companyOrgUnitId")}>
          <option value="">—</option>
          {orgUnits.filter((u) => u.unitType === "company").map((u) => (
            <option key={u.id} value={u.id}>
              {u.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Branch
        <select name="branchOrgUnitId" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("branchOrgUnitId")}>
          <option value="">—</option>
          {orgUnits.filter((u) => u.unitType === "branch").map((u) => (
            <option key={u.id} value={u.id}>
              {u.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Department
        <select name="departmentOrgUnitId" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("departmentOrgUnitId")}>
          <option value="">—</option>
          {orgUnits.filter((u) => u.unitType === "department").map((u) => (
            <option key={u.id} value={u.id}>
              {u.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
        Position title
        <input name="positionTitle" type="text" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" {...field("positionTitle")} />
      </label>

      {state.error ? (
        <p role="alert" className="col-span-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <div className="col-span-full">
        <Button type="submit" loading={pending} loadingLabel="Saving…">
          Save changes
        </Button>
      </div>
    </form>
  );
}

export function EmployeeDetailPanel({
  tenantSlug,
  profile,
  contacts,
  history,
  duplicates,
  files,
  changeRequests,
  orgUnits,
  updateDraftAction,
  submitAction,
  decideApprovalAction,
  activateAction,
  linkUserAction,
  startLeaveAction,
  endLeaveAction,
  suspendAction,
  reactivateAction,
  terminateAction,
  reactivateAccessAction,
  archiveAction,
  transferAction,
  addContactAction,
  removeContactAction,
  decideDuplicateAction,
  decideChangeRequestAction,
}: {
  tenantSlug: string;
  profile: EmployeeProfile;
  contacts: readonly EmployeeEmergencyContact[];
  history: readonly EmployeeLifecycleEvent[];
  duplicates: readonly EmployeeDuplicateCandidate[];
  files: readonly HrisFile[];
  changeRequests: readonly EmployeeChangeRequest[];
  orgUnits: readonly OrgUnit[];
  updateDraftAction: BoundAction;
  submitAction: BoundAction;
  decideApprovalAction: BoundAction;
  activateAction: BoundAction;
  linkUserAction: BoundAction;
  startLeaveAction: BoundAction;
  endLeaveAction: BoundAction;
  suspendAction: BoundAction;
  reactivateAction: BoundAction;
  terminateAction: BoundAction;
  reactivateAccessAction: BoundAction;
  archiveAction: BoundAction;
  transferAction: BoundAction;
  addContactAction: BoundAction;
  removeContactAction: (contactId: string, expectedVersion: number) => BoundAction;
  decideDuplicateAction: (candidateId: string, expectedVersion: number) => BoundAction;
  decideChangeRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  const [tab, setTab] = useState<"personal" | "employment" | "organization" | "documents" | "history">("personal");
  const orgUnitName = (id: string | null) => (id ? orgUnits.find((u) => u.id === id)?.name ?? id : "—");
  const pendingDuplicates = duplicates.filter((d) => d.decision === "pending");
  const pendingChangeRequests = changeRequests.filter((r) => r.status === "pending");

  const TABS: { key: typeof tab; label: string }[] = [
    { key: "personal", label: "Personal" },
    { key: "employment", label: "Employment" },
    { key: "organization", label: "Organization" },
    { key: "documents", label: "Documents" },
    { key: "history", label: "History" },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            {profile.fullName} <span className="text-sm font-normal text-neutral-500">({profile.employeeNumber})</span>
          </h1>
          <div className="mt-1 flex items-center gap-2">
            <StatusBadge tone={STATUS_TONE[profile.lifecycleStatus]} label={profile.lifecycleStatus.replace(/_/g, " ")} />
            {profile.userId ? <span className="text-xs text-neutral-500">Linked to a Platform user</span> : <span className="text-xs text-warning">No Platform user linked yet</span>}
          </div>
        </div>
        <a href={`/${tenantSlug}/hris/employees`} className="text-sm text-primary underline">
          Back to directory
        </a>
      </div>

      {pendingDuplicates.length > 0 ? (
        <div role="alert" className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-neutral-900">
          {pendingDuplicates.length} unresolved duplicate candidate(s) block submission for approval until reviewed.
        </div>
      ) : null}

      <LifecycleActions
        status={profile.lifecycleStatus}
        submitAction={submitAction}
        activateAction={activateAction}
        startLeaveAction={startLeaveAction}
        endLeaveAction={endLeaveAction}
        suspendAction={suspendAction}
        reactivateAction={reactivateAction}
        terminateAction={terminateAction}
        reactivateAccessAction={reactivateAccessAction}
        archiveAction={archiveAction}
      />

      <div role="tablist" aria-label="Employee detail sections" className="flex gap-1 border-b border-neutral-200">
        {TABS.map((t) => (
          <button
            key={t.key}
            role="tab"
            id={`tab-${t.key}`}
            aria-selected={tab === t.key}
            aria-controls={`panel-${t.key}`}
            tabIndex={tab === t.key ? 0 : -1}
            onClick={() => setTab(t.key)}
            className={`rounded-t-md px-3 py-2 text-sm font-medium ${tab === t.key ? "border-b-2 border-primary text-primary" : "text-neutral-600 hover:text-neutral-900"}`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === "personal" ? (
        <div id="panel-personal" role="tabpanel" aria-labelledby="tab-personal" className="flex flex-col gap-4">
          {profile.personalDataMasked ? (
            <p className="rounded-md border border-neutral-200 bg-neutral-50 p-2 text-xs text-neutral-600">
              Sensitive personal fields are masked. You need HRS:View personal data to see them, or this must be your own linked profile.
            </p>
          ) : null}
          <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div>
              <dt className="text-xs text-neutral-500">Personal email</dt>
              <dd className="text-sm">{profile.personalDataMasked ? "•••• (masked)" : profile.personalEmail ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Personal phone</dt>
              <dd className="text-sm">{profile.personalDataMasked ? "•••• (masked)" : profile.personalPhone ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">National ID number</dt>
              <dd className="text-sm">{profile.personalDataMasked ? "•••• (masked)" : profile.nationalIdNumber ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Date of birth</dt>
              <dd className="text-sm">{profile.personalDataMasked ? "•••• (masked)" : profile.dateOfBirth ?? "—"}</dd>
            </div>
            <div className="sm:col-span-2">
              <dt className="text-xs text-neutral-500">Personal address</dt>
              <dd className="text-sm">
                {profile.personalDataMasked
                  ? "•••• (masked)"
                  : [profile.personalAddressStreet, profile.personalAddressCity, profile.personalAddressProvince, profile.personalAddressPostalCode, profile.personalAddressCountry].filter(Boolean).join(", ") || "—"}
              </dd>
            </div>
          </dl>

          <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
            <h2 className="text-sm font-semibold text-neutral-900">Emergency contacts</h2>
            {contacts.length === 0 ? (
              <EmptyState title="No emergency contacts yet" description="Required before this profile can be submitted for approval." />
            ) : (
              <ul className="flex flex-col gap-2">
                {contacts.map((c) => (
                  <li key={c.id} className="flex items-center justify-between rounded-md border border-neutral-100 p-2 text-sm">
                    <span>
                      {c.name} {c.relationship ? `(${c.relationship})` : ""} {c.isPrimary ? <StatusBadge tone="info" label="Primary" /> : null}
                      <br />
                      <span className="text-xs text-neutral-500">{c.phone ?? "•••• (masked)"} {c.email ? `· ${c.email}` : ""}</span>
                    </span>
                    <ActionForm action={removeContactAction(c.id, c.recordVersion)} label="Remove" variant="destructive" />
                  </li>
                ))}
              </ul>
            )}
            <FormWithState action={addContactAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {(pending, error) => (
                <>
                  <input name="name" type="text" placeholder="Name" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                  <input name="relationship" type="text" placeholder="Relationship" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                  <input name="phone" type="tel" placeholder="Phone" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                  <input name="email" type="email" placeholder="Email" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                  <label className="flex items-center gap-1 text-xs text-neutral-600">
                    <input name="isPrimary" type="checkbox" /> Primary
                  </label>
                  <Button type="submit" loading={pending} loadingLabel="Adding…">
                    Add contact
                  </Button>
                  {error ? (
                    <p role="alert" className="col-span-full text-xs text-danger">
                      {error}
                    </p>
                  ) : null}
                </>
              )}
            </FormWithState>
          </section>

          {pendingDuplicates.length > 0 ? (
            <section className="flex flex-col gap-2 rounded-md border border-warning/40 p-3">
              <h2 className="text-sm font-semibold text-neutral-900">Unresolved duplicate candidates</h2>
              <ul className="flex flex-col gap-2">
                {pendingDuplicates.map((d) => (
                  <li key={d.id} className="rounded-md border border-neutral-100 p-2 text-sm">
                    <p className="text-xs text-neutral-500">Basis: {d.similarityBasis} {d.similarityScore != null ? `(score ${d.similarityScore})` : ""}</p>
                    <FormWithState action={decideDuplicateAction(d.id, d.recordVersion)} className="mt-1 flex flex-wrap items-center gap-2">
                      {(pending, error) => (
                        <>
                          <input name="reason" type="text" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                          <Button type="submit" name="decision" value="dismissed" variant="secondary" loading={pending}>
                            Not a duplicate
                          </Button>
                          <Button type="submit" name="decision" value="linked" variant="destructive" loading={pending}>
                            Confirm duplicate
                          </Button>
                          {error ? (
                            <p role="alert" className="w-full text-xs text-danger">
                              {error}
                            </p>
                          ) : null}
                        </>
                      )}
                    </FormWithState>
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          {changeRequests.length > 0 ? (
            <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
              <h2 className="text-sm font-semibold text-neutral-900">Self-service correction requests</h2>
              <ul className="flex flex-col gap-2">
                {changeRequests.map((r) => (
                  <li key={r.id} className="rounded-md border border-neutral-100 p-2 text-sm">
                    <p>
                      <span className="font-medium">{r.fieldKey.replace(/_/g, " ")}</span>: {r.currentValueSnapshot ?? "—"} → {r.requestedValue ?? "—"}
                    </p>
                    {r.reason ? <p className="text-xs text-neutral-500">Reason: {r.reason}</p> : null}
                    <p className="text-xs text-neutral-500">
                      Status: <StatusBadge tone={r.status === "pending" ? "info" : r.status === "approved" ? "success" : "danger"} label={r.status} />
                    </p>
                    {r.status === "pending" ? (
                      <FormWithState action={decideChangeRequestAction(r.id, r.recordVersion)} className="mt-1 flex flex-wrap items-center gap-2">
                        {(pending, error) => (
                          <>
                            <input name="decidedReason" type="text" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                            <Button type="submit" name="decision" value="rejected" variant="secondary" loading={pending}>
                              Reject
                            </Button>
                            <Button type="submit" name="decision" value="approved" variant="primary" loading={pending}>
                              Approve
                            </Button>
                            {error ? (
                              <p role="alert" className="w-full text-xs text-danger">
                                {error}
                              </p>
                            ) : null}
                          </>
                        )}
                      </FormWithState>
                    ) : null}
                  </li>
                ))}
              </ul>
            </section>
          ) : null}
        </div>
      ) : null}

      {tab === "employment" ? (
        <div id="panel-employment" role="tabpanel" aria-labelledby="tab-employment" className="flex flex-col gap-4">
          {profile.lifecycleStatus === "draft" ? (
            <EmployeeEditForm profile={profile} orgUnits={orgUnits} action={updateDraftAction} />
          ) : (
            <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div>
                <dt className="text-xs text-neutral-500">Employment type</dt>
                <dd className="text-sm">{profile.employmentType.replace(/_/g, " ")}</dd>
              </div>
              <div>
                <dt className="text-xs text-neutral-500">Hire date</dt>
                <dd className="text-sm">{profile.hireDate ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-neutral-500">Probation end date</dt>
                <dd className="text-sm">{profile.probationEndDate ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-neutral-500">Employment end date</dt>
                <dd className="text-sm">{profile.employmentEndDate ?? "—"}</dd>
              </div>
              {profile.revisionReason ? (
                <div className="sm:col-span-2">
                  <dt className="text-xs text-neutral-500">Last revision reason</dt>
                  <dd className="text-sm">{profile.revisionReason}</dd>
                </div>
              ) : null}
              <p className="col-span-full text-xs text-neutral-500">Only a draft profile can be edited directly. Use Transfer (Organization tab) to change company/branch/department/position/manager once active.</p>
            </dl>
          )}

          {profile.lifecycleStatus === "submitted" ? (
            <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
              <h2 className="text-sm font-semibold text-neutral-900">Approval decision</h2>
              <FormWithState action={decideApprovalAction} className="flex flex-wrap items-center gap-2">
                {(pending, error) => (
                  <>
                    <input name="reason" type="text" placeholder="Reason (required to reject)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                    <Button type="submit" name="decision" value="reject" variant="destructive" loading={pending}>
                      Reject
                    </Button>
                    <Button type="submit" name="decision" value="approve" variant="primary" loading={pending}>
                      Approve
                    </Button>
                    {error ? (
                      <p role="alert" className="w-full text-xs text-danger">
                        {error}
                      </p>
                    ) : null}
                  </>
                )}
              </FormWithState>
            </section>
          ) : null}

          {!profile.userId && profile.lifecycleStatus !== "terminated" && profile.lifecycleStatus !== "archived" ? (
            <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
              <h2 className="text-sm font-semibold text-neutral-900">Link a Platform user</h2>
              <p className="text-xs text-neutral-500">This profile was created before a Platform user account existed. Link one now to enable self-service access.</p>
              <FormWithState action={linkUserAction} className="flex flex-wrap items-center gap-2">
                {(pending, error) => (
                  <>
                    <input name="userId" type="text" placeholder="Platform user id (uuid)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                    <Button type="submit" loading={pending} loadingLabel="Linking…">
                      Link user
                    </Button>
                    {error ? (
                      <p role="alert" className="w-full text-xs text-danger">
                        {error}
                      </p>
                    ) : null}
                  </>
                )}
              </FormWithState>
            </section>
          ) : null}
        </div>
      ) : null}

      {tab === "organization" ? (
        <div id="panel-organization" role="tabpanel" aria-labelledby="tab-organization" className="flex flex-col gap-4">
          <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div>
              <dt className="text-xs text-neutral-500">Company</dt>
              <dd className="text-sm">{orgUnitName(profile.companyOrgUnitId)}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Branch</dt>
              <dd className="text-sm">{orgUnitName(profile.branchOrgUnitId)}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Department</dt>
              <dd className="text-sm">{orgUnitName(profile.departmentOrgUnitId)}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Position title</dt>
              <dd className="text-sm">{profile.positionTitle ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Manager (employee id)</dt>
              <dd className="text-sm">{profile.managerEmployeeId ?? "—"}</dd>
            </div>
          </dl>

          <div className="rounded-md border border-primary/30 bg-primary/5 p-3">
            <p className="text-sm font-medium text-neutral-900">Governed position, grade and reporting assignment</p>
            <p className="mt-1 text-xs text-neutral-600">
              The free-text transfer below (position title, manager id) is HRT-274&apos;s original, ungoverned quick edit. For a governed position/grade linked to the canonical organization tree, with effective-dated history, capacity
              enforcement and reorganization impact preview, use the assignment timeline page.
            </p>
            <a href={`/${tenantSlug}/hris/employees/${profile.masterRecordId}/positions`} className="mt-2 inline-block text-sm font-medium text-primary underline">
              Open position &amp; assignment timeline
            </a>
          </div>

          {profile.lifecycleStatus !== "terminated" && profile.lifecycleStatus !== "archived" ? (
            <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
              <h2 className="text-sm font-semibold text-neutral-900">Transfer (free-text, ungoverned)</h2>
              <p className="text-xs text-neutral-500">Full before/after history is preserved (see the History tab). Cyclic reporting lines are rejected. Prefer the governed assignment timeline above when a position/grade catalogue exists for this role.</p>
              <FormWithState action={transferAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {(pending, error) => (
                  <>
                    <select name="companyOrgUnitId" defaultValue={profile.companyOrgUnitId ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                      <option value="">Company: —</option>
                      {orgUnits.filter((u) => u.unitType === "company").map((u) => (
                        <option key={u.id} value={u.id}>
                          {u.name}
                        </option>
                      ))}
                    </select>
                    <select name="branchOrgUnitId" defaultValue={profile.branchOrgUnitId ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                      <option value="">Branch: —</option>
                      {orgUnits.filter((u) => u.unitType === "branch").map((u) => (
                        <option key={u.id} value={u.id}>
                          {u.name}
                        </option>
                      ))}
                    </select>
                    <select name="departmentOrgUnitId" defaultValue={profile.departmentOrgUnitId ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                      <option value="">Department: —</option>
                      {orgUnits.filter((u) => u.unitType === "department").map((u) => (
                        <option key={u.id} value={u.id}>
                          {u.name}
                        </option>
                      ))}
                    </select>
                    <input name="positionTitle" type="text" placeholder="Position title" defaultValue={profile.positionTitle ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
                    <input name="managerEmployeeId" type="text" placeholder="Manager employee id (uuid, optional)" defaultValue={profile.managerEmployeeId ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-2" />
                    <input name="reason" type="text" placeholder="Reason (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-2" />
                    {error ? (
                      <p role="alert" className="col-span-full text-xs text-danger">
                        {error}
                      </p>
                    ) : null}
                    <div className="col-span-full">
                      <Button type="submit" loading={pending} loadingLabel="Transferring…">
                        Transfer
                      </Button>
                    </div>
                  </>
                )}
              </FormWithState>
            </section>
          ) : null}
        </div>
      ) : null}

      {tab === "documents" ? (
        <div id="panel-documents" role="tabpanel" aria-labelledby="tab-documents">
          {files.length === 0 ? (
            <EmptyState title="No documents uploaded" description="Employee documents are stored via the private, scanned Document Engine (app.files) -- never a second file table." />
          ) : (
            <ul className="flex flex-col gap-2">
              {files.map((f) => (
                <li key={f.id} className="flex items-center justify-between rounded-md border border-neutral-100 p-2 text-sm">
                  <span>
                    {f.originalFilename} <span className="text-xs text-neutral-500">({f.mimeType}, {Math.round(f.sizeBytes / 1024)} KB)</span>
                  </span>
                  <StatusBadge
                    tone={f.malwareScanStatus === "clean" ? "success" : f.malwareScanStatus === "infected" ? "danger" : "warning"}
                    label={`scan: ${f.malwareScanStatus}`}
                  />
                </li>
              ))}
            </ul>
          )}
          <p className="mt-2 text-xs text-neutral-500">Upload is server-mediated through app.initiate_file_upload (RPD-032 true quarantine) -- not yet wired to a client-side file picker in this checkpoint (residual gap, see the build log).</p>
        </div>
      ) : null}

      {tab === "history" ? (
        <div id="panel-history" role="tabpanel" aria-labelledby="tab-history">
          {history.length === 0 ? (
            <EmptyState title="No lifecycle history yet" />
          ) : (
            <ol className="flex flex-col gap-2 border-l border-neutral-200 pl-4">
              {history.map((e) => (
                <li key={e.id} className="text-sm">
                  <p className="font-medium">
                    {e.fromStatus} → {e.toStatus} <span className="text-xs font-normal text-neutral-500">{new Date(e.occurredAt).toLocaleString()}</span>
                  </p>
                  {e.reason ? <p className="text-xs text-neutral-600">Reason: {e.reason}</p> : null}
                  {e.actorLabel ? <p className="text-xs text-neutral-500">By: {e.actorLabel}</p> : null}
                </li>
              ))}
            </ol>
          )}
        </div>
      ) : null}
    </div>
  );
}
