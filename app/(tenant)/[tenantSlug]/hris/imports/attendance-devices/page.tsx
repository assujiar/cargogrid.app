import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
import { listConfigVersions, ConfigQueryError, type ConfigQueryRpcClient } from "../../../../../../server/queries/config.ts";
import { getImportExportJob, listImportStagingRows, ImportExportQueryError, type ImportExportQueryRpcClient } from "../../../../../../server/queries/import-export.ts";
import type { ImportExportJob, ImportStagingRow } from "../../../../../../server/contracts/import-export/import-export.ts";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { SuccessState } from "../../../../../../components/ui/success-state.tsx";
import {
  bootstrapAttendanceDeviceImportAction,
  uploadAttendanceDeviceImportSourceAction,
  stageAndValidateAttendanceDeviceImportRowsAction,
  commitAttendanceDeviceImportAction,
} from "./actions.ts";
import {
  BootstrapAttendanceDeviceImportForm,
  UploadAttendanceDeviceImportSourceForm,
  StageAndValidateAttendanceDeviceImportRowsForm,
  CommitAttendanceDeviceImportForm,
} from "./attendance-device-import-forms.tsx";

const SCHEMA_CODE = "attendance_device_import";
const DOCUMENT_TYPE_CODE = "attendance_device_import_source";

const ROW_STATUS_TONE = {
  pending: { tone: "neutral", label: "Pending" },
  valid: { tone: "success", label: "Valid" },
  invalid: { tone: "danger", label: "Invalid" },
} as const;

/**
 * Attendance device import wizard (CG-AUDIT-2026-09-02 A4, seventh import
 * schema). A real, multi-step state machine reflecting the actual underlying
 * job lifecycle (bootstrap -> upload+scan -> stage+validate -> review ->
 * commit), a near-mechanical port of hris/imports/employees/page.tsx's own
 * structure -- see that page's doc comment for why the shape isn't
 * simplified further.
 *
 * Linked from the attendance admin page's own header. Unlike master-data
 * imports (customers/items), a committed row here never creates or links a
 * master record -- it feeds app._ingest_attendance_event, the SAME engine
 * the live self-service clock path uses, so an already-committed staging row
 * is simply skipped as an idempotent replay rather than flagged as a
 * duplicate.
 */
