-- Orchestrating-session independent-verification fix (batch 5, CG-S11-PRC-017): the
-- persisted COMMENT ON FUNCTION added by 20260730790000's own fix #3
-- (app.list_procurement_dashboard_saved_views) describes the p_cursor_id-omitted
-- fallback as "the max uuid so a tie is at worst repeated once, never silently lost".
-- The function body actually coalesces to '00000000-0000-0000-0000-000000000000'::uuid
-- (the MINIMUM possible uuid), which -- per 20260730790000's own top-of-file design
-- note (the comment immediately above the function's CREATE) -- is the deliberately
-- chosen, deliberately reasoned-about fallback: it reproduces the OLD single-column
-- `created_at < p_cursor` behavior (a tie at the boundary is excluded, never returned
-- again), specifically BECAUSE a max-uuid fallback would cause the boundary row itself
-- to repeat forever at page size 1. The function's own persisted comment (what a
-- future reader sees via `\df+`/`pg_catalog`) contradicted the file's own design note
-- and the actual code. No behavior changes here -- COMMENT ON is metadata only, never
-- edits the already-applied 20260730790000 migration file itself.

comment on function app.list_procurement_dashboard_saved_views(uuid, text, uuid, integer, timestamptz, uuid) is
  'PRC-266: always scoped to the CALLING actor''s own views only (owner_auth_user_id = p_actor_auth_user_id), never another user''s, even for a tenant_admin -- "a user''s own" (Prompt 266 section 20) is literal. Tier C batch-5 fix (HIGH): cursor-paginated on a composite (created_at desc, id desc) keyset, not created_at alone -- a single-column cursor silently dropped every row sharing an exact created_at tie at a page boundary (live-reproduced); p_cursor_id defaults to null for a legacy single-timestamp caller, falling back to the MINIMUM possible uuid, reproducing the OLD single-column behavior (a tie at the boundary is excluded, never returned again -- a maximum-uuid fallback was deliberately rejected because it would repeat the boundary row forever at page size 1).';
