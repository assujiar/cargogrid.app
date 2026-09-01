"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../components/forms/checkbox.tsx";
import type { CustomerProfileActionState } from "./actions.ts";
import {
  readCustomerProfileProposedValue,
  CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS,
  type CustomerPortalAccountProfile,
  type CustomerPortalAccountContact,
  type CustomerProfileChangeRequest,
  type CustomerProfileBillingAddress,
} from "../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";
import { CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELD_LABELS, type CustomerLegalIdentityChangeRequest, type CustomerLegalIdentityWritableField } from "../../../../server/contracts/customer-portal-legal-identity/customer-portal-legal-identity.ts";
import { CUSTOMER_CONTACT_ROLES, type CustomerContactChangeRequest } from "../../../../server/contracts/customer-portal-contact-change/customer-portal-contact-change.ts";

const INITIAL_STATE: CustomerProfileActionState = { error: null };

const STATUS_TONE: Record<CustomerProfileChangeRequest["status"], StatusTone> = {
  pending: "info",
  approved: "success",
  rejected: "danger",
  withdrawn: "neutral",
};

type BoundAction = (prevState: CustomerProfileActionState, formData: FormData) => Promise<CustomerProfileActionState>;

function billingAddressText(address: Record<string, unknown>): string {
  const parts = [address.line1, address.line2, address.city, address.state, address.postalCode, address.country].filter((v): v is string => typeof v === "string" && v.length > 0);
  return parts.length > 0 ? parts.join(", ") : "Not on file";
}

function LegalIdentityPendingBanner({ request, withdrawAction }: { request: CustomerLegalIdentityChangeRequest; withdrawAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(withdrawAction, INITIAL_STATE);
  const proposedText = typeof request.proposedValue === "string" ? request.proposedValue : "";

  return (
    <div className="flex flex-col gap-2 rounded-md border border-info/30 bg-info/5 p-3 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="info" label="Pending review" />
        <span className="text-neutral-700">
          Requested: <span className="font-medium">{proposedText}</span>
        </span>
      </div>
      <p className="text-xs text-neutral-500">Submitted {new Date(request.createdAt).toLocaleString()}. This is a legal identity correction -- our team reviews it before it takes effect.</p>
      <form action={formAction} className="flex items-center gap-2">
        <input type="hidden" name="requestId" value={request.id} />
        <input type="hidden" name="accountId" value={request.accountId} />
        <input type="hidden" name="expectedVersion" value={request.recordVersion} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Withdrawing…">
          Withdraw
        </Button>
      </form>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </div>
  );
}

/**
 * Legal identity field row (ISS-2026-123 item 1). The field itself is never directly
 * editable -- CustomerProfilePage has no direct-write path to legal_name/tax_id at all -- but
 * unlike the old locked-field copy, a customer can request a correction here, reviewed by
 * staff (COM:Approve, additionally step-up-MFA-gated per tenant policy) before it takes
 * effect on the real app.accounts row.
 */
function LegalIdentityField({
  label,
  fieldName,
  currentValue,
  pendingRequest,
  submitAction,
  withdrawAction,
}: {
  label: string;
  fieldName: CustomerLegalIdentityWritableField;
  currentValue: string;
  pendingRequest: CustomerLegalIdentityChangeRequest | undefined;
  submitAction: BoundAction;
  withdrawAction: BoundAction;
}) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  const fieldId = `legal-identity-${fieldName}`;
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex items-center gap-2">
        <span aria-hidden="true" className="text-neutral-400">
          🔒
        </span>
        <span className="text-xs font-medium text-neutral-500">{label}</span>
      </div>
      <p className="text-sm text-neutral-900">{currentValue || "Not on file"}</p>

      {pendingRequest ? (
        <LegalIdentityPendingBanner request={pendingRequest} withdrawAction={withdrawAction} />
      ) : (
        <form action={formAction} className="flex flex-col gap-2">
          <FormField id={fieldId} label="Request a correction" error={state.error ?? undefined}>
            <Input
              id={fieldId}
              name="proposedValue"
              defaultValue={currentValue}
              placeholder={`Correct ${CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELD_LABELS[fieldName].toLowerCase()}`}
              invalid={Boolean(state.error)}
              aria-describedby={state.error ? `${fieldId}-error` : undefined}
            />
          </FormField>
          <div>
            <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
              Request correction
            </Button>
          </div>
          <p className="text-xs text-neutral-400">A legal name or tax ID correction has compliance implications and is reviewed by our team before it takes effect -- it is never applied immediately.</p>
        </form>
      )}
    </div>
  );
}

