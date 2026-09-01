-- ISS-2026-131 item 3 (docs/runtime/KNOWN_ISSUES.md) -- the admin reward-create/edit form
-- accepts an existing app.files.id by direct text entry only; no dedicated uploader widget
-- exists. Closing that gap needs a real file input wired to PLT-128's own
-- app.initiate_file_upload, which requires a PUBLISHED document-type definition to exist
-- before any upload can succeed (app.resolve_document_type_definition raises
-- document_type_not_configured otherwise).
--
-- Live-verified before writing this migration (Supabase Management API against project
-- awdlicmwzdxquopwtcfd, 2026-09-01): app.document_types has no 'reward_terms' row,
-- app.config_types has no 'document:reward_terms' row, and app.config_objects has ZERO rows
-- with config_type_code like 'document:%' project-wide -- every tenant's own document-type
-- definition (for ANY document type, not just this one) still has to be published
-- separately per tenant; this migration only registers the two catalogue rows every tenant's
-- own publish call depends on, mirroring the identical two-insert shape
-- 20260801030000_create_customer_portal_quote_requests.sql already established for
-- 'quote_request_attachment' (CPT). No new function is created here.
--
-- Additive and idempotent (on conflict (code) do nothing) -- safe to apply even though
-- scripts/db-tests/customer-loyalty-reward-catalogue.sql's own disposable-DB fixture
-- already calls app.register_document_type('reward_terms', ...) directly: that fixture
-- runs register_document_type (an idempotent SECURITY DEFINER wrapper the platform ships,
-- supabase/migrations/20260719140000_create_document_file_engine.sql) against its own
-- throwaway database, never this migration's insert -- the two never collide, and either
-- one running first leaves the same row behind: register_document_type itself is
-- read-if-exists (returns the existing row unchanged, never updates name/owner_primitive_
-- code on a repeat call), and this migration's own `code`/`name`/`owner_primitive_code`
-- values are identical to the fixture's, so whichever writer runs first is authoritative
-- and the second is always a genuine no-op, not a silent divergence.
--
-- code reused VERBATIM ('reward_terms') per this migration's own charter: making the code
-- scripts/db-tests/customer-loyalty-reward-catalogue.sql already exercises real in the
-- live/shared schema, not inventing a second one.

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('reward_terms', 'Reward Terms Document', 'LYL', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:reward_terms', 'Reward Terms Document', 'LYL', 'system')
on conflict (code) do nothing;
