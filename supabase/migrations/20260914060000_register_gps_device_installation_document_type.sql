-- CG-AUDIT-2026-09-02 E5 ("Telematics: device can never reach `installed`,
-- blocked by A6"): app.record_gps_device_installation (ATW-226B,
-- 20260729350000_create_advanced_tms_device_installation_evidence.sql) and its
-- own db-test (scripts/db-tests/advanced-tms-device-installation-evidence.sql,
-- plus 5 other db-test files whose own fixtures independently register the
-- same document type: advanced-tms-canonical-telemetry-arbitration.sql,
-- advanced-tms-claim-incident-operations.sql [a different code, same
-- owner_primitive_code precedent], advanced-tms-geofence-route-deviation-
-- signals.sql, advanced-tms-gps-gateway-ingestion.sql, advanced-tms-wms-
-- integrated-verification.sql) both already fully build and exercise the
-- evidenced-installation RPC end to end -- but every one of those db-test
-- fixtures calls app.register_document_type('gps_device_installation', ...)
-- itself, against its own disposable database, and NO real migration ever
-- performed that same registration. Confirmed live via repo-wide grep before
-- writing this migration: zero hits for register_document_type(...
-- 'gps_device_installation'...) or the literal 'gps_device_installation'
-- outside those db-test files and the RPC's own validation logic. Since
-- app.resolve_document_type_definition (PLT-128, the function
-- app.initiate_file_upload always calls first) raises
-- document_type_not_configured whenever no tenant has EVER published a
-- 'document:<code>' config_object for that document type -- and a tenant can
-- never publish one until the matching app.config_types catalogue row exists
-- (app.register_document_type's own single entry point creates both rows
-- together) -- every real tenant's first attempt to upload GPS device
-- installation evidence would fail immediately, before ever reaching its own
-- per-tenant publish step. This is the actual, concrete blocker E5's own note
-- ("blocked by A6") points at: not a missing RPC (one already exists, fully
-- tested), but a missing platform-level catalogue registration.
--
-- Mirrors 20260901020000_register_loyalty_reward_terms_document_type.sql's own
-- identical shape verbatim: additive, idempotent (on conflict (code) do
-- nothing), registers only the two global catalogue rows every tenant's own
-- later publish call depends on -- never a per-tenant config_object (that
-- remains a separate, later, per-tenant admin action, exactly as every other
-- document type in this repository already requires). No new function is
-- created here.
--
-- code/name/owner_primitive_code reused VERBATIM from every one of those six
-- db-test fixtures' own identical register_document_type call (all six agree
-- byte-for-byte: 'gps_device_installation', 'GPS Device Installation
-- Evidence', 'DOC') -- 'DOC' (the generic Document and File Engine primitive,
-- PLT-128) rather than 'OPS', matching this repository's own established
-- convention for other generic evidence-photo document types that are not
-- owned by one single business module (e.g. 'epod'/'pod', also 'DOC') rather
-- than a business-module-owned type like 'customs_declaration' ('OPS') or
-- 'ticket_attachment' ('TKT'). Safe to apply even though those six db-test
-- fixtures' own register_document_type calls still run against their own
-- disposable databases on every db:test run: app.register_document_type is
-- itself read-if-exists (returns the existing row unchanged on a repeat call
-- with the same code), and this migration's own code/name/owner_primitive_code
-- values are identical to every one of those fixtures', so whichever writer
-- runs first is authoritative and every later one is a genuine no-op, never a
-- silent divergence -- identical reasoning to the loyalty precedent's own
-- note.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('gps_device_installation', 'GPS Device Installation Evidence', 'DOC', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:gps_device_installation', 'GPS Device Installation Evidence', 'DOC', 'system')
on conflict (code) do nothing;
