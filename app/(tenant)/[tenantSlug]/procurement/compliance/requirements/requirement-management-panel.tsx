"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { ComplianceActionState } from "../actions.ts";
import { VENDOR_COMPLIANCE_REQUIREMENT_STATUSES, type VendorComplianceRequirementStatus, type VendorComplianceRequirement } from "../../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";

const INITIAL_STATE: ComplianceActionState = { error: null };

const STATUS_TONE: Record<VendorComplianceRequirementStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

export function RequirementManagementPanel({
  tenantSlug,
  requirements,
  statusFilter,
  createAction,
}: {
  tenantSlug: string;
  requirements: readonly VendorComplianceRequirement[];
  statusFilter: VendorComplianceRequirementStatus | null;
  createAction: (prevState: ComplianceActionState, formData: FormData) => Promise<ComplianceActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const createErrorId = "requirement-create-error";
  const createDescribedBy = state.error ? createErrorId : undefined;

  function applyFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/compliance/requirements?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="requirement-status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <Select id="requirement-status" defaultValue={statusFilter ?? ""} className="w-fit py-1.5" onChange={(event) => applyFilter(event.currentTarget.value)}>
            <option value="">All statuses</option>
            {VENDOR_COMPLIANCE_REQUIREMENT_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </Select>
        </div>

        {requirements.length === 0 ? (
          <EmptyState title="No requirements match this view" description="Create a new draft requirement below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Scope</th>
                <th className="pb-1">Document type</th>
                <th className="pb-1">Blocking</th>
                <th className="pb-1">Status</th>
              </tr>
            </thead>
            <tbody>
              {requirements.map((r) => (
                <tr key={r.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/procurement/compliance/requirements/${r.id}`} className="text-primary underline">
                      {r.name}
                    </Link>
                  </td>
                  <td className="py-1 text-xs">
                    {r.vendorCategory ?? "any category"} / {r.serviceType ?? "any service"}
                  </td>
                  <td className="py-1 text-xs">{r.documentTypeCode}</td>
                  <td className="py-1 text-xs">{r.blockingEffect}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[r.status]} label={r.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new requirement draft</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3" noValidate>
          <FormField id="name" label="Name">
            <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="documentTypeCode" label="Document type code">
            <Input id="documentTypeCode" name="documentTypeCode" type="text" required placeholder="vendor_compliance_document" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="vendorCategory" label="Vendor category (blank = any)">
            <Input id="vendorCategory" name="vendorCategory" type="text" placeholder="trucking, warehousing…" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="serviceType" label="Service type (blank = any)">
            <Input id="serviceType" name="serviceType" type="text" placeholder="linehaul, trucking…" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="blockingEffect" label="Blocking effect">
            <Select id="blockingEffect" name="blockingEffect" defaultValue="blocking" invalid={Boolean(state.error)} aria-describedby={createDescribedBy}>
              <option value="blocking">Blocking (triggers an eligibility hold)</option>
              <option value="warning">Warning (never holds)</option>
            </Select>
          </FormField>
          <FormField id="reminderOffsets" label="Reminder offsets (days before expiry, comma-separated)">
            <Input id="reminderOffsets" name="reminderOffsets" type="text" defaultValue="30,14,7" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <div className="flex items-center pt-5">
            <Checkbox id="requiresExpiry" name="requiresExpiry" defaultChecked label="This document type has an expiry date" aria-describedby={createDescribedBy} />
          </div>
          <div className="col-span-full">
            <FormField id="description" label="Description (optional)">
              <Textarea id="description" name="description" rows={2} invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
            </FormField>
          </div>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id={createErrorId}>{state.error}</ValidationMessage>
            </div>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create draft
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
