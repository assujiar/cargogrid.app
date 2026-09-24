"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { searchMasterDataAction, mergeMasterDataAction } from "./actions.ts";
import type { MasterRecord } from "../../../../../server/contracts/master-data/master-data.ts";

/**
 * The 6 master types actually seeded by any real (non-db-test) migration today
 * (`supabase/migrations/20260717120000_create_master_data.sql`,
 * `20260727130000_create_operations_resource_assignment.sql`,
 * `20260730830000_create_hris_employee_master.sql`). Every one is tenant-scoped --
 * no `scope='global'` master type is seeded anywhere -- so this panel only ever
 * needs the tenant-scoped merge authority path. `app.master_types` has no list RPC
 * of its own (a genuinely new one would be its own separate, unrelated addition),
 * so this small, static, known option set is hardcoded here rather than fetched --
 * the same judgment call `components/forms/select.tsx`'s own header describes this
 * primitive for.
 */
const MASTER_TYPE_OPTIONS = [
  { code: "vendor", label: "Vendor" },
  { code: "vendor_rate", label: "Vendor rate" },
  { code: "fleet", label: "Fleet" },
  { code: "vehicle", label: "Vehicle" },
  { code: "driver", label: "Driver" },
  { code: "employee", label: "Employee" },
] as const;

/**
 * CG-AUDIT-2026-09-02 UNTRACKED-A1 (bounded core): `app.merge_master_records` --
 * the only deduplication path in the whole system -- was fully built and tested but
 * had zero callers anywhere. This is the first real caller: search for the two
 * duplicate records by master type, pick which one survives (target) and which one
 * gets folded into it (source, never deleted -- it stays a real, retained,
 * `canonical_status='merged'` row), and record why.
 */
export function MasterDataMergePanel({ tenantSlug }: { tenantSlug: string }) {
  const [masterTypeCode, setMasterTypeCode] = useState<string>(MASTER_TYPE_OPTIONS[0].code);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<MasterRecord[]>([]);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [searchPending, startSearch] = useTransition();

  const [sourceId, setSourceId] = useState("");
  const [targetId, setTargetId] = useState("");
  const [reason, setReason] = useState("");
  const [mergeError, setMergeError] = useState<string | null>(null);
  const [mergeSuccess, setMergeSuccess] = useState(false);
  const [mergePending, startMerge] = useTransition();

  const canMerge = Boolean(sourceId) && Boolean(targetId) && sourceId !== targetId && reason.trim().length > 0;

  return (
    <div className="flex flex-col gap-4 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Search master records</h2>
        <p className="text-xs text-neutral-500">Find the two duplicate records you want to merge. A merge is scoped to one master type at a time.</p>
      </div>

      <div className="flex flex-wrap items-end gap-2">
        <FormField id="master-data-type" label="Master type">
          <Select
            id="master-data-type"
            value={masterTypeCode}
            onChange={(e) => {
              setMasterTypeCode(e.target.value);
              setResults([]);
              setSourceId("");
              setTargetId("");
            }}
          >
            {MASTER_TYPE_OPTIONS.map((option) => (
              <option key={option.code} value={option.code}>
                {option.label}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="master-data-query" label="Code or name contains">
          <Input id="master-data-query" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="e.g. Acme" />
        </FormField>
        <Button
          type="button"
          variant="secondary"
          loading={searchPending}
          loadingLabel="Searching…"
          onClick={() =>
            startSearch(async () => {
              const result = await searchMasterDataAction(tenantSlug, masterTypeCode, query);
              setSearchError(result.error);
              setResults(result.results);
            })
          }
        >
          Search
        </Button>
      </div>

      {searchError ? <ValidationMessage id="master-data-search-error">{searchError}</ValidationMessage> : null}

      {results.length > 0 ? (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[500px] border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Code
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Name
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {results.map((record) => (
                <tr key={record.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{record.code}</td>
                  <td className="py-2 pr-4 text-neutral-600">{record.name}</td>
                  <td className="py-2 pr-4 text-neutral-600">{record.canonicalStatus}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {results.length > 0 ? (
        <div className="flex flex-col gap-3 border-t border-neutral-200 pt-4">
          <h2 className="text-sm font-semibold text-neutral-900">Merge two records</h2>
          <p className="text-xs text-neutral-500">The record to keep stays active and absorbs the other&apos;s code as an alias. The record to merge away is never deleted -- it is marked merged and points at the surviving record.</p>

          <div className="flex flex-wrap gap-2">
            <FormField id="master-data-target" label="Record to keep">
              <Select id="master-data-target" value={targetId} onChange={(e) => setTargetId(e.target.value)}>
                <option value="">Select a record…</option>
                {results.map((record) => (
                  <option key={record.id} value={record.id}>
                    {record.code} — {record.name}
                  </option>
                ))}
              </Select>
            </FormField>
            <FormField id="master-data-source" label="Record to merge away">
              <Select id="master-data-source" value={sourceId} onChange={(e) => setSourceId(e.target.value)}>
                <option value="">Select a record…</option>
                {results.map((record) => (
                  <option key={record.id} value={record.id}>
                    {record.code} — {record.name}
                  </option>
                ))}
              </Select>
            </FormField>
          </div>

          <FormField id="master-data-reason" label="Reason (required)">
            <Input id="master-data-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Duplicate vendor entered twice" />
          </FormField>

          {sourceId && targetId && sourceId === targetId ? <ValidationMessage id="master-data-same-record-error">The record to keep and the record to merge away must be different.</ValidationMessage> : null}
          {mergeError ? <ValidationMessage id="master-data-merge-error">{mergeError}</ValidationMessage> : null}
          {mergeSuccess ? <p className="text-sm text-success">Merged successfully.</p> : null}

          <Button
            type="button"
            disabled={!canMerge}
            loading={mergePending}
            loadingLabel="Merging…"
            onClick={() =>
              startMerge(async () => {
                const result = await mergeMasterDataAction(tenantSlug, sourceId, targetId, reason.trim());
                setMergeError(result.error);
                setMergeSuccess(!result.error);
                if (!result.error) {
                  setSourceId("");
                  setTargetId("");
                  setReason("");
                  const refreshed = await searchMasterDataAction(tenantSlug, masterTypeCode, query);
                  setResults(refreshed.results);
                }
              })
            }
          >
            Merge
          </Button>
        </div>
      ) : null}
    </div>
  );
}
