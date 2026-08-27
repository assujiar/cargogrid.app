#!/usr/bin/env bash
# ISS-2026-268 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
# -- docs/runbooks/database-restore.md §4 item 2's own seeded drill slice (2 tenants, 2
# users, 1 pending + 1 dead-lettered job) has gone unexercised for app.files across 2
# consecutive checkpoints (HDN-383, HDN-384), disclosed inline both times but never
# tracked or closed. Not sandbox-infeasible like Supabase Storage object bytes (ISS-2026-255)
# -- file-METADATA recovery is "the same ordinary-table mechanism already proven for jobs
# and was fully testable in-sandbox" (the entry's own text, and item 2's own real pg_dump/
# pg_restore procedure already covers it structurally; jobs was simply the only table
# whose survival was actually asserted afterward).
#
# A REAL, live, timed pg_dump/pg_restore drill -- not a db-tests/*.sql simulation -- since
# this is exactly the mechanism item 2 itself already uses and measures (dump/drop/create/
# restore against a real disposable Postgres instance, real wall-clock timing). Committed
# as a permanent, re-runnable script (mirroring this repository's own established
# non-*.sql drill-helper precedent, scripts/db-tests/wms-picking-concurrency-helper.sh) so
# this specific coverage gap can never silently regress a third time -- the whole point of
# this entry's own text ("a minor coverage gap for the next real drill to close").
#
# Not part of `pnpm run db:test` (scripts/db-tests/run.sh only globs *.sql as test files)
# -- run manually: bash scripts/db-tests/database-restore-files-drill.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATABASE_ADMIN_URL="${DATABASE_ADMIN_URL:-postgresql://postgres:postgres@127.0.0.1:5432/postgres}"
DB_NAME="cargogrid_restore_files_drill"
DUMP_FILE="$(mktemp -u /tmp/cargogrid-restore-files-drill-XXXXXX.dump)"

# shellcheck source=lib/setup-disposable-db.sh
source "$REPO_ROOT/scripts/db-tests/lib/setup-disposable-db.sh"

cleanup() {
  rm -f "$DUMP_FILE"
}
trap cleanup EXIT

echo "==> database-restore-files-drill: seeding a fresh disposable database with the full migration set"
cargogrid_setup_disposable_db "$DATABASE_ADMIN_URL" "$DB_NAME" "$REPO_ROOT" "$REPO_ROOT/scripts/db-tests/fixtures"
DB_URL="$CARGOGRID_TEST_DB_URL"

echo "==> database-restore-files-drill: seeding the representative slice -- 1 tenant, 1 actor, 1 job, and (ISS-2026-268) 1 real app.files row"
psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare
  v_tenant uuid;
  v_actor uuid := '00000000-0000-0000-0000-000039000001';
  v_user app.users;
  v_draft app.config_versions;
  v_file app.files;
begin
  insert into auth.users (id, email) values (v_actor, 'drilloperator@restoredrill268.test');
  perform app.provision_tenant('restoredrill268', 'Restore Drill 268 Co', 'idem-restoredrill268', 'tester');
  v_tenant := (select id from app.tenants where slug = 'restoredrill268');
  v_user := app.invite_user(v_tenant, v_actor, 'drilloperator@restoredrill268.test', 'Drill Operator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status(v_user.id, 'active', 'drill activation', 'tester');
  perform app.grant_principal_membership(v_actor, 'tenant_admin', v_tenant, null, 'tester');

  perform app.enqueue_job(v_tenant, 'notification_batch', '{}'::jsonb, 5, 'idem-restoredrill268-job-1', 3, v_actor, 'drilloperator');

  -- A published per-tenant document_type_definition is a real precondition of
  -- app.initiate_file_upload, mirroring scripts/db-tests/document-file.sql's own
  -- established minimal-valid-definition shape exactly.
  v_draft := app.create_config_draft('document:employee_document', v_tenant, 'tenant', null, v_actor, 'drilloperator');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_actor, 'drilloperator');
  perform app.publish_document_type_definition(v_draft.id, v_actor, now(), 'drilloperator');

  v_file := app.initiate_file_upload(v_tenant, 'employee_document', 'restore_drill', gen_random_uuid(), 'restore-drill-268.pdf', 'application/pdf', 4096, null, false, null, '{}', null, 'idem-restoredrill268-file-1', v_actor, 'drilloperator');
  perform app.record_file_scan_result(v_file.id, 'clean', null, v_actor, 'drilloperator');
