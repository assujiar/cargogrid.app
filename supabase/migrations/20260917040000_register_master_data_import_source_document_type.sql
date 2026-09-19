-- CG-AUDIT-2026-09-02 A4 ("No import UI over 12 working import schemas"),
-- fifth schema (customer_import, after finance_opening_balance_import,
-- employee_import, vendor_import, and vendor_rate_import): the SAME
-- missing-registration gap already fixed for vendor_rate_import_source
-- (20260917030000_register_vendor_rate_import_source_document_type.sql)
-- and vendor_import_source
-- (20260917020000_register_vendor_import_source_document_type.sql).
--
-- The import_export SCHEMA registration itself (app.import_export_schemas +
-- the import_export:customer_import config_type -- the structural shape of
-- the parsed CSV columns) is already real
-- (20260830120000_create_customer_and_item_import_adapters.sql lines
-- 219-227, which ALSO registers item_import's own schema kind in the same
-- statement -- customer_import and item_import are siblings created
-- together in that one migration). What is still missing is a DIFFERENT,
-- earlier catalogue entry: the DOCUMENT TYPE for the raw source FILE
-- itself (master_data_import_source, shared by BOTH customer_import and
-- item_import per that migration's own design) that app.initiate_file_upload
-- (PLT-128) requires before any tenant can even upload the CSV that would
-- later be staged against either schema. Confirmed live via repo-wide grep
-- before writing this migration: app.register_document_type(
-- 'master_data_import_source', ...) is called only by
-- scripts/db-tests/master-data-import.sql:181, against its own disposable
-- database -- no real migration ever performed that registration. Every
-- real tenant's first attempt to upload a customer (or, later, item)
-- import source file would fail immediately with
-- document_type_not_configured -- the actual, concrete blocker behind A4's
-- "no import UI" finding for this schema, not a missing RPC (the full
-- validate/commit adapter already exists and is fully tested,
-- app.validate_customer_import_row/app.commit_customer_import_job).
--
-- Registering this shared document type here, while only customer_import
-- gets a UI in this same commit, is deliberately harmless and forward-
-- compatible: this migration is additive and idempotent (on conflict (code)
-- do nothing), so a future item_import UI slice finds the document type
-- already registered and needs no migration of its own for it -- exactly
-- the same "whichever writer runs first is authoritative" property
-- 20260917020000/20260917030000 already rely on against their own
-- respective db-test fixtures.
--
-- code/name/owner_primitive_code reused VERBATIM from
-- master-data-import.sql:181's own register_document_type call
-- ('master_data_import_source', 'Master Data Import Source File', 'COM') --
-- 'COM' matches customer_import's own registration (line 220 of the
-- 20260830120000 migration); item_import is 'OPS'-owned but shares this
-- same document type by the original migration's own design, not a new
-- decision made here.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('master_data_import_source', 'Master Data Import Source File', 'COM', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:master_data_import_source', 'Master Data Import Source File', 'COM', 'system')
on conflict (code) do nothing;