export default async function AttendanceDeviceImportPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ job?: string }>;
}) {
  const { tenantSlug } = await params;
  const { job: jobId } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const serviceRoleClient = createSupabaseServiceRoleClient();
  const configClient: ConfigQueryRpcClient = { rpc: async (fn, args) => await serviceRoleClient.rpc(fn, args) };
  const importClient: ImportExportQueryRpcClient = { rpc: async (fn, args) => await serviceRoleClient.rpc(fn, args) };

  let bootstrapped = false;
  let loadFailed = false;
  try {
    const [docTypeVersions, schemaVersions] = await Promise.all([
      listConfigVersions(configClient, { configTypeCode: `document:${DOCUMENT_TYPE_CODE}`, tenantId: access.tenant.id, scopeLevel: "tenant", scopeId: null, actorAuthUserId: access.authUserId }),
      listConfigVersions(configClient, { configTypeCode: `import_export:${SCHEMA_CODE}`, tenantId: access.tenant.id, scopeLevel: "tenant", scopeId: null, actorAuthUserId: access.authUserId }),
    ]);
    bootstrapped = docTypeVersions.some((version) => version.status === "published") && schemaVersions.some((version) => version.status === "published");
  } catch (error) {
    if (!(error instanceof ConfigQueryError)) throw error;
    loadFailed = true;
  }

  let job: ImportExportJob | null = null;
  let jobLoadError: string | null = null;
  if (bootstrapped && jobId) {
    try {
      job = await getImportExportJob(importClient, { jobId, actorAuthUserId: access.authUserId });
    } catch (error) {
      if (!(error instanceof ImportExportQueryError)) throw error;
      jobLoadError = "Could not find this import job -- it may belong to a different organization.";
    }
  }

  let stagedRows: ImportStagingRow[] = [];
  if (job && job.totalRows !== null && job.totalRows > 0) {
    try {
      stagedRows = await listImportStagingRows(importClient, { jobId: job.jobId, actorAuthUserId: access.authUserId });
    } catch (error) {
      if (!(error instanceof ImportExportQueryError)) throw error;
    }
  }

  const rowColumns: readonly DataTableColumn<ImportStagingRow>[] = [
    { key: "rowNumber", header: "Row", render: (row) => row.rowNumber },
    {
      key: "status",
      header: "Status",
      render: (row) => {
        const { tone, label } = ROW_STATUS_TONE[row.validationStatus];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "employeeNumber", header: "Employee #", render: (row) => (row.rawPayload.employee_number as string | undefined) ?? "—" },
    { key: "eventType", header: "Event type", render: (row) => (row.rawPayload.event_type as string | undefined) ?? "—" },
    { key: "eventAt", header: "Event at", render: (row) => (row.rawPayload.event_at as string | undefined) ?? "—" },
    { key: "error", header: "Error", render: (row) => row.error ?? "—" },
  ];

  const pendingCount = stagedRows.filter((row) => row.validationStatus === "pending").length;
  const invalidCount = stagedRows.filter((row) => row.validationStatus === "invalid").length;
  const validCount = stagedRows.filter((row) => row.validationStatus === "valid").length;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Attendance device import</h1>
        <p className="text-sm text-text-secondary">
          Bulk-loads clock events exported from a physical attendance device as a CSV file. Real, staged, row-validated data -- each committed row is fed through the same ingestion engine as a live self-service clock event; an already-committed row is skipped as a safe replay, never duplicated.
        </p>
      </div>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading this workspace. Please try again." />
      ) : !bootstrapped ? (
        <EmptyState
          title="Not set up yet"
          description="This organization has not yet published the file-upload rules and column definition attendance device imports require. This is a one-time setup."
          primaryAction={<BootstrapAttendanceDeviceImportForm action={bootstrapAttendanceDeviceImportAction.bind(null, tenantSlug)} />}
        />
      ) : jobLoadError ? (
        <ErrorState description={jobLoadError} />
      ) : !job ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-text-primary">Upload a CSV file</h2>
          <p className="mt-1 text-xs text-text-secondary">Columns: employee_number, event_type (clock_in/clock_out), event_at (ISO-8601 timestamp), device_label.</p>
          <div className="mt-2">
            <UploadAttendanceDeviceImportSourceForm action={uploadAttendanceDeviceImportSourceAction.bind(null, tenantSlug)} />
          </div>
        </section>
      ) : (
        <>
          <section className="rounded-md border border-neutral-200 p-4">
            <h2 className="text-sm font-semibold text-text-primary">Current import</h2>
            <dl className="mt-2 grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
              <div>
                <dt className="text-xs text-text-secondary">Status</dt>
                <dd className="font-medium text-text-primary">{job.status}</dd>
              </div>
              <div>
                <dt className="text-xs text-text-secondary">Source file</dt>
                <dd className="font-medium text-text-primary">{(job.payload.source_original_filename as string | undefined) ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-text-secondary">Rows staged</dt>
                <dd className="font-medium text-text-primary">{job.totalRows ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-text-secondary">Valid / invalid</dt>
                <dd className="font-medium text-text-primary">
                  {job.validRowCount} / {job.invalidRowCount}
                </dd>
              </div>
            </dl>
          </section>

          {job.status === "completed" ? (
            <SuccessState title="Import completed" description={`Committed with ${job.validRowCount} valid row(s) and ${job.invalidRowCount} invalid row(s) skipped.`} />
          ) : job.totalRows === null || job.totalRows === 0 ? (
            <section className="rounded-md border border-neutral-200 p-4">
              <h2 className="text-sm font-semibold text-text-primary">Stage &amp; validate rows</h2>
              <p className="mt-1 text-xs text-text-secondary">
                Reads the uploaded file back and stages every row for validation. This requires the file to have already scanned clean -- if it has not, staging fails and you can try again shortly.
              </p>
              <div className="mt-2">
                <StageAndValidateAttendanceDeviceImportRowsForm action={stageAndValidateAttendanceDeviceImportRowsAction.bind(null, tenantSlug, job.jobId)} />
              </div>
            </section>
          ) : pendingCount > 0 ? (
            <section className="rounded-md border border-neutral-200 p-4">
              <h2 className="text-sm font-semibold text-text-primary">Continue validating</h2>
              <p className="mt-1 text-xs text-text-secondary">{pendingCount} row(s) still need validation.</p>
              <div className="mt-2">
                <StageAndValidateAttendanceDeviceImportRowsForm action={stageAndValidateAttendanceDeviceImportRowsAction.bind(null, tenantSlug, job.jobId)} />
              </div>
            </section>
          ) : (
            <>
              <section className="rounded-md border border-neutral-200 p-4">
                <h2 className="text-sm font-semibold text-text-primary">Review rows</h2>
                <p className="mt-1 text-xs text-text-secondary">
                  {validCount} valid, {invalidCount} invalid.
                </p>
                <div className="mt-2">
                  <DataTable caption="Staged rows" columns={rowColumns} rows={stagedRows} rowKey={(row) => row.id} emptyMessage="No rows staged." />
                </div>
              </section>

              <section className="rounded-md border border-neutral-200 p-4">
                <h2 className="text-sm font-semibold text-text-primary">Commit</h2>
                <p className="mt-1 text-xs text-text-secondary">
                  {invalidCount > 0
                    ? "This job has invalid rows -- commit is refused unless you explicitly accept skipping them."
                    : "Every row is valid. Committing feeds each row through the same clock-event ingestion the live self-service path uses."}
                </p>
                <div className="mt-2">
                  <CommitAttendanceDeviceImportForm action={commitAttendanceDeviceImportAction.bind(null, tenantSlug, job.jobId)} invalidRowCount={invalidCount} />
                </div>
              </section>
            </>
          )}

          <section className="rounded-md border border-neutral-200 p-4">
            <h2 className="text-sm font-semibold text-text-primary">Start a new import</h2>
            <div className="mt-2">
              <UploadAttendanceDeviceImportSourceForm action={uploadAttendanceDeviceImportSourceAction.bind(null, tenantSlug)} />
            </div>
          </section>
        </>
      )}
    </div>
  );
}
