-- CG-AUDIT-2026-09-02 A4 ("No import UI over 12 working import schemas"),
-- eleventh schema (payroll_loan_cutover_import, after finance_opening_
-- balance_import, employee_import, vendor_import, vendor_rate_import,
-- customer_import, item_import, attendance_device_import, timesheet_import,
-- and leave_opening_balance_import): the SAME document-type-registration
-- decision this session's own leave_opening_balance_import slice made
-- (20260917050000_register_leave_opening_balance_import_source_document_type.sql).
--
-- The import_export SCHEMA registration itself (app.import_export_schemas +
-- the import_export:payroll_loan_cutover_import config_type) is already real
-- (20260901010000_create_payroll_loan_cutover_import_adapter.sql lines
-- 161-167). What is still missing is a dedicated DOCUMENT TYPE for the raw
-- source FILE itself. Confirmed live via repo-wide grep before writing this
-- migration: no migration and no db-test fixture anywhere registers a
-- dedicated payroll_loan_cutover_import_source document type --
-- scripts/db-tests/hris-payroll.sql's own bootstrap fixture (line ~493)
-- instead reuses the generic, COM-owned master_data_import_source document
-- type (itself only registered for real by this session's own
-- 20260917040000_register_master_data_import_source_document_type.sql).
--
-- That reuse is functionally UNBLOCKED (master_data_import_source is now a
-- real catalog row), unlike leave_opening_balance_import's prior state where
-- the fallback generic type was not registered for real at all. But it is
-- architecturally inconsistent with the convention this session's own
-- leave_opening_balance_import slice just established for this exact
-- situation: a genuinely HRS-owned, employee-linked cutover file (payroll
-- loan balances are arguably even more sensitive than leave balances --
-- personal debt/financial obligation data tied to an individual employee)
-- does not belong under a generic, commercial-master-data-flavoured document
-- type shared with customer_import/item_import. This migration instead
-- gives payroll_loan_cutover_import a dedicated document type, mirroring
-- timesheet_import_source's/attendance_device_import_source's/leave_opening_
-- balance_import_source's own one-document-type-per-HRS-import-schema
-- precedent.
--
-- Mirrors every prior A4 document-type-registration migration's own
-- identical shape verbatim: additive, idempotent (on conflict (code) do
-- nothing), registers only the two global catalogue rows every tenant's own
-- later publish call depends on -- never a per-tenant config_object (that
-- remains a separate, later, per-tenant admin action). No new function is
-- created here.
--
-- owner_primitive_code 'HRS' matches this same schema's own
-- payroll_loan_cutover_import registration (line 163 of the 20260901010000
-- migration), the module that actually owns this document type.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('payroll_loan_cutover_import_source', 'Payroll Loan Cutover Import Source File', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:payroll_loan_cutover_import_source', 'Payroll Loan Cutover Import Source File', 'HRS', 'system')
on conflict (code) do nothing;