function PendingChangeBanner({ request, withdrawAction }: { request: CustomerProfileChangeRequest; withdrawAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(withdrawAction, INITIAL_STATE);
  const proposed = readCustomerProfileProposedValue(request);
  const proposedText = typeof proposed === "string" ? proposed : billingAddressText(proposed);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-info/30 bg-info/5 p-3 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="info" label="Pending review" />
        <span className="text-neutral-700">
          Proposed: <span className="font-medium">{proposedText}</span>
        </span>
      </div>
      <p className="text-xs text-neutral-500">Submitted {new Date(request.createdAt).toLocaleString()}. Your team will review this before it takes effect.</p>
      <form action={formAction} className="flex items-center gap-2">
        <input type="hidden" name="requestId" value={request.id} />
        <input type="hidden" name="accountId" value={request.accountId} />
        <input type="hidden" name="expectedVersion" value={request.recordVersion} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Withdrawing…">
          Withdraw
        </Button>
      </form>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </div>
  );
}

function TradeNameForm({ currentValue, submitAction }: { currentValue: string; submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  const fieldId = "trade-name";
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id={fieldId} label="Trade name" error={state.error ?? undefined}>
        <Input
          id={fieldId}
          name="tradeName"
          defaultValue={currentValue}
          placeholder="e.g. Acme Logistics"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? `${fieldId}-error` : undefined}
        />
      </FormField>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Propose change
        </Button>
      </div>
      <p className="text-xs text-neutral-500">This does not change your trade name immediately -- it submits a request for our team to review.</p>
    </form>
  );
}

