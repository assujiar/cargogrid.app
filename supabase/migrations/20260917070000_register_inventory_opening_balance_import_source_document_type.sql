-- CG-AUDIT-2026-09-02 A4 ("No import UI over 12 working import schemas"),
-- twelfth and FINAL schema (inventory_opening_balance_import, after
-- finance_opening_balance_import, employee_import, vendor_import,
-- vendor_rate_import, customer_import, item_import,
-- attendance_device_import, timesheet_import, leave_opening_balance_import,
-- payroll_loan_cutover_import, and position_crosswalk_import): the SAME
-- document-type-registration decision this session's own
-- leave_opening_balance_import and payroll_loan_cutover_import slices made
-- (20260917050000/20260917060000).
--
-- The import_export SCHEMA registration itself (app.import_export_schemas +
-- the import_export:inventory_opening_balance_import config_type) is
-- already real
-- (20260831260000_create_inventory_and_leave_opening_balance_import_adapters.sql
-- lines 51-61, the SAME migration that also registers
-- leave_opening_balance_import's own schema kind). What is still missing is
-- a dedicated DOCUMENT TYPE for the raw source FILE itself. Confirmed live
-- via repo-wide grep before writing this migration: no migration and no
-- db-test fixture anywhere registers a dedicated
-- inventory_opening_balance_import_source document type --
-- scripts/db-tests/master-data-import.sql's own bootstrap fixture instead
-- reuses the generic, COM-owned master_data_import_source document type
-- (the same one item_import's own real, shipped UI reuses).
--
-- That reuse is functionally usable (master_data_import_source is a real
-- catalog row as of 20260917040000), but item_import's own reuse of it was
-- a deliberate, original-design choice (customer_import and item_import
-- were registered TOGETHER, in the same migration, explicitly sharing a
-- document type). inventory_opening_balance_import's own true sibling by
-- original design is leave_opening_balance_import (registered together in
-- 20260831260000), and that migration registers NO document type for
-- either -- reusing master_data_import_source for inventory would be pure
-- db-test-author convenience, not a real shared-ownership decision, the
-- exact situation this session's own leave_opening_balance_import and
-- payroll_loan_cutover_import migrations already declined to accept for
-- their own genuinely domain-owned cutover files. This migration applies
-- the identical reasoning: a genuinely OPS/warehouse-owned inventory
-- cutover file does not belong under a generic, commercial-master-data-
-- flavoured document type, so it gets its own dedicated one, mirroring
-- leave_opening_balance_import_source's/payroll_loan_cutover_import_source's
-- own one-document-type-per-schema precedent.
--
-- Mirrors every prior A4 document-type-registration migration's own
-- identical shape verbatim: additive, idempotent (on conflict (code) do
-- nothing), registers only the two global catalogue rows every tenant's own
-- later publish call depends on -- never a per-tenant config_object (that
-- remains a separate, later, per-tenant admin action). No new function is
-- created here.
--
-- owner_primitive_code 'OPS' matches this same schema's own
-- inventory_opening_balance_import registration (line 53 of the
-- 20260831260000 migration), the module that actually owns this document
-- type.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('inventory_opening_balance_import_source', 'Inventory Opening Balance Import Source File', 'OPS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:inventory_opening_balance_import_source', 'Inventory Opening Balance Import Source File', 'OPS', 'system')
on conflict (code) do nothing;
