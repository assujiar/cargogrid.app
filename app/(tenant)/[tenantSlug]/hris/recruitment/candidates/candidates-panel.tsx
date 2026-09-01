"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { RecruitmentExportForm, type RecruitmentExportActionState } from "../../../../../../components/domain/recruitment-export-form.tsx";
import type { CandidateListRow, CandidateStatus } from "../../../../../../server/contracts/recruitment/recruitment.ts";

const STATUS_TONE: Record<CandidateStatus, string> = {
  active: "bg-success/10 text-success",
  blocked: "bg-danger/10 text-danger",
  archived: "bg-neutral-200 text-neutral-600",
};

/**
 * Candidate directory (ISS-2026-067 item 5) -- a candidate reachable independently by
 * candidate id, not only via an application's own detail page. Mirrors
 * `../recruitment-panel.tsx`'s own search/filter shape exactly.
 */
export function CandidatesPanel({
  tenantSlug,
  candidates,
  statusFilter,
  search,
  exportAction,
}: {
  tenantSlug: string;
  candidates: CandidateListRow[];
  statusFilter: CandidateStatus | null;
  search: string;
  exportAction: (prevState: RecruitmentExportActionState, formData: FormData) => Promise<RecruitmentExportActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  function applyFilter(next: { status?: string; q?: string }) {
    const params = new URLSearchParams(searchParams.toString());
    if (next.status !== undefined) {
      if (next.status) params.set("status", next.status);
      else params.delete("status");
    }
    if (next.q !== undefined) {
      if (next.q) params.set("q", next.q);
      else params.delete("q");
    }
    params.delete("after");
    router.push(`/${tenantSlug}/hris/recruitment/candidates?${params.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <input
          type="search"
          defaultValue={search}
          placeholder="Search candidate name…"
          aria-label="Search candidates"
          onKeyDown={(e) => {
            if (e.key === "Enter") applyFilter({ q: (e.target as HTMLInputElement).value });
          }}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select aria-label="Filter by status" value={statusFilter ?? ""} onChange={(e) => applyFilter({ status: e.target.value })} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="blocked">Blocked</option>
          <option value="archived">Archived</option>
        </select>
      </div>

      <RecruitmentExportForm label="Export candidates" description="Downloads the candidate directory, respecting the status filter above. No email/phone/national ID/date of birth/address column is included." action={exportAction} />

      {candidates.length === 0 ? (
        <EmptyState title="No candidates yet" description="Candidates are added from a vacancy's own pipeline, or apply directly through a published careers link." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-left text-sm">
            <thead className="bg-neutral-50 text-xs uppercase text-neutral-500">
              <tr>
                <th scope="col" className="px-3 py-2">
                  Full name
                </th>
                <th scope="col" className="px-3 py-2">
                  Source
                </th>
                <th scope="col" className="px-3 py-2">
                  Status
                </th>
                <th scope="col" className="px-3 py-2">
                  Added
                </th>
              </tr>
            </thead>
            <tbody>
              {candidates.map((c) => (
                <tr key={c.id} className="border-t border-neutral-100 hover:bg-neutral-50">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/hris/recruitment/candidates/${c.id}`} className="font-medium text-primary underline">
                      {c.fullName}
                    </Link>
                  </td>
                  <td className="px-3 py-2">{c.source.replace("_", " ")}</td>
                  <td className="px-3 py-2">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_TONE[c.status]}`}>{c.status}</span>
                  </td>
                  <td className="px-3 py-2">{new Date(c.createdAt).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
