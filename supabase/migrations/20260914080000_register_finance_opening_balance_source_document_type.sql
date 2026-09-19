-- CG-AUDIT-2026-09-02 A4 ("No import UI over 12 working import schemas"),
-- narrowed to the finance_opening_balance_import schema: the SAME
-- missing-registration gap already fixed for E5's gps_device_installation
-- document type (20260914060000_register_gps_device_installation_document_type.sql).
--
-- The import_export SCHEMA registration itself (app.import_export_schemas +
-- the import_export:finance_opening_balance_import config_type -- the
-- structural shape of the PARSED CSV COLUMNS) is already real
-- (20260830130000_create_finance_opening_balance_import_and_gl_posting.sql
-- lines 495-501). What is still missing is a DIFFERENT, earlier catalogue
-- entry: the DOCUMENT TYPE for the raw source FILE itself
-- (finance_opening_balance_source) that app.initiate_file_upload
-- (PLT-128) requires before any tenant can even upload the CSV that would
-- later be staged against that schema. Confirmed live via repo-wide grep
-- before writing this migration: app.register_document_type(
-- 'finance_opening_balance_source', ...) is called only by
-- scripts/db-tests/finance-subledger.sql:903, against its own disposable
-- database -- no real migration ever performed that registration. Since
-- app.resolve_document_type_definition raises document_type_not_configured
-- whenever no tenant has ever published a 'document:<code>' config_object
-- for that document type, and a tenant can never publish one until the
-- matching app.config_types catalogue row exists (app.register_document_type's
-- own single entry point creates both rows together), every real tenant's
-- first attempt to upload a finance opening-balance source file would fail
-- immediately -- the actual, concrete blocker behind A4's "no import UI"
-- finding for this one schema, not a missing RPC (the full
-- validate/commit adapter already exists and is fully tested,
-- app.validate_finance_opening_balance_import_row /
-- app.commit_finance_opening_balance_import_job).
--
-- Mirrors 20260914060000_register_gps_device_installation_document_type.sql's
-- own identical shape verbatim: additive, idempotent (on conflict (code) do
-- nothing), registers only the two global catalogue rows every tenant's own
-- later publish call depends on -- never a per-tenant config_object (that
-- remains a separate, later, per-tenant admin action). No new function is
-- created here.
--
-- code/name/owner_primitive_code reused VERBATIM from
-- finance-subledger.sql:903's own register_document_type call
-- ('finance_opening_balance_source', 'Finance Opening Balance Source File',
-- 'FIN') -- 'FIN' matches this same migration's own
-- finance_opening_balance_import schema registration (line 496 of the
-- 20260830130000 migration), the module that actually owns this document
-- type, unlike the generic 'DOC' primitive E5's device-evidence photo used.
-- Safe to apply even though finance-subledger.sql's own
-- register_document_type call still runs against its own disposable
-- database on every db:test run: app.register_document_type is itself
-- read-if-exists, and this migration's own values are identical to that
-- fixture's, so whichever writer runs first is authoritative and the other
-- is a genuine no-op.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('finance_opening_balance_source', 'Finance Opening Balance Source File', 'FIN', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:finance_opening_balance_source', 'Finance Opening Balance Source File', 'FIN', 'system')
on conflict (code) do nothing;
