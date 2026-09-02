"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { HelpdeskActionState } from "./actions.ts";
import { TICKET_PRIORITIES, HELPDESK_SEVERITIES, HELPDESK_ENVIRONMENTS, type TicketStatus, type HelpdeskTicketCategoryRow, type HelpdeskTicketListRow } from "../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: HelpdeskActionState = { error: null };

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

function HelpdeskTicketRow({ tenantSlug, ticket }: { tenantSlug: string; ticket: HelpdeskTicketListRow }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/helpdesk/${ticket.id}`} className="text-primary underline">
          {ticket.ticketNumber}
        </Link>
      </td>
      <td className="p-2 text-sm">{ticket.subject}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[ticket.status]} label={ticket.status.replace(/_/g, " ")} />
      </td>
      <td className="p-2 text-sm">{ticket.priority}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.severity ?? "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.categoryName}</td>
    </tr>
  );
}

function CreateHelpdeskTicketForm({
  categories,
  createTicketAction,
}: {
  categories: readonly HelpdeskTicketCategoryRow[];
  createTicketAction: (prevState: HelpdeskActionState, formData: FormData) => Promise<HelpdeskActionState>;
}) {
  const [state, formAction, pending] = useActionState(createTicketAction, INITIAL_STATE);
  const noCategoriesConfigured = categories.length === 0;
  const describedBy = state.error ? "create-helpdesk-ticket-error" : undefined;

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Open a CargoGrid support case</h2>
      <p className="text-xs text-neutral-500 sm:col-span-2">
        This opens a governed support ticket only. It never grants CargoGrid support access to your business data on its own — any diagnostic access requires a separate, reasoned, time-bound grant your organization
        approves.
      </p>
      <FormField id="helpdesk-categoryId" label="Category">
        <Select id="helpdesk-categoryId" name="categoryId" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Select a category
          </option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="helpdesk-priority" label="Priority">
        <Select id="helpdesk-priority" name="priority" defaultValue="normal" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="helpdesk-severity" label="Severity (optional)">
        <Select id="helpdesk-severity" name="severity" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Not specified</option>
          {HELPDESK_SEVERITIES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="helpdesk-environment" label="Environment (optional)">
        <Select id="helpdesk-environment" name="environment" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Not specified</option>
          {HELPDESK_ENVIRONMENTS.map((e) => (
            <option key={e} value={e}>
              {e}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="helpdesk-productArea" label="Product area (optional)">
        <Input id="helpdesk-productArea" name="productArea" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="helpdesk-externalReference" label="Your own reference (optional)">
        <Input id="helpdesk-externalReference" name="externalReference" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="sm:col-span-2">
        <FormField id="helpdesk-subject" label="Subject">
          <Input id="helpdesk-subject" name="subject" required minLength={1} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <FormField id="helpdesk-body" label="Description">
          <Textarea
            id="helpdesk-body"
            name="body"
            required
            minLength={1}
            rows={4}
            placeholder="Describe what you need help with."
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…" disabled={noCategoriesConfigured}>
          Submit case
        </Button>
      </div>
      {noCategoriesConfigured ? (
        <p className="text-xs text-neutral-500 sm:col-span-2">No helpdesk categories are configured for your organization yet — ask a tenant admin to enable one from the internal ticket workspace.</p>
      ) : null}
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id="create-helpdesk-ticket-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

export function HelpdeskPanel({
  tenantSlug,
  categories,
  tickets,
  createTicketAction,
}: {
  tenantSlug: string;
  categories: readonly HelpdeskTicketCategoryRow[];
  tickets: readonly HelpdeskTicketListRow[];
  createTicketAction: (prevState: HelpdeskActionState, formData: FormData) => Promise<HelpdeskActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your organization&apos;s support cases</h2>
        {tickets.length === 0 ? (
          <EmptyState title="No support cases yet" description="Cases your organization opens with CargoGrid support will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Case</th>
                  <th className="p-2">Subject</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Priority</th>
                  <th className="p-2">Severity</th>
                  <th className="p-2">Category</th>
                </tr>
              </thead>
              <tbody>
                {tickets.map((t) => (
                  <HelpdeskTicketRow key={t.id} tenantSlug={tenantSlug} ticket={t} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateHelpdeskTicketForm categories={categories} createTicketAction={createTicketAction} />
    </div>
  );
}