end;
$$;
SQL

echo "==> database-restore-files-drill: capturing pre-restore state (jobs + files)"
BEFORE_FILE="$(psql "$DB_URL" -Atqc "select id, tenant_id, original_filename, storage_path, size_bytes, malware_scan_status, malware_scan_completed_at, created_at from app.files where original_filename = 'restore-drill-268.pdf';")"
BEFORE_JOB="$(psql "$DB_URL" -Atqc "select job_id, tenant_id, status, attempts, idempotency_key, created_at from app.jobs where idempotency_key = 'idem-restoredrill268-job-1';")"
if [ -z "$BEFORE_FILE" ] || [ -z "$BEFORE_JOB" ]; then
  echo "FAIL: expected both a real app.files row and a real app.jobs row to exist before the drill even starts" >&2
  exit 1
fi
echo "  -- before (files): $BEFORE_FILE"
echo "  -- before (jobs):  $BEFORE_JOB"

echo "==> database-restore-files-drill: pg_dump -Fc (owner+privileges included, per this runbook's own documented footgun)"
T0=$(date +%s.%N)
pg_dump -Fc "$DB_URL" -f "$DUMP_FILE"
T1=$(date +%s.%N)

echo "==> database-restore-files-drill: DROP DATABASE / CREATE DATABASE"
psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $DB_NAME;" >/dev/null
psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DB_NAME;" >/dev/null
T2=$(date +%s.%N)

echo "==> database-restore-files-drill: pg_restore -j 4"
pg_restore -j 4 -d "$DB_URL" "$DUMP_FILE" || {
  echo "NOTE: pg_restore exit status reflects the same 'errors ignored' shape this runbook's own §4 item 3 already documents (e.g. role-recreation notices) -- the assertions below, not this exit code, are the real pass/fail signal."
}
T3=$(date +%s.%N)

echo "==> database-restore-files-drill: verifying post-restore state (byte-for-byte, not merely non-null)"
AFTER_FILE="$(psql "$DB_URL" -Atqc "select id, tenant_id, original_filename, storage_path, size_bytes, malware_scan_status, malware_scan_completed_at, created_at from app.files where original_filename = 'restore-drill-268.pdf';")"
AFTER_JOB="$(psql "$DB_URL" -Atqc "select job_id, tenant_id, status, attempts, idempotency_key, created_at from app.jobs where idempotency_key = 'idem-restoredrill268-job-1';")"
echo "  -- after (files):  $AFTER_FILE"
echo "  -- after (jobs):   $AFTER_JOB"

FAILED=0
if [ "$BEFORE_FILE" != "$AFTER_FILE" ]; then
  echo "FAIL: app.files row did not survive the restore identically -- ISS-2026-268 has reappeared" >&2
  FAILED=1
fi
if [ "$BEFORE_JOB" != "$AFTER_JOB" ]; then
  echo "FAIL: app.jobs row did not survive the restore identically (the already-proven case -- a regression here would indicate an unrelated defect)" >&2
  FAILED=1
fi

DUMP_S=$(echo "$T1 - $T0" | bc)
TEARDOWN_S=$(echo "$T2 - $T1" | bc)
RESTORE_S=$(echo "$T3 - $T2" | bc)
TOTAL_S=$(echo "$T3 - $T0" | bc)
echo "==> database-restore-files-drill: timing -- dump ${DUMP_S}s, teardown+create ${TEARDOWN_S}s, restore ${RESTORE_S}s, total ${TOTAL_S}s"

echo "==> database-restore-files-drill: dropping disposable database '$DB_NAME'"
psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $DB_NAME;" >/dev/null

if [ "$FAILED" -ne 0 ]; then
  echo "==> database-restore-files-drill: FAILED"
  exit 1
fi

echo "==> database-restore-files-drill: PASSED -- app.files metadata survives the same pg_dump/pg_restore cycle already proven for app.jobs, byte-for-byte"
