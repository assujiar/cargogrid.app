"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { OnboardingActionState } from "./actions.ts";
import { CASE_TYPES, CASE_STATUSES, SOURCE_TYPES, type CaseListRow, type CaseType, type CaseStatus, type TemplateListRow } from "../../../../../server/contracts/onboarding/onboarding.ts";

const INITIAL_STATE: OnboardingActionState = { error: null };

const STATUS_TONE: Record<CaseStatus, StatusTone> = {
  draft: "neutral",
  active: "info",
  pending_finalize_approval: "warning",
  finalized: "success",
  cancelled: "danger",
};

export function OnboardingCaseListPanel({
  tenantSlug,
  cases,
  templates,
  caseTypeFilter,
  statusFilter,
  search,
  startCaseAction,
}: {
  tenantSlug: string;
  cases: readonly CaseListRow[];
  templates: readonly TemplateListRow[];
  caseTypeFilter: CaseType | null;
  statusFilter: CaseStatus | null;
  search: string;
  startCaseAction: (prevState: OnboardingActionState, formData: FormData) => Promise<OnboardingActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(startCaseAction, INITIAL_STATE);
  const [sourceType, setSourceType] = useState<string>("direct_hire");
  const [caseType, setCaseType] = useState<string>("onboarding");

  function applyFilter(nextCaseType: string, nextStatus: string, nextSearch: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextCaseType) next.set("caseType", nextCaseType);
    else next.delete("caseType");
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    if (nextSearch) next.set("q", nextSearch);
    else next.delete("q");
    next.delete("after");
    router.push(`/${tenantSlug}/hris/onboarding?${next.toString()}`);
  }

  const publishedTemplateCount = templates.filter((t) => t.publishedVersionId != null).length;

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-col gap-1">
            <label htmlFor="case-search" className="text-xs font-medium text-neutral-600">
              Search (employee name)
            </label>
            <Input
              id="case-search"
              type="search"
              defaultValue={search}
              placeholder="Employee name"
              className="py-1.5"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(caseTypeFilter ?? "", statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="case-type-filter" className="text-xs font-medium text-neutral-600">
              Case type
            </label>
            <Select id="case-type-filter" defaultValue={caseTypeFilter ?? ""} className="py-1.5" onChange={(event) => applyFilter(event.currentTarget.value, statusFilter ?? "", search)}>
              <option value="">All types</option>
              {CASE_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="case-status-filter" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <Select id="case-status-filter" defaultValue={statusFilter ?? ""} className="py-1.5" onChange={(event) => applyFilter(caseTypeFilter ?? "", event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {CASE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
          </div>
        </div>

        {cases.length === 0 ? (
          <EmptyState title="No cases match this view" description="Adjust your search/status filter, or start a new case below." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Employee</th>
                  <th className="pb-1">Case type</th>
                  <th className="pb-1">Source</th>
                  <th className="pb-1">Effective date</th>
                  <th className="pb-1">Status</th>
                </tr>
              </thead>
              <tbody>
                {cases.map((c) => (
                  <tr key={c.id} className="border-t border-neutral-100">
                    <td className="py-1">
                      <Link href={`/${tenantSlug}/hris/onboarding/${c.id}`} className="text-primary underline">
                        {c.employeeFullName ?? "(unlinked)"}
                      </Link>
                    </td>
                    <td className="py-1 text-xs">{c.caseType}</td>
                    <td className="py-1 text-xs">{c.sourceType.replace(/_/g, " ")}</td>
                    <td className="py-1 text-xs">{c.effectiveDate ?? "—"}</td>
                    <td className="py-1">
                      <StatusBadge tone={STATUS_TONE[c.status]} label={c.status.replace(/_/g, " ")} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Start a new case</h2>
        {publishedTemplateCount === 0 ? (
          <p className="text-xs text-warning">No published checklist template exists yet for any case type -- publish one under Checklist templates first, or starting will fail with no_published_checklist_template.</p>
        ) : null}
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2" noValidate>
          <FormField id="caseType" label="Case type">
            <Select id="caseType" name="caseType" required value={caseType} onChange={(e) => setCaseType(e.currentTarget.value)} invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined}>
              {CASE_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="sourceType" label="Source">
            <Select id="sourceType" name="sourceType" required value={sourceType} onChange={(e) => setSourceType(e.currentTarget.value)} invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined}>
              {SOURCE_TYPES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
          </FormField>

          {sourceType === "job_offer" ? (
            <div className="sm:col-span-2">
              <FormField id="sourceJobOfferId" label="Accepted job offer ID" helpText="Find this on the candidate's application detail page under Recruitment once their offer is accepted.">
                <Input id="sourceJobOfferId" name="sourceJobOfferId" type="text" required placeholder="UUID of an app.job_offers row with status=accepted" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
              </FormField>
            </div>
          ) : null}

          {sourceType === "existing_employee" ? (
            <div className="sm:col-span-2">
              <FormField id="employeeMasterRecordId" label="Employee ID (master record)">
                <Input id="employeeMasterRecordId" name="employeeMasterRecordId" type="text" required placeholder="UUID from the Employees directory" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
              </FormField>
            </div>
          ) : null}

          {sourceType === "direct_hire" ? (
            <>
              <FormField id="fullName" label="Full name">
                <Input id="fullName" name="fullName" type="text" required invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
              </FormField>
              <FormField id="employmentType" label="Employment type">
                <Select id="employmentType" name="employmentType" required defaultValue="full_time" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined}>
                  <option value="full_time">full time</option>
                  <option value="part_time">part time</option>
                  <option value="contract">contract</option>
                  <option value="intern">intern</option>
                  <option value="probation">probation</option>
                  <option value="daily_worker">daily worker</option>
                </Select>
              </FormField>
              <FormField id="workEmail" label="Work email (optional)">
                <Input id="workEmail" name="workEmail" type="email" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
              </FormField>
              <FormField id="idempotencyKey" label="Idempotency key">
                <Input id="idempotencyKey" name="idempotencyKey" type="text" required placeholder="a stable, unique key for this start attempt" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
              </FormField>
            </>
          ) : null}

          <FormField id="effectiveDate" label="Effective date">
            <Input id="effectiveDate" name="effectiveDate" type="date" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
          </FormField>
          <FormField id="companyOrgUnitId" label="Company org unit ID (optional)">
            <Input id="companyOrgUnitId" name="companyOrgUnitId" type="text" invalid={Boolean(state.error)} aria-describedby={state.error ? "start-case-error" : undefined} />
          </FormField>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id="start-case-error">{state.error}</ValidationMessage>
            </div>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Starting…">
              Start case
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