function BillingAddressForm({ currentValue, submitAction }: { currentValue: CustomerProfileBillingAddress; submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  const errorId = "billing-address-error";
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-3 sm:grid-cols-2">
      <div className="sm:col-span-2">
        <FormField id="billing-line1" label="Address line 1">
          <Input id="billing-line1" name="billingLine1" defaultValue={typeof currentValue.line1 === "string" ? currentValue.line1 : ""} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <FormField id="billing-line2" label="Address line 2">
          <Input id="billing-line2" name="billingLine2" defaultValue={typeof currentValue.line2 === "string" ? currentValue.line2 : ""} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id="billing-city" label="City">
        <Input id="billing-city" name="billingCity" defaultValue={typeof currentValue.city === "string" ? currentValue.city : ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id="billing-state" label="State/Province">
        <Input id="billing-state" name="billingState" defaultValue={typeof currentValue.state === "string" ? currentValue.state : ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id="billing-postal-code" label="Postal code">
        <Input id="billing-postal-code" name="billingPostalCode" defaultValue={typeof currentValue.postalCode === "string" ? currentValue.postalCode : ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id="billing-country" label="Country">
        <Input id="billing-country" name="billingCountry" defaultValue={typeof currentValue.country === "string" ? currentValue.country : ""} aria-describedby={describedBy} />
      </FormField>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Propose change
        </Button>
      </div>
      <p className="text-xs text-neutral-500 sm:col-span-2">This does not change your billing address immediately -- it submits a request for our team to review.</p>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function ContactChangePendingBanner({ request, withdrawAction, verb }: { request: CustomerContactChangeRequest; withdrawAction: BoundAction; verb: string }) {
  const [state, formAction, pending] = useActionState(withdrawAction, INITIAL_STATE);
  return (
    <div className="flex flex-col gap-2 rounded-md border border-info/30 bg-info/5 p-2 text-xs">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="info" label="Pending review" />
        <span className="text-neutral-700">{verb} pending -- submitted {new Date(request.createdAt).toLocaleString()}</span>
      </div>
      <form action={formAction} className="flex items-center gap-2">
        <input type="hidden" name="requestId" value={request.id} />
        <input type="hidden" name="accountId" value={request.accountId} />
        <input type="hidden" name="expectedVersion" value={request.recordVersion} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Withdrawing…">
          Withdraw
        </Button>
      </form>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </div>
  );
}

function AddContactForm({ submitAction }: { submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  const errorId = "add-contact-error";
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-3 sm:grid-cols-2">
      <p className="text-xs font-semibold text-neutral-900 sm:col-span-2">Request a new contact</p>
      <FormField id="add-contact-full-name" label="Full name">
        <Input id="add-contact-full-name" name="fullName" required aria-describedby={describedBy} />
      </FormField>
      <FormField id="add-contact-title" label="Title">
        <Input id="add-contact-title" name="title" aria-describedby={describedBy} />
      </FormField>
      <FormField id="add-contact-email" label="Email">
        <Input id="add-contact-email" name="email" type="email" aria-describedby={describedBy} />
      </FormField>
      <FormField id="add-contact-phone" label="Phone">
        <Input id="add-contact-phone" name="phone" aria-describedby={describedBy} />
      </FormField>
      <FormField id="add-contact-role" label="Role">
        <Select id="add-contact-role" name="role" defaultValue="other" aria-describedby={describedBy}>
          {CUSTOMER_CONTACT_ROLES.map((role) => (
            <option key={role} value={role}>
              {role}
            </option>
          ))}
        </Select>
      </FormField>
      <Checkbox id="add-contact-is-primary" name="isPrimary" value="true" label="Primary contact" />
      <p className="text-xs text-neutral-400 sm:col-span-2">Provide at least an email or a phone number. This submits a request for our team to review before the contact is added.</p>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Request add
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function ContactEditForm({ contact, submitAction, onCancel }: { contact: CustomerPortalAccountContact; submitAction: BoundAction; onCancel: () => void }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  const idPrefix = `contact-${contact.contactId}`;
  const errorId = `${idPrefix}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 bg-neutral-50 p-3 sm:grid-cols-2">
      <FormField id={`${idPrefix}-full-name`} label="Full name">
        <Input id={`${idPrefix}-full-name`} name="fullName" defaultValue={contact.fullName} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${idPrefix}-title`} label="Title">
        <Input id={`${idPrefix}-title`} name="title" defaultValue={contact.title ?? ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${idPrefix}-email`} label="Email">
        <Input id={`${idPrefix}-email`} name="email" type="email" defaultValue={contact.email ?? ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${idPrefix}-phone`} label="Phone">
        <Input id={`${idPrefix}-phone`} name="phone" defaultValue={contact.phone ?? ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${idPrefix}-role`} label="Role">
        <Select id={`${idPrefix}-role`} name="role" defaultValue={contact.role} aria-describedby={describedBy}>
          {CUSTOMER_CONTACT_ROLES.map((role) => (
            <option key={role} value={role}>
              {role}
            </option>
          ))}
        </Select>
      </FormField>
      <Checkbox id={`${idPrefix}-is-primary`} name="isPrimary" value="true" defaultChecked={contact.isPrimary} label="Primary contact" />
      <p className="text-xs text-neutral-400 sm:col-span-2">Leave a field as-is to keep it unchanged. This submits a request for our team to review before it takes effect.</p>
      <div className="flex gap-2 sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Request update
        </Button>
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function RemoveContactForm({ submitAction }: { submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-end gap-1">
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Submitting…">
        Request removal
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ContactRow({
  contact,
  pendingUpdate,
  pendingRemove,
  updateAction,
  removeAction,
  withdrawAction,
}: {
  contact: CustomerPortalAccountContact;
  pendingUpdate: CustomerContactChangeRequest | undefined;
  pendingRemove: CustomerContactChangeRequest | undefined;
  updateAction: BoundAction;
  removeAction: BoundAction;
  withdrawAction: BoundAction;
}) {
  const [editing, setEditing] = useState(false);
  return (
    <li className="flex flex-col gap-2 rounded border border-neutral-100 p-2 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium text-neutral-900">{contact.fullName}</span>
        {contact.isPrimary ? <StatusBadge tone="info" label="Primary" /> : null}
        <span className="text-xs text-neutral-500">{contact.title ?? "—"}</span>
        <span className="text-xs text-neutral-500">{contact.email ?? "—"}</span>
        <span className="text-xs text-neutral-500">{contact.phone ?? "—"}</span>
      </div>

      {pendingRemove ? (
        <ContactChangePendingBanner request={pendingRemove} withdrawAction={withdrawAction} verb="Removal" />
      ) : pendingUpdate ? (
        <ContactChangePendingBanner request={pendingUpdate} withdrawAction={withdrawAction} verb="Update" />
      ) : editing ? (
        <ContactEditForm contact={contact} submitAction={updateAction} onCancel={() => setEditing(false)} />
      ) : (
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={() => setEditing(true)}>
            Request edit
          </Button>
          <RemoveContactForm submitAction={removeAction} />
        </div>
      )}
    </li>
  );
}

function ContactsSection({
  contacts,
  contactChangeHistory,
  submitAddContactAction,
  contactActions,
  withdrawContactChangeAction,
}: {
  contacts: readonly CustomerPortalAccountContact[];
  contactChangeHistory: readonly CustomerContactChangeRequest[];
  submitAddContactAction: BoundAction;
  contactActions: ReadonlyMap<string, { updateAction: BoundAction; removeAction: BoundAction }>;
  withdrawContactChangeAction: BoundAction;
}) {
  const pendingAdd = contactChangeHistory.find((r) => r.status === "pending" && r.changeKind === "add");

  return (
    <section aria-label="Contacts" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Contacts</h2>
      {contacts.length === 0 ? (
        <EmptyState title="No contacts on file" description="No contacts are linked to this account yet." />
      ) : (
        <ul className="flex flex-col gap-2">
          {contacts.map((c) => {
            const actions = contactActions.get(c.contactId);
            if (!actions) return null;
            const pendingUpdate = contactChangeHistory.find((r) => r.status === "pending" && r.changeKind === "update" && r.targetContactId === c.contactId);
            const pendingRemove = contactChangeHistory.find((r) => r.status === "pending" && r.changeKind === "remove" && r.targetContactId === c.contactId);
            return (
              <ContactRow
                key={c.contactId}
                contact={c}
                pendingUpdate={pendingUpdate}
                pendingRemove={pendingRemove}
                updateAction={actions.updateAction}
                removeAction={actions.removeAction}
                withdrawAction={withdrawContactChangeAction}
              />
            );
          })}
        </ul>
      )}

      {pendingAdd ? (
        <div className="max-w-md">
          <ContactChangePendingBanner request={pendingAdd} withdrawAction={withdrawContactChangeAction} verb="New contact" />
        </div>
      ) : (
        <AddContactForm submitAction={submitAddContactAction} />
      )}
    </section>
  );
}

function HistorySection({ history }: { history: readonly CustomerProfileChangeRequest[] }) {
  return (
    <section aria-label="Change request history" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Change request history</h2>
      {history.length === 0 ? (
        <EmptyState title="No change requests yet" description="Profile change requests you or a colleague submit will appear here." />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <thead>
              <tr className="text-left text-xs font-medium text-neutral-500">
                <th className="p-2">Field</th>
                <th className="p-2">Proposed value</th>
                <th className="p-2">Status</th>
                <th className="p-2">Reviewed</th>
                <th className="p-2">Submitted</th>
              </tr>
            </thead>
            <tbody>
              {history.map((r) => {
                const proposed = readCustomerProfileProposedValue(r);
                const proposedText = typeof proposed === "string" ? proposed : billingAddressText(proposed);
                return (
                  <tr key={r.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm">{CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS[r.fieldName]}</td>
                    <td className="p-2 text-sm">{proposedText}</td>
                    <td className="p-2 text-sm">
                      <StatusBadge tone={STATUS_TONE[r.status]} label={r.status} />
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{r.reviewedAt ? `${new Date(r.reviewedAt).toLocaleString()}${r.reviewReason ? ` — ${r.reviewReason}` : ""}` : "—"}</td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(r.createdAt).toLocaleString()}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function LegalIdentityHistorySection({ history }: { history: readonly CustomerLegalIdentityChangeRequest[] }) {
  return (
    <section aria-label="Legal identity correction history" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Legal identity correction history</h2>
      {history.length === 0 ? (
        <EmptyState title="No correction requests yet" description="Legal name/tax ID correction requests you or a colleague submit will appear here." />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <thead>
              <tr className="text-left text-xs font-medium text-neutral-500">
                <th className="p-2">Field</th>
                <th className="p-2">Requested value</th>
                <th className="p-2">Status</th>
                <th className="p-2">Reviewed</th>
                <th className="p-2">Submitted</th>
              </tr>
            </thead>
            <tbody>
              {history.map((r) => (
                <tr key={r.id} className="border-t border-neutral-100">
                  <td className="p-2 text-sm">{CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELD_LABELS[r.fieldName]}</td>
                  <td className="p-2 text-sm">{typeof r.proposedValue === "string" ? r.proposedValue : ""}</td>
                  <td className="p-2 text-sm">
                    <StatusBadge tone={STATUS_TONE[r.status]} label={r.status} />
                  </td>
                  <td className="p-2 text-xs text-neutral-500">{r.reviewedAt ? `${new Date(r.reviewedAt).toLocaleString()}${r.reviewReason ? ` — ${r.reviewReason}` : ""}` : "—"}</td>
                  <td className="p-2 text-xs text-neutral-500">{new Date(r.createdAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

export function CustomerProfilePanel({
  profile,
  contacts,
  history,
  legalIdentityHistory,
  contactChangeHistory,
  submitTradeNameAction,
  submitBillingAddressAction,
  withdrawAction,
  submitLegalNameAction,
  submitTaxIdAction,
  withdrawLegalIdentityAction,
  submitAddContactAction,
  contactActions,
  withdrawContactChangeAction,
}: {
  tenantSlug: string;
  profile: CustomerPortalAccountProfile;
  contacts: readonly CustomerPortalAccountContact[];
  history: readonly CustomerProfileChangeRequest[];
  legalIdentityHistory: readonly CustomerLegalIdentityChangeRequest[];
  contactChangeHistory: readonly CustomerContactChangeRequest[];
  submitTradeNameAction: BoundAction;
  submitBillingAddressAction: BoundAction;
  withdrawAction: BoundAction;
  submitLegalNameAction: BoundAction;
  submitTaxIdAction: BoundAction;
  withdrawLegalIdentityAction: BoundAction;
  submitAddContactAction: BoundAction;
  contactActions: ReadonlyMap<string, { updateAction: BoundAction; removeAction: BoundAction }>;
  withdrawContactChangeAction: BoundAction;
}) {
  const pendingTradeName = history.find((r) => r.status === "pending" && r.fieldName === "trade_name");
  const pendingBillingAddress = history.find((r) => r.status === "pending" && r.fieldName === "billing_address");
  const pendingLegalName = legalIdentityHistory.find((r) => r.status === "pending" && r.fieldName === "legal_name");
  const pendingTaxId = legalIdentityHistory.find((r) => r.status === "pending" && r.fieldName === "tax_id");

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">{profile.legalName}</h2>
          <StatusBadge tone={profile.customerStatus === "active" ? "success" : "neutral"} label={profile.customerStatus} />
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <LegalIdentityField label="Legal name" fieldName="legal_name" currentValue={profile.legalName} pendingRequest={pendingLegalName} submitAction={submitLegalNameAction} withdrawAction={withdrawLegalIdentityAction} />
          <LegalIdentityField label="Tax ID" fieldName="tax_id" currentValue={profile.taxId ?? ""} pendingRequest={pendingTaxId} submitAction={submitTaxIdAction} withdrawAction={withdrawLegalIdentityAction} />
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <span className="text-xs font-medium text-neutral-500">Trade name</span>
            {pendingTradeName ? <PendingChangeBanner request={pendingTradeName} withdrawAction={withdrawAction} /> : <TradeNameForm currentValue={profile.tradeName ?? ""} submitAction={submitTradeNameAction} />}
          </div>
          <div className="flex flex-col gap-2">
            <span className="text-xs font-medium text-neutral-500">Billing address</span>
            {pendingBillingAddress ? (
              <PendingChangeBanner request={pendingBillingAddress} withdrawAction={withdrawAction} />
            ) : (
              <BillingAddressForm currentValue={profile.billingAddress as CustomerProfileBillingAddress} submitAction={submitBillingAddressAction} />
            )}
          </div>
        </div>
      </section>

      <ContactsSection
        contacts={contacts}
        contactChangeHistory={contactChangeHistory}
        submitAddContactAction={submitAddContactAction}
        contactActions={contactActions}
        withdrawContactChangeAction={withdrawContactChangeAction}
      />
      <HistorySection history={history} />
      <LegalIdentityHistorySection history={legalIdentityHistory} />
    </div>
  );
}
