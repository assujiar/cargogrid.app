-- CG-AUDIT-2026-09-02 A4 ("No import UI over 12 working import schemas"),
-- fourth schema (vendor_rate_import, after finance_opening_balance_import,
-- employee_import, and vendor_import): the SAME missing-registration gap
-- already fixed for vendor_import_source
-- (20260917020000_register_vendor_import_source_document_type.sql) and
-- finance_opening_balance_source
-- (20260914080000_register_finance_opening_balance_source_document_type.sql).
--
-- The import_export SCHEMA registration itself (app.import_export_schemas +
-- the import_export:vendor_rate_import config_type -- the structural shape
-- of the parsed CSV columns) is already real
-- (20260730620000_extend_commercial_vendor_rate_for_procurement.sql lines
-- 1282-1288). What is still missing is a DIFFERENT, earlier catalogue
-- entry: the DOCUMENT TYPE for the raw source FILE itself
-- (vendor_rate_import_source) that app.initiate_file_upload (PLT-128)
-- requires before any tenant can even upload the CSV that would later be
-- staged against that schema. Confirmed live via repo-wide grep before
-- writing this migration: app.register_document_type(
-- 'vendor_rate_import_source', ...) is called only by
-- scripts/db-tests/procurement-vendor-rate-tiers.sql:164, against its own
-- disposable database -- no real migration ever performed that
-- registration. Every real tenant's first attempt to upload a vendor rate
-- import source file would fail immediately with
-- document_type_not_configured -- the actual, concrete blocker behind A4's
-- "no import UI" finding for this schema, not a missing RPC (the full
-- validate/commit adapter already exists and is fully tested,
-- app.validate_vendor_rate_import_row/app.commit_vendor_rate_import_job).
--
-- Mirrors 20260917020000's own identical shape verbatim: additive,
-- idempotent (on conflict (code) do nothing), registers only the two global
-- catalogue rows every tenant's own later publish call depends on -- never
-- a per-tenant config_object (that remains a separate, later, per-tenant
-- admin action). No new function is created here.
--
-- code/name/owner_primitive_code reused VERBATIM from
-- procurement-vendor-rate-tiers.sql:164's own register_document_type call
-- ('vendor_rate_import_source', 'Vendor Rate Import Source File', 'PRC') --
-- 'PRC' matches this same schema's own vendor_rate_import registration
-- (line 1282 of the 20260730620000 migration), the module that actually
-- owns this document type. Safe to apply even though
-- procurement-vendor-rate-tiers.sql's own register_document_type call
-- still runs against its own disposable database on every db:test run:
-- app.register_document_type is itself read-if-exists, and this migration's
-- own values are identical to that fixture's, so whichever writer runs
-- first is authoritative and the other is a genuine no-op.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('vendor_rate_import_source', 'Vendor Rate Import Source File', 'PRC', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:vendor_rate_import_source', 'Vendor Rate Import Source File', 'PRC', 'system')
on conflict (code) do nothing;
