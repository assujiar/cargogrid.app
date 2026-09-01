"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import type { CandidateProfile, CandidateStatus, CandidateDuplicateMatch } from "../../../../../../../server/contracts/recruitment/recruitment.ts";
import type { CandidateActionState, DuplicateSearchState, DuplicateFlagState } from "./actions.ts";

const INITIAL_STATE: CandidateActionState = { error: null };
const INITIAL_SEARCH_STATE: DuplicateSearchState = { error: null, matches: [], searched: false };
const INITIAL_FLAG_STATE: DuplicateFlagState = { error: null, flagged: null };

type Bound0 = (prevState: CandidateActionState, formData: FormData) => Promise<CandidateActionState>;
type BoundSearch = (prevState: DuplicateSearchState, formData: FormData) => Promise<DuplicateSearchState>;
type BoundFlag = (prevState: DuplicateFlagState, formData: FormData) => Promise<DuplicateFlagState>;

const STATUS_TONE: Record<CandidateStatus, string> = {
  active: "bg-success/10 text-success",
  blocked: "bg-danger/10 text-danger",
  archived: "bg-neutral-200 text-neutral-600",
};

export function CandidateDetailPanel({
  candidate,
  updateProfileAction,
  setStatusAction,
  searchDuplicatesAction,
  flagDuplicateAction,
  decideDuplicateAction,
}: {
  candidate: CandidateProfile;
  updateProfileAction: Bound0;
  setStatusAction: (newStatus: CandidateStatus) => Bound0;
  searchDuplicatesAction: BoundSearch;
  flagDuplicateAction: (matchCandidateId: string, similarityBasis: string, similarityScore: number | null) => BoundFlag;
  decideDuplicateAction: (duplicateId: string, expectedVersion: number, decision: "linked" | "dismissed") => Bound0;
}) {
  const [profileState, profileFormAction, profilePending] = useActionState(updateProfileAction, INITIAL_STATE);
  const [searchState, searchFormAction, searchPending] = useActionState(searchDuplicatesAction, INITIAL_SEARCH_STATE);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-xl font-semibold text-neutral-900">{candidate.fullName}</h1>
          <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_TONE[candidate.status]}`}>{candidate.status}</span>
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-neutral-500">
          <span>{candidate.source.replace("_", " ")}</span>
          {candidate.personalDataMasked ? (
            <span className="italic">Contact details masked -- you don&apos;t hold HRS:View personal data</span>
          ) : (
            <span>
              {candidate.email ?? "no email"} {candidate.phone ? `· ${candidate.phone}` : ""}
            </span>
          )}
          <span>{candidate.consentGiven ? `Consent given (${candidate.consentVersion ?? "unknown version"})` : "No consent recorded"}</span>
        </div>
      </div>

      <CandidateStatusActions status={candidate.status} setStatusAction={setStatusAction} />

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Profile</h2>
        <form action={profileFormAction} className="flex flex-col gap-3" noValidate>
          <div className="flex flex-wrap gap-3">
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="fullName" className="text-xs font-medium text-neutral-700">
                Full name
              </label>
              <input id="fullName" name="fullName" defaultValue={candidate.fullName} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="phone" className="text-xs font-medium text-neutral-700">
                Phone
              </label>
              <input id="phone" name="phone" defaultValue={candidate.phone ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
          </div>
          <div className="flex flex-wrap gap-3">
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="nationalIdNumber" className="text-xs font-medium text-neutral-700">
                National ID number
              </label>
              <input id="nationalIdNumber" name="nationalIdNumber" defaultValue={candidate.nationalIdNumber ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="dateOfBirth" className="text-xs font-medium text-neutral-700">
                Date of birth
              </label>
              <input id="dateOfBirth" name="dateOfBirth" type="date" defaultValue={candidate.dateOfBirth ?? ""} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            </div>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="address" className="text-xs font-medium text-neutral-700">
              Address
            </label>
            <textarea id="address" name="address" defaultValue={candidate.address ?? ""} rows={2} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="resumeFileId" className="text-xs font-medium text-neutral-700">
              Resume file id
            </label>
            <input id="resumeFileId" name="resumeFileId" defaultValue={candidate.resumeFileId ?? ""} placeholder="uuid" className="w-72 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          {profileState.error ? (
            <p role="alert" className="text-sm text-danger">
              {profileState.error}
            </p>
          ) : null}
          <Button type="submit" loading={profilePending} loadingLabel="Saving…" className="w-fit">
            Save profile
          </Button>
        </form>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div>
          <h2 className="text-sm font-semibold text-neutral-900">Duplicate review</h2>
          <p className="text-xs text-neutral-500">
            Exact email/phone match plus fuzzy name similarity, human-reviewed-only -- searching or flagging never merges a record automatically.
          </p>
        </div>
        <form action={searchFormAction} className="flex flex-wrap items-end gap-2" noValidate>
          <div className="flex flex-col gap-1">
            <label htmlFor="dup-fullName" className="text-xs font-medium text-neutral-700">
              Name
            </label>
            <input id="dup-fullName" name="fullName" defaultValue={candidate.fullName} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="dup-email" className="text-xs font-medium text-neutral-700">
              Email
            </label>
            <input id="dup-email" name="email" defaultValue={candidate.personalDataMasked ? "" : (candidate.email ?? "")} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="dup-phone" className="text-xs font-medium text-neutral-700">
              Phone
            </label>
            <input id="dup-phone" name="phone" defaultValue={candidate.personalDataMasked ? "" : (candidate.phone ?? "")} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          <Button type="submit" variant="secondary" loading={searchPending} loadingLabel="Searching…">
            Search for duplicates
          </Button>
        </form>

        {searchState.error ? (
          <p role="alert" className="text-sm text-danger">
            {searchState.error}
          </p>
        ) : null}

        {searchState.searched && searchState.matches.length === 0 ? <p className="text-sm text-neutral-500">No possible duplicates found.</p> : null}

        {searchState.matches.length > 0 ? (
          <ul className="flex flex-col gap-2">
            {searchState.matches
              .filter((m) => m.id !== candidate.id)
              .map((m) => (
                <DuplicateMatchRow key={m.id} match={m} flagAction={flagDuplicateAction} decideAction={decideDuplicateAction} />
              ))}
          </ul>
        ) : null}
      </section>
    </div>
  );
}

function CandidateStatusActions({ status, setStatusAction }: { status: CandidateStatus; setStatusAction: (newStatus: CandidateStatus) => Bound0 }) {
  const [blockState, blockFormAction, blockPending] = useActionState(setStatusAction("blocked"), INITIAL_STATE);
  const [archiveState, archiveFormAction, archivePending] = useActionState(setStatusAction("archived"), INITIAL_STATE);
  const [reactivateState, reactivateFormAction, reactivatePending] = useActionState(setStatusAction("active"), INITIAL_STATE);
  const error = blockState.error ?? archiveState.error ?? reactivateState.error;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {status === "active" ? (
        <>
          <form action={blockFormAction} className="flex items-center gap-2">
            <input type="hidden" name="reason" value="Blocked by recruiter" />
            <Button type="submit" variant="destructive" loading={blockPending} loadingLabel="Blocking…">
              Block candidate
            </Button>
          </form>
          <form action={archiveFormAction} className="flex items-center gap-2">
            <input type="hidden" name="reason" value="Archived by recruiter" />
            <Button type="submit" variant="secondary" loading={archivePending} loadingLabel="Archiving…">
              Archive candidate
            </Button>
          </form>
        </>
      ) : null}
      {status !== "active" ? (
        <form action={reactivateFormAction} className="flex items-center gap-2">
          <Button type="submit" loading={reactivatePending} loadingLabel="Reactivating…">
            Reactivate to active
          </Button>
        </form>
      ) : null}
      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}

function DuplicateMatchRow({
  match,
  flagAction,
  decideAction,
}: {
  match: CandidateDuplicateMatch;
  flagAction: (matchCandidateId: string, similarityBasis: string, similarityScore: number | null) => BoundFlag;
  decideAction: (duplicateId: string, expectedVersion: number, decision: "linked" | "dismissed") => Bound0;
}) {
  const boundFlag = flagAction(match.id, match.similarityBasis, match.similarityScore);
  const [flagState, flagFormAction, flagPending] = useActionState(boundFlag, INITIAL_FLAG_STATE);

  return (
    <li className="rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span className="font-medium">{match.fullName}</span>
        <span className="text-xs text-neutral-500">
          {match.similarityBasis} &middot; {(match.similarityScore * 100).toFixed(0)}% match
        </span>
      </div>
      {flagState.flagged ? (
        <DecideDuplicateForm duplicateId={flagState.flagged.id} expectedVersion={flagState.flagged.recordVersion} decideAction={decideAction} />
      ) : (
        <form action={flagFormAction} className="mt-2">
          <Button type="submit" variant="secondary" loading={flagPending} loadingLabel="Flagging…">
            Flag as duplicate
          </Button>
        </form>
      )}
      {flagState.error ? (
        <p role="alert" className="mt-1 text-xs text-danger">
          {flagState.error}
        </p>
      ) : null}
    </li>
  );
}

function DecideDuplicateForm({
  duplicateId,
  expectedVersion,
  decideAction,
}: {
  duplicateId: string;
  expectedVersion: number;
  decideAction: (duplicateId: string, expectedVersion: number, decision: "linked" | "dismissed") => Bound0;
}) {
  const [linkState, linkFormAction, linkPending] = useActionState(decideAction(duplicateId, expectedVersion, "linked"), INITIAL_STATE);
  const [dismissState, dismissFormAction, dismissPending] = useActionState(decideAction(duplicateId, expectedVersion, "dismissed"), INITIAL_STATE);
  const [reason, setReason] = useState("");

  return (
    <div className="mt-2 flex flex-col gap-2">
      <label className="text-xs font-medium text-neutral-700">
        Decision reason
        <input value={reason} onChange={(e) => setReason(e.target.value)} className="mt-1 block w-full rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      </label>
      <div className="flex gap-2">
        <form action={linkFormAction}>
          <input type="hidden" name="reason" value={reason} />
          <Button type="submit" loading={linkPending} loadingLabel="Saving…" disabled={!reason}>
            Confirm duplicate (link)
          </Button>
        </form>
        <form action={dismissFormAction}>
          <input type="hidden" name="reason" value={reason} />
          <Button type="submit" variant="secondary" loading={dismissPending} loadingLabel="Saving…" disabled={!reason}>
            Not a duplicate (dismiss)
          </Button>
        </form>
      </div>
      {(linkState.error ?? dismissState.error) ? (
        <p role="alert" className="text-xs text-danger">
          {linkState.error ?? dismissState.error}
        </p>
      ) : null}
    </div>
  );
}
