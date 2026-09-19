-- CG-AUDIT-2026-09-02 A4 ("No import UI over 12 working import schemas"),
-- tenth schema (leave_opening_balance_import, after finance_opening_balance_
-- import, employee_import, vendor_import, vendor_rate_import,
-- customer_import, item_import, attendance_device_import, and
-- timesheet_import): the SAME missing-registration gap already fixed for
-- finance_opening_balance_source, vendor_import_source,
-- vendor_rate_import_source, and master_data_import_source.
--
-- The import_export SCHEMA registration itself (app.import_export_schemas +
-- the import_export:leave_opening_balance_import config_type -- the
-- structural shape of the parsed CSV columns) is already real
-- (20260831260000_create_inventory_and_leave_opening_balance_import_adapters.sql
-- lines 51-61). What is still missing is a DIFFERENT, earlier catalogue
-- entry: the DOCUMENT TYPE for the raw source FILE itself
-- (leave_opening_balance_import_source) that app.initiate_file_upload
-- (PLT-128) requires before any tenant can even upload the CSV that would
-- later be staged against that schema. Confirmed live via repo-wide grep
-- before writing this migration: no migration and no db-test fixture
-- anywhere registers a dedicated leave_opening_balance_import_source
-- document type at all -- scripts/db-tests/hris-leave-permit-business-
-- trip.sql's own bootstrap fixture (line ~1006) instead reuses the
-- generic, COM-owned master_data_import_source document type (itself only
-- registered for real by this session's own
-- 20260917040000_register_master_data_import_source_document_type.sql).
-- That reuse works for the db-test's own narrow purpose, but a generic,
-- commercial-master-data-flavoured document type is the wrong home for a
-- genuinely HRS-owned, employee-linked opening-balance cutover file --
-- this migration instead gives leave_opening_balance_import a dedicated
-- document type, mirroring timesheet_import_source's and
-- attendance_device_import_source's own precedent of one document type per
-- HRS import schema (20260730980000_create_hris_overtime_timesheet.sql
-- lines 2122-2128, 20260730900000_create_hris_attendance.sql lines
-- 1547-1553) rather than vendor_rate_import's/customer_import's own
-- narrower precedent of sharing a document type with a sibling schema.
--
-- Mirrors every prior A4 document-type-registration migration's own
-- identical shape verbatim: additive, idempotent (on conflict (code) do
-- nothing), registers only the two global catalogue rows every tenant's own
-- later publish call depends on -- never a per-tenant config_object (that
-- remains a separate, later, per-tenant admin action). No new function is
-- created here.
--
-- owner_primitive_code 'HRS' matches this same schema's own
-- leave_opening_balance_import registration (line 53 of the 20260831260000
-- migration), the module that actually owns this document type.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('leave_opening_balance_import_source', 'Leave Opening Balance Import Source File', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:leave_opening_balance_import_source', 'Leave Opening Balance Import Source File', 'HRS', 'system')
on conflict (code) do nothing;
