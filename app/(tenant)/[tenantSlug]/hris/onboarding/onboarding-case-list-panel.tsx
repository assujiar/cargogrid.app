"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
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
            <input
              id="case-search"
              type="search"
              defaultValue={search}
              placeholder="Employee name"
              className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(caseTypeFilter ?? "", statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="case-type-filter" className="text-xs font-medium text-neutral-600">
              Case type
            </label>
            <select id="case-type-filter" defaultValue={caseTypeFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value, statusFilter ?? "", search)}>
              <option value="">All types</option>
              {CASE_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="case-status-filter" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <select id="case-status-filter" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(caseTypeFilter ?? "", event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {CASE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
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
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1">
            <label htmlFor="caseType" className="text-xs font-medium text-neutral-600">
              Case type
            </label>
            <select id="caseType" name="caseType" required value={caseType} onChange={(e) => setCaseType(e.currentTarget.value)} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
              {CASE_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="sourceType" className="text-xs font-medium text-neutral-600">
              Source
            </label>
            <select id="sourceType" name="sourceType" required value={sourceType} onChange={(e) => setSourceType(e.currentTarget.value)} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
              {SOURCE_TYPES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>

          {sourceType === "job_offer" ? (
            <div className="flex flex-col gap-1 sm:col-span-2">
              <label htmlFor="sourceJobOfferId" className="text-xs font-medium text-neutral-600">
                Accepted job offer ID
              </label>
              <input id="sourceJobOfferId" name="sourceJobOfferId" type="text" required placeholder="UUID of an app.job_offers row with status=accepted" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
              <p className="text-xs text-neutral-500">Find this on the candidate&apos;s application detail page under Recruitment once their offer is accepted.</p>
            </div>
          ) : null}

          {sourceType === "existing_employee" ? (
            <div className="flex flex-col gap-1 sm:col-span-2">
              <label htmlFor="employeeMasterRecordId" className="text-xs font-medium text-neutral-600">
                Employee ID (master record)
              </label>
              <input id="employeeMasterRecordId" name="employeeMasterRecordId" type="text" required placeholder="UUID from the Employees directory" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
            </div>
          ) : null}

          {sourceType === "direct_hire" ? (
            <>
              <div className="flex flex-col gap-1">
                <label htmlFor="fullName" className="text-xs font-medium text-neutral-600">
                  Full name
                </label>
                <input id="fullName" name="fullName" type="text" required className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="employmentType" className="text-xs font-medium text-neutral-600">
                  Employment type
                </label>
                <select id="employmentType" name="employmentType" required defaultValue="full_time" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
                  <option value="full_time">full time</option>
                  <option value="part_time">part time</option>
                  <option value="contract">contract</option>
                  <option value="intern">intern</option>
                  <option value="probation">probation</option>
                  <option value="daily_worker">daily worker</option>
                </select>
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="workEmail" className="text-xs font-medium text-neutral-600">
                  Work email (optional)
                </label>
                <input id="workEmail" name="workEmail" type="email" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="idempotencyKey" className="text-xs font-medium text-neutral-600">
                  Idempotency key
                </label>
                <input id="idempotencyKey" name="idempotencyKey" type="text" required placeholder="a stable, unique key for this start attempt" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
              </div>
            </>
          ) : null}

          <div className="flex flex-col gap-1">
            <label htmlFor="effectiveDate" className="text-xs font-medium text-neutral-600">
              Effective date
            </label>
            <input id="effectiveDate" name="effectiveDate" type="date" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="companyOrgUnitId" className="text-xs font-medium text-neutral-600">
              Company org unit ID (optional)
            </label>
            <input id="companyOrgUnitId" name="companyOrgUnitId" type="text" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
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
