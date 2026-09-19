-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 0 batch 4 of ~4
-- (leads/prospects/quotations-directory/quotation-lines-directory/
-- quotation-approval-rules/quotation-acceptance-tokens, 6 of the remaining 10
-- tables). Continues the same Design->Verify->Fix adversarial pipeline batches
-- 1-3 established (RULE A/B/C baked into every draft and every independent
-- verify pass below), user-directed ("lanjut sampe siap launching") extension
-- of CG-AUDIT-2026-09-02's Ø1-query-layer finding: supabase/config.toml only
-- exposes "public"/"graphql_public" to PostgREST, so every .from() read
-- against the "app" schema has never worked in production.
--
-- 11 new app.*/public.* Option-2 wrapper function pairs across 6 tables:
--   app.leads:                        app.list_leads, app.get_lead_by_id
--   app.prospects:                    app.list_prospects, app.get_prospect_by_id
--   app.quotations_directory:         app.get_quotation_by_id,
--                                     app.list_quotation_versions,
--                                     app.list_quotations_for_opportunity,
--                                     app.list_quotations_for_tenant
--   app.quotation_lines_directory:    app.list_quotation_lines
--   app.quotation_approval_rules:     app.list_quotation_approval_rule_versions
--   app.quotation_acceptance_tokens:  app.list_quotation_acceptance_tokens
--
-- Every function below was independently adversarially re-verified against
-- the live repo state (not merely its own draft's claims) before being
-- included in this migration. Two real, security/data-relevant issues were
-- found and fixed during that verify pass, before this migration was ever
-- applied to any database:
--   * app.prospects: the first draft returned all 26 physical columns,
--     including normalized_legal_name/normalized_tax_id/duplicate_fingerprint/
--     disqualified_at/archived_at -- none of which is part of the real
--     ProspectSchema/parseProspect contract (server/contracts/prospect/
--     prospect.ts). Fixed to exclude all five, matching the same
--     "return exactly what the TS contract consumes" discipline batch 1's
--     app.contacts and this batch's own app.leads already established --
--     app.leads keeps its own duplicate_fingerprint only because LeadSchema
--     explicitly requires it; ProspectSchema has no such field, so
--     app.prospects' duplicate_fingerprint does not qualify for that
--     exception.
--   * app.quotations_directory: a documentation-only miscount (the header
--     prose claimed the view's current column count was 39; independently
--     recounting the live view's own SELECT list found 40). The actual
--     reproduced column lists in every function body and RETURNS TABLE
--     clause were already correct throughout -- this was a prose defect, not
--     a masking or authority bug -- and was corrected for accuracy.
-- All four other tables (app.leads, app.quotation_lines_directory,
-- app.quotation_approval_rules, app.quotation_acceptance_tokens) passed
-- independent adversarial re-verification with zero issues found.
--
-- All 3 affected TS query files (server/queries/lead.ts, prospect.ts,
-- quotation.ts, quotation-approval.ts, quotation-acceptance.ts) and every
-- real page.tsx call site are switched from .from() to .rpc() in this same
-- commit, per each function's own embedded TS INTEGRATION note below.

-- ===========================================================================
-- TABLE 1 of 6: app.leads
-- ===========================================================================
-- ===========================================================================
-- app.leads remediation -- Option-2 RPC surface
-- (app is not exposed to PostgREST; supabase/config.toml only exposes
-- "public"/"graphql_public")
-- ===========================================================================
--
-- Replaces two broken `.from("leads")` reads in server/queries/lead.ts:
--   :74 listLeads    -- select * (count exact) from leads, eq tenant_id,
--                        order last_activity_at desc, paginated range. Lead List page.
--   :94 getLeadById  -- select * from leads, eq id, maybeSingle. Lead Detail view.
-- assign_lead/capture_lead/qualify_lead/disqualify_lead/transition_lead_status/
-- merge_leads/score_lead/find_duplicate_leads are all mutations or narrow scoring/
-- duplicate-search helpers, not general reads -- no list_leads/get_lead_by_id
-- function existed before this migration (grepped "function app.list_leads" /
-- "function app.get_lead_by_id" across all of supabase/migrations/*.sql -- zero hits).
--
-- ---------------------------------------------------------------------------
-- TARGET TABLE AND COLUMN SHAPE
-- ---------------------------------------------------------------------------
-- app.leads is a REAL BASE TABLE (confirmed via `grep -n "create table app.leads"` --
-- exactly one hit, no "create view"/"create materialized view" hit for this name
-- anywhere in supabase/migrations/*.sql), created at
-- supabase/migrations/20260723090000_create_commercial_lead_management.sql:35-80:
--   id uuid, tenant_id uuid, source text, external_reference text, company_name text,
--   contact_name text, email text, phone text, normalized_email text,
--   normalized_phone text, duplicate_fingerprint text, status text,
--   disqualify_reason text, score integer, score_explanation jsonb,
--   score_version integer, owner_user_id uuid, org_unit_id uuid, assigned_at
--   timestamptz, assigned_by text, qualified_at timestamptz, disqualified_at
--   timestamptz, merged_into_id uuid, merged_at timestamptz, merged_by text,
--   converted_at timestamptz, last_activity_at timestamptz, record_version integer,
--   created_by text, created_at timestamptz, updated_at timestamptz.
-- One later column was added: `alter table app.leads add column
-- converted_prospect_id uuid references app.prospects (id);`
-- (supabase/migrations/20260723120000_create_commercial_prospect_lifecycle.sql:63,
-- plus its companion CHECK constraint at :68). Grepped "alter table app\.leads\b"
-- repo-wide -- that ADD COLUMN and the original migration's own `enable row level
-- security` are the only two hits; no other column has ever been added, dropped, or
-- retyped. The 31-column list above (30 original + converted_prospect_id) is
-- therefore the complete, current shape.
--
-- DELIBERATE COLUMN EXCLUSION: `normalized_email` and `normalized_phone` are
-- internal, computed correlation columns (populated by the `leads_set_computed_
-- fields` trigger, used only to derive `duplicate_fingerprint`) -- never part of the
-- Lead contract. `server/contracts/lead/lead.ts`'s `LeadSchema`/`parseLead` reads
-- every other column (including `duplicate_fingerprint` itself, which IS part of the
-- contract as a required, non-nullable string -- unlike the sibling app.contacts
-- remediation, which excluded its own duplicate_fingerprint too) but never reads
-- `normalized_email`/`normalized_phone`. Both new functions below select every
-- column except those two, matching `parseLead`'s own effective contract exactly --
-- narrower than the broken `.select("*")` call, the same "never select more than the
-- contract needs" discipline `app.list_contacts`/`app.get_contact_by_id`
-- (20260908020000) already applied to this exact table family.
--
-- ---------------------------------------------------------------------------
-- RULE B -- authority envelope (current RLS predicate, not the original)
-- ---------------------------------------------------------------------------
-- `create policy leads_select_scoped on app.leads` was declared exactly once, at
-- 20260723090000_create_commercial_lead_management.sql:635-643:
--     for select to authenticated
--     using (
--       app.can_access_record(
--         (select auth.uid()), tenant_id, owner_user_id,
--         app.lead_record_scope_org_unit_ids(org_unit_id),
--         null
--       )
--     );
-- Grepped BOTH `alter policy.*leads` and the bare policy name `leads_select_scoped`
-- across every file in supabase/migrations/*.sql, sorted by filename: the ONLY hits
-- are the original CREATE POLICY above and one unrelated comment referencing the
-- policy name in 20260723180000_create_commercial_sales_pipeline.sql:243 ("the
-- existing leads_select_scoped / prospects RLS policies..."), which does not alter
-- it. No ALTER POLICY on this table or policy exists anywhere. This is confirmed
-- independently by 20260730560000_harden_customer_user_layer_default_deny.sql's own
-- header, which explains its narrowing was applied ONLY to policies where tenant
-- membership was the ENTIRE test, and explicitly excludes "any policy already
-- carrying ... app.can_access_record ... those are ... already fail closed on their
-- own" -- app.leads' policy already routes through app.can_access_record, so it was
-- correctly left untouched by that sweep (grepped "leads" in that migration file
-- directly -- zero hits, confirming it). The predicate above is therefore still the
-- CURRENT, unaltered authority envelope for reading app.leads. Both new functions
-- below reproduce it exactly (neither wider nor narrower), evaluated per row since
-- SECURITY DEFINER bypasses RLS and must re-implement it explicitly.
--
-- ---------------------------------------------------------------------------
-- RULE C -- precedent staleness check
-- ---------------------------------------------------------------------------
-- Helper signatures used below, each confirmed to be its own most-recent
-- CREATE OR REPLACE:
--   app.can_access_record(p_auth_user_id uuid, p_tenant_id uuid, p_owner_user_id uuid,
--     p_shared_org_unit_ids uuid[], p_customer_account_ref text)
--     -- grepped "create or replace function app.can_access_record" / "create function
--     -- app.can_access_record" repo-wide: exactly two hits -- the PLT-114 original
--     -- (20260716110430_create_field_record_access.sql) and the COM-146 replacement
--     -- (20260723180000_create_commercial_sales_pipeline.sql:50), which fixed a real
--     -- NULL-owner-defeats-the-guard defect. No later replace exists. This current
--     -- (COM-146) 5-arg body is what both functions below call.
--   app.lead_record_scope_org_unit_ids(p_org_unit_id uuid)
--     -- grepped repo-wide: exactly ONE definition, ever
--     -- (20260723090000_create_commercial_lead_management.sql:164) -- never replaced.
--   app.assert_actor_is_session_identity(p_actor_auth_user_id uuid)
--     -- grepped repo-wide: exactly ONE definition, ever
--     -- (20260730440000_harden_actor_identity_session_crosscheck.sql:59) -- never
--     -- replaced.
--
-- AUTHORITY-CHECK PRECEDENT (RULE C applied): modeled on `app.list_contacts` /
-- `app.get_contact_by_id` (supabase/migrations/20260908020000_close_o1_query_layer_
-- cluster0_batch1_crm_core.sql:898-959, 1039-1097) -- the closest same-shape,
-- already-adversarially-reviewed precedent in this exact backlog: a `can_access_
-- record`-gated (not merely tenant-membership-gated) table, same `app.lead_record_
-- scope_org_unit_ids` helper, same "RLS is the real scope gate, so a non-member or a
-- member with zero visible rows silently yields an empty result, never a thrown
-- error" contract as this table's own `leads_select_scoped` policy and the original
-- `.from()` calls both already had. `app.list_opportunities`/`app.list_accounts`
-- (same backlog, 20260908020000 and 20260909000000) independently confirm the same
-- `order by <col> desc, id desc` tie-break and `count(*) over()` pagination idiom.
--
-- Explicitly checked and NOT followed as precedent, because each is either stale or
-- the wrong shape:
--   * `app.find_duplicate_leads` (this table's own most obvious same-file sibling,
--     20260723090000:220-252) checks ONLY `app.has_active_tenant_membership`, with NO
--     `app.can_access_record`/org-unit-scope narrowing at all -- broader than
--     `leads_select_scoped`'s own RLS envelope. It has never been replaced (grepped
--     "create or replace function app.find_duplicate_leads" repo-wide -- zero hits;
--     the 20260723090000 original is still its only, current body), so it is not even
--     a stale-but-since-widened case -- it was simply always narrower in scope
--     (tenant-only) than what a general list/get read must reproduce. Copying its
--     predicate forward would OVER-GRANT relative to `leads_select_scoped` and is
--     rejected for that reason, exactly as batch 1's header rejected
--     `find_duplicate_contacts` as precedent for `list_contacts`/`get_contact_by_id`
--     for the identical reason.
--   * `app.assign_lead` -- checked for its RULE A shape since it is this table's own
--     sibling mutation. Grepped "CREATE OR REPLACE FUNCTION app.assign_lead" repo-wide:
--     it was originally created at 20260723090000 WITHOUT an assert call, patched to
--     ADD `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as its
--     first statement at 20260730510000_harden_actor_identity_unchecked_authority_
--     surface.sql:376-441 (ATW-032) -- but its MOST RECENT replacement,
--     20260902200000_harden_tenant_id_disclosure_commercial.sql:420-487 (which fixed an
--     unrelated stale-version-no-op defect, ISS-2026-034), silently DROPPED that assert
--     call again -- the current, live body of app.assign_lead has NO actor-identity
--     check. This is a genuine, apparently-unnoticed RULE A regression in existing
--     mutation code, but `app.assign_lead` is a mutation, out of scope for this
--     read-only remediation, and is NOT touched or re-fixed here -- flagged instead as
--     an open question below. The regression is exactly why it is REJECTED as RULE A
--     precedent for the two new functions below (which correctly include the assert
--     call, modeled on `list_contacts`/`get_contact_by_id` instead) -- copying
--     `assign_lead`'s current body forward would have reintroduced the same hole this
--     migration must not create in brand-new code. (`app.convert_lead_to_prospect`,
--     20260902200000:909-975, was also checked and never had the assert call at all in
--     any version -- same disclosed-but-out-of-scope pattern, same rejection.)
--
-- ---------------------------------------------------------------------------
-- PAGINATION (rule 8)
-- ---------------------------------------------------------------------------
-- listLeads' own existing, unchanged external contract (`ListLeadsResult.totalCount`,
-- `ListLeadsInput.page`/`pageSize`, and the original `.select("*", {count:"exact"})`
-- + `.range()` call) requires an exact total count and the ability to jump to an
-- arbitrary page number -- exactly `app.list_contacts`/`app.list_opportunities`'s own
-- shape (`p_page`/`p_page_size` plus a `count(*) over()` window column), not the
-- newer `p_limit`/`p_after_id` keyset idiom used for finance lists (which cannot
-- support arbitrary-page jumps or an exact total). `app.list_leads` below reproduces
-- that identical `p_page`/`p_page_size` + `count(*) over()` shape, clamped
-- server-side to the same bounds `server/queries/lead.ts`'s own `MAX_PAGE_SIZE`
-- (100) / `DEFAULT_PAGE_SIZE` (50) constants already enforce client-side -- defense
-- in depth, since an RPC is directly callable and must not trust a caller-supplied
-- page size. One small, disclosed addition over the original
-- `.order("last_activity_at", {ascending: false})` call (no secondary sort key at
-- all): `order by last_activity_at desc, id desc` adds `id` as a tie-breaker, the
-- same technique `app.list_contacts`/`app.list_opportunities` already use, to make
-- paging deterministic when multiple leads share a `last_activity_at` timestamp --
-- flagged in openQuestions as a minor, deliberate improvement rather than a
-- byte-for-byte behavior match.
--
-- ---------------------------------------------------------------------------
-- Design notes shared by both functions
-- ---------------------------------------------------------------------------
-- * Neither function pre-flight-raises on missing tenant membership (unlike
--   `app.find_duplicate_leads`/`app.capture_lead`): both reads' own existing
--   contract is "RLS is the real scope gate" (see `listLeads`/`getLeadById`'s own
--   doc-comments in server/queries/lead.ts, "RLS ... is the real access gate, not a
--   second check in this layer") -- a non-member or a member with zero visible rows
--   both silently yield an empty result (empty page / null), exactly as the
--   RLS-filtered `.from("leads")` calls already do today, never a thrown error.
--   `app.can_access_record`'s own first AND-clause is `app.has_active_tenant_
--   membership`, so a non-member is filtered out identically either way -- the same
--   rule, applied as a row filter instead of a guard clause, to preserve the exact
--   current no-error-on-non-member behavior (mirrors `app.list_contacts`/`app.
--   get_contact_by_id`'s identical choice for this exact reason).
-- * `app.get_lead_by_id` takes NO explicit `p_tenant_id` -- the original
--   `.eq("id", leadId).maybeSingle()` call site never supplied one either, relying
--   purely on RLS to filter the one candidate row by its own tenant_id. Reproducing
--   that means evaluating the authority predicate against THIS row's own tenant_id,
--   and returning SETOF (zero or one row) rather than raising, so "no such id" and
--   "exists but denied" both collapse to an empty result -- the same anti-enumeration
--   property `.maybeSingle()` under real RLS already had; the TS caller keeps
--   returning `null` on an empty result exactly as before.
--
-- Both functions take an explicit `p_actor_auth_user_id` and are granted to
-- `authenticated` (not service_role-only) -- RULE A applies to both:
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- executable statement in each, before any lookup or authority check.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit `revoke execute ... from
-- public` per function below, plus the standing blanket statement. Per ISS-2026-309
-- (closed by 20260830200000_correct_public_wrapper_grant_parity.sql): every
-- `public.*` wrapper below revokes from `anon, authenticated, service_role, public`
-- (all four) before re-granting only the intended subset, since Supabase's own
-- ALTER DEFAULT PRIVILEGES rule grants `anon`/`authenticated` EXECUTE directly at
-- CREATE FUNCTION time in schema `public`.
-- ===========================================================================

-- ===========================================================================
-- 1. app.list_leads -- replaces server/queries/lead.ts:74 (listLeads)
-- ===========================================================================
create function app.list_leads(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  source text,
  external_reference text,
  company_name text,
  contact_name text,
  email text,
  phone text,
  duplicate_fingerprint text,
  status text,
  disqualify_reason text,
  score integer,
  score_explanation jsonb,
  score_version integer,
  owner_user_id uuid,
  org_unit_id uuid,
  assigned_at timestamptz,
  assigned_by text,
  qualified_at timestamptz,
  disqualified_at timestamptz,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  converted_at timestamptz,
  converted_prospect_id uuid,
  last_activity_at timestamptz,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
  v_page integer;
begin
  -- RULE A (ISS-2026-017/032, HDN-372/373): first executable statement, before any
  -- lookup or authority check -- the claimed actor must genuinely be the calling
  -- session, never merely an actor the caller asserts is allowed.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  -- No pre-flight has_active_tenant_membership raise: this read's own existing
  -- contract (server/queries/lead.ts's own doc-comment, "RLS (leads_select_scoped)
  -- is the real scope gate") is that a non-member or a member with zero visible
  -- rows both silently yield an empty page (totalCount 0), exactly as the
  -- RLS-filtered `.from("leads")` call already does today -- mirrors
  -- app.list_contacts'/app.list_opportunities' own identical choice
  -- (20260908020000 / 20260909000000) for the same reason.
  return query
    select
      l.id,
      l.tenant_id,
      l.source,
      l.external_reference,
      l.company_name,
      l.contact_name,
      l.email,
      l.phone,
      l.duplicate_fingerprint,
      l.status,
      l.disqualify_reason,
      l.score,
      l.score_explanation,
      l.score_version,
      l.owner_user_id,
      l.org_unit_id,
      l.assigned_at,
      l.assigned_by,
      l.qualified_at,
      l.disqualified_at,
      l.merged_into_id,
      l.merged_at,
      l.merged_by,
      l.converted_at,
      l.converted_prospect_id,
      l.last_activity_at,
      l.record_version,
      l.created_by,
      l.created_at,
      l.updated_at,
      count(*) over() as total_count
    from app.leads l
    where l.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, l.tenant_id, l.owner_user_id,
        app.lead_record_scope_org_unit_ids(l.org_unit_id), null
      )
    order by l.last_activity_at desc, l.id desc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_leads(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1: paginated Lead List read, replacing server/queries/lead.ts:74''s broken .from("leads") (app is not exposed to PostgREST). Row filter reproduces app.leads'' own leads_select_scoped RLS predicate exactly (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) -- unaltered since 20260723090000, confirmed via grep for a later ALTER POLICY, none found), never a second, different authority rule. normalized_email/normalized_phone are deliberately excluded (internal duplicate-detection correlation columns, never part of the Lead contract); duplicate_fingerprint itself IS returned, since parseLead/LeadSchema require it. total_count is an exact count(*) over() of every row matching the WHERE clause before LIMIT/OFFSET, mirroring app.list_contacts''/app.list_opportunities'' identical technique for the same "exact count, arbitrary page number" external contract. order by last_activity_at desc, id desc adds an id tie-break the original .order() call did not have, for deterministic paging across rows sharing a timestamp. A non-member or zero-visible-row actor gets an empty page, never a thrown error.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_leads with an identical grant set, never a
-- reimplementation.
create function public.list_leads(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  source text,
  external_reference text,
  company_name text,
  contact_name text,
  email text,
  phone text,
  duplicate_fingerprint text,
  status text,
  disqualify_reason text,
  score integer,
  score_explanation jsonb,
  score_version integer,
  owner_user_id uuid,
  org_unit_id uuid,
  assigned_at timestamptz,
  assigned_by text,
  qualified_at timestamptz,
  disqualified_at timestamptz,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  converted_at timestamptz,
  converted_prospect_id uuid,
  last_activity_at timestamptz,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_leads(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_leads(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_leads with an identical grant set, never a reimplementation.';

revoke execute on function app.list_leads(uuid, uuid, integer, integer) from public;
grant execute on function app.list_leads(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_leads(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_leads(uuid, uuid, integer, integer) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_lead_by_id -- replaces server/queries/lead.ts:94 (getLeadById)
-- ===========================================================================
create function app.get_lead_by_id(
  p_lead_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  source text,
  external_reference text,
  company_name text,
  contact_name text,
  email text,
  phone text,
  duplicate_fingerprint text,
  status text,
  disqualify_reason text,
  score integer,
  score_explanation jsonb,
  score_version integer,
  owner_user_id uuid,
  org_unit_id uuid,
  assigned_at timestamptz,
  assigned_by text,
  qualified_at timestamptz,
  disqualified_at timestamptz,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  converted_at timestamptz,
  converted_prospect_id uuid,
  last_activity_at timestamptz,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_lead from app.leads l where l.id = p_lead_id;

  -- Anti-enumeration, matching this read's own current contract (server/queries/
  -- lead.ts:92's own doc-comment: "the caller must treat null as 'not found or not
  -- accessible'") and app.get_contact_by_id's identical idiom (20260908020000): a
  -- nonexistent id and an id the actor cannot access both collapse to zero rows,
  -- never a thrown error -- exactly RLS's own behavior today.
  if not found
     or not app.can_access_record(
       p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
       app.lead_record_scope_org_unit_ids(v_lead.org_unit_id), null
     )
  then
    return;
  end if;

  -- Deliberate column exclusion (per this migration's own header): never return
  -- normalized_email/normalized_phone, matching app.list_leads.
  id := v_lead.id;
  tenant_id := v_lead.tenant_id;
  source := v_lead.source;
  external_reference := v_lead.external_reference;
  company_name := v_lead.company_name;
  contact_name := v_lead.contact_name;
  email := v_lead.email;
  phone := v_lead.phone;
  duplicate_fingerprint := v_lead.duplicate_fingerprint;
  status := v_lead.status;
  disqualify_reason := v_lead.disqualify_reason;
  score := v_lead.score;
  score_explanation := v_lead.score_explanation;
  score_version := v_lead.score_version;
  owner_user_id := v_lead.owner_user_id;
  org_unit_id := v_lead.org_unit_id;
  assigned_at := v_lead.assigned_at;
  assigned_by := v_lead.assigned_by;
  qualified_at := v_lead.qualified_at;
  disqualified_at := v_lead.disqualified_at;
  merged_into_id := v_lead.merged_into_id;
  merged_at := v_lead.merged_at;
  merged_by := v_lead.merged_by;
  converted_at := v_lead.converted_at;
  converted_prospect_id := v_lead.converted_prospect_id;
  last_activity_at := v_lead.last_activity_at;
  record_version := v_lead.record_version;
  created_by := v_lead.created_by;
  created_at := v_lead.created_at;
  updated_at := v_lead.updated_at;
  return next;
end;
$$;

comment on function app.get_lead_by_id(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: single-lead read for the Lead Detail view, replacing server/queries/lead.ts:94''s broken .from("leads") (app is not exposed to PostgREST). Authority predicate reproduces app.leads'' own leads_select_scoped RLS predicate exactly (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) -- unaltered since 20260723090000, confirmed via grep for a later ALTER POLICY, none found), evaluated against this row''s own tenant_id (no p_tenant_id parameter, matching the original .eq("id", ...) call''s own lack of a tenant filter). Returns zero rows (never an exception) for a nonexistent id or one the actor cannot access, matching both the current .from()+RLS behavior and app.get_contact_by_id''s own anti-enumeration posture -- a caller cannot distinguish "does not exist" from "exists, not yours". normalized_email/normalized_phone are deliberately excluded, matching app.list_leads.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_lead_by_id with an identical grant set, never a
-- reimplementation.
create function public.get_lead_by_id(
  p_lead_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  source text,
  external_reference text,
  company_name text,
  contact_name text,
  email text,
  phone text,
  duplicate_fingerprint text,
  status text,
  disqualify_reason text,
  score integer,
  score_explanation jsonb,
  score_version integer,
  owner_user_id uuid,
  org_unit_id uuid,
  assigned_at timestamptz,
  assigned_by text,
  qualified_at timestamptz,
  disqualified_at timestamptz,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  converted_at timestamptz,
  converted_prospect_id uuid,
  last_activity_at timestamptz,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_lead_by_id(p_lead_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_lead_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_lead_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_lead_by_id(uuid, uuid) from public;
grant execute on function app.get_lead_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_lead_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_lead_by_id(uuid, uuid) to authenticated, service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-execute
-- default, applied before the role-specific grants above are relied upon (the
-- individual `revoke ... from public` lines per function above are kept too, for the
-- same belt-and-suspenders reason every other checkpoint in this repository keeps
-- them; this final sweep is the standing convention's closing statement, not a
-- substitute for the per-function grant hygiene above).
revoke execute on function app.list_leads(uuid, uuid, integer, integer) from public;
revoke execute on function app.get_lead_by_id(uuid, uuid) from public;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping)
-- ===========================================================================
-- RULE A: both app.* functions above take an explicit p_actor_auth_user_id and are
-- granted to `authenticated` -- in both, `perform app.assert_actor_is_session_
-- identity(p_actor_auth_user_id);` is the first statement inside `begin ... end`,
-- before any lookup, any can_access_record call, and any `return query`/`return
-- next`. Neither relies on the "service_role-only" exception, so neither needed to
-- invoke it. Their public.* wrappers are LANGUAGE SQL pass-throughs with no
-- authority logic of their own (correctly so -- RULE A applies to the app.*
-- function that does the actual check, not to a wrapper that only forwards
-- arguments), consistent with every other Option-2 wrapper in this backlog.
--
-- RULE B: grepped "alter policy.*leads" and the bare policy name
-- "leads_select_scoped" across every file in supabase/migrations/*.sql (not just
-- nearby ones), sorted by filename. Exactly one substantive hit -- the original
-- CREATE POLICY (20260723090000) -- plus one unrelated comment mention
-- (20260723180000:243) that does not alter it. No ALTER POLICY on app.leads or on
-- leads_select_scoped exists anywhere. Independently cross-checked against
-- 20260730560000_harden_customer_user_layer_default_deny.sql directly (grepped
-- "leads" in that file -- zero hits), confirming app.leads was correctly left out of
-- that sweep because its policy already routes through app.can_access_record. The
-- predicate reproduced in both functions above is therefore still the CURRENT,
-- only-ever version: app.can_access_record(actor, tenant_id, owner_user_id,
-- app.lead_record_scope_org_unit_ids(org_unit_id), null).
-- ===========================================================================

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/lead.ts.
--
-- 1. listLeads (currently line 67, typed `client: Pick<SupabaseClient, "from">`):
--    - Change the client parameter type to `LeadQueryRpcClient` (the
--      `Pick<SupabaseClient, "rpc">` alias already defined and already used by
--      findDuplicateLeads/findExistingAccountsForLead above in this same file).
--    - Add `actorAuthUserId: string` to `ListLeadsInput` (its one call site --
--      the Lead List page -- already resolves the acting user's auth_user_id
--      via the same commercial access-resolution helper every other Commercial
--      query in this codebase uses, e.g. `access.authUserId`).
--    - Replace the body:
--        const { data, error, count } = await client
--          .from("leads")
--          .select("*", { count: "exact" })
--          .eq("tenant_id", input.tenantId)
--          .order("last_activity_at", { ascending: false })
--          .range(from, to);
--      with:
--        const { data, error } = await client.rpc("list_leads", {
--          p_tenant_id: input.tenantId,
--          p_actor_auth_user_id: input.actorAuthUserId,
--          p_page: page,
--          p_page_size: pageSize,
--        });
--      (keep the existing `page`/`pageSize` clamping logic exactly as-is -- it
--      still bounds what gets sent as p_page/p_page_size; the `from`/`to` range
--      variables and the separate `count` destructure both go away).
--    - `count: "exact"`'s separate `count` return value goes away; total_count now
--      rides on each returned row. Map it as:
--        const rows = (data ?? []) as Record<string, unknown>[];
--        const totalCount = rows.length > 0 ? Number(rows[0].total_count) : 0;
--        return {
--          leads: rows.map((row) => parseLead(row)),
--          totalCount,
--          page,
--          pageSize,
--        };
--      (parseLead already ignores the extra total_count field on each row -- no
--      contract change needed on server/contracts/lead/lead.ts; the RPC never
--      returns normalized_email/normalized_phone at all, which parseLead never
--      read anyway).
--    - Error handling is unchanged: `if (error) throw new LeadQueryError(error.message);`.
--    - Return type is unchanged: `Promise<ListLeadsResult>`.
--
-- 2. getLeadById (currently line 93, typed `client: Pick<SupabaseClient, "from">`,
--    `leadId: string`):
--    - Change the client parameter type to `LeadQueryRpcClient`.
--    - Add a required `actorAuthUserId: string` parameter (its one call site, the
--      Lead Detail page, already has the acting user's auth_user_id in scope).
--    - Replace the body:
--        const { data, error } = await client.from("leads").select("*").eq("id", leadId).maybeSingle();
--      with:
--        const { data, error } = await client.rpc("get_lead_by_id", {
--          p_lead_id: leadId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--      if (error) throw new LeadQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseLead(row as Record<string, unknown>);
--    - Note: a `returns table(...)` RPC comes back as an array (empty array, not
--      null, when no row is visible) -- `Array.isArray(data) ? data[0] : data`
--      yields `undefined` in that case, so `!row` still correctly maps to the
--      "not found or not accessible" `null` return, matching the replaced
--      `.maybeSingle()` semantics exactly.
--    - Return type is unchanged: `Promise<Lead | null>`; the "not found or denied
--      -> null, never distinguished" contract in its own doc-comment is preserved
--      exactly.
--
-- 3. Call-site mechanical changes (no other logic changes needed): every existing
--    call site of `listLeads(client, { tenantId, page, pageSize })` and
--    `getLeadById(client, leadId)` (the Lead List page and Lead Detail page,
--    plus server/queries/lead.test.ts's fake-client fixtures) must additionally
--    pass `actorAuthUserId`, and lead.test.ts's `.from`-shaped stubs for these two
--    functions must be replaced with `.rpc("list_leads", ...)` /
--    `.rpc("get_lead_by_id", ...)` stubs, mirroring how this same file's existing
--    findDuplicateLeads/findExistingAccountsForLead tests already stub `.rpc(...)`.
-- ===========================================================================

-- ===========================================================================
-- OPEN QUESTIONS / DISCLOSED RESIDUAL RISK (not fixed by this migration; out of
-- its read-only scope, flagged for whoever owns the mutation surface)
-- ===========================================================================
-- 1. app.assign_lead's CURRENT body (20260902200000_harden_tenant_id_disclosure_
--    commercial.sql:420-487) no longer calls app.assert_actor_is_session_identity,
--    even though an earlier patch (20260730510000, ATW-032) had added it -- a later,
--    unrelated fix (ISS-2026-034, stale-version-no-op) appears to have been built on
--    top of the pre-ATW-032 body and silently dropped the assert call. This is a
--    live RULE A gap in existing mutation code, not introduced or touched by this
--    migration. app.convert_lead_to_prospect (20260902200000:909-975) similarly has
--    never had the assert call in any version. Both are mutations, outside this
--    task's read-only scope (app.list_leads/app.get_lead_by_id), and are left
--    exactly as they are -- recorded here rather than silently left for someone to
--    rediscover.
-- 2. order by last_activity_at desc, id desc (both new functions... actually only
--    app.list_leads orders) adds an id tie-break the original `.order()` call did
--    not have. This is a minor, deliberate determinism improvement (matching
--    app.list_contacts/app.list_opportunities' own established convention for this
--    exact backlog), not a byte-for-byte behavior match -- disclosed, not hidden.
-- ===========================================================================

-- ===========================================================================
-- TABLE 2 of 6: app.prospects
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1 query-layer remediation -- app.prospects (COM-144, CG-S7-COM-003).
--
-- supabase/config.toml exposes only public/graphql_public to PostgREST; app is completely
-- invisible to it. server/queries/prospect.ts:86 (listProspects) and :106 (getProspectById)
-- both call supabase.from("prospects")..., which can never resolve in production. This
-- follows the exact "Option-2" pattern already proven across three prior batches
-- (account.ts/contact.ts/contract.ts/costing.ts in
-- 20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql, and the pipeline/
-- margin/opportunity and costing/credit/quotation-approval batches that followed it): a
-- real, SECURITY DEFINER app.* function that re-implements the equivalent SELECT with
-- explicit tenant/actor authority scoping, plus a thin public.* SECURITY DEFINER
-- pass-through wrapper (app is not exposed to PostgREST, so public.* is the only reachable
-- surface), with an identical grant set on both.
--
-- archive_prospect/disqualify_prospect/convert_lead_to_prospect/merge_prospects are
-- mutations (already exist, unaffected); find_duplicate_prospects/
-- get_prospect_conversion_readiness are narrow RPCs with different shapes (fingerprint
-- match; fixed-rule readiness check). No general list-the-queue or get-by-id read exists
-- today for this table -- both functions below are new.
--
-- ============================================================================
-- TARGET TABLE -- app.prospects (real BASE TABLE, not a view)
-- ============================================================================
-- Created at supabase/migrations/20260723120000_create_commercial_prospect_lifecycle.sql
-- (`create table app.prospects`, lines 15-52):
--   id uuid, tenant_id uuid, lead_id uuid, legal_name text, trade_name text, tax_id text,
--   normalized_legal_name text, normalized_tax_id text, duplicate_fingerprint text,
--   billing_address jsonb, contact_name text, contact_email text, contact_phone text,
--   status text, disqualify_reason text, owner_user_id uuid, org_unit_id uuid,
--   merged_into_id uuid, merged_at timestamptz, merged_by text, record_version integer,
--   created_by text, created_at timestamptz, updated_at timestamptz.
-- Grepped "alter table app.prospects" across every file in supabase/migrations/*.sql
-- (RULE B applies to column shape too, not just policies): exactly one later hit, at
-- supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:100-101, which
-- adds two nullable columns:
--   disqualified_at timestamptz  (set by app.disqualify_prospect, superseded via
--                                 CREATE OR REPLACE in that same migration, lines 109-161)
--   archived_at timestamptz      (set by app.archive_prospect, superseded the same way,
--                                 lines 163-209)
-- No other add/drop/alter-column statement exists anywhere later. Full, current column
-- list (base CREATE TABLE plus these two later columns, in physical order) is exactly the
-- 26 columns both functions below enumerate.
--
-- Column exclusion (CORRECTED on review -- the original draft's "no exclusion was
-- specified in the task notes, so return every column" reasoning was wrong; it never
-- actually checked the TS contract). server/contracts/prospect/prospect.ts's
-- ProspectSchema/parseProspect were read directly: ProspectSchema defines exactly 21
-- fields (id, tenantId, leadId, legalName, tradeName, taxId, billingAddress,
-- contactName, contactEmail, contactPhone, status, disqualifyReason, ownerUserId,
-- orgUnitId, mergedIntoId, mergedAt, mergedBy, recordVersion, createdBy, createdAt,
-- updatedAt), and parseProspect maps only those 21 snake_case columns. It does NOT
-- define normalizedLegalName, normalizedTaxId, or duplicateFingerprint -- the same
-- internal identity-correlation-column class app.contacts (batch 1) excluded as
-- normalized_email/normalized_phone/duplicate_fingerprint, and the same class app.leads
-- (sibling batch) partially excluded as normalized_email/normalized_phone. app.leads
-- kept its own duplicate_fingerprint only because LeadSchema literally requires it
-- (`duplicateFingerprint: z.string()`); ProspectSchema has no such field, so
-- app.prospects' duplicate_fingerprint does not qualify for that exception and must be
-- excluded along with normalized_legal_name/normalized_tax_id. ProspectSchema also has
-- no disqualifiedAt/archivedAt field, and grepping app/(tenant)/**/commercial/prospects/**
-- confirms neither disqualified_at nor archived_at is read anywhere in the UI layer
-- either. Both functions below therefore exclude all five non-contract columns --
-- normalized_legal_name, normalized_tax_id, duplicate_fingerprint, disqualified_at,
-- archived_at -- returning exactly the 21 columns ProspectSchema/parseProspect consume.
-- This matches the app.contacts/app.leads precedent's actual rule ("return what the TS
-- contract needs," not "return whatever the replaced `select *` happened to return"),
-- and closes a PII/identity-correlation-column leak the original draft would otherwise
-- have shipped through the new public RPC surface.
--
-- ============================================================================
-- RULE B -- current RLS predicate (app.prospects_select_scoped)
-- ============================================================================
-- create policy prospects_select_scoped on app.prospects
--   for select to authenticated
--   using (
--     app.can_access_record(
--       (select auth.uid()), tenant_id, owner_user_id,
--       app.lead_record_scope_org_unit_ids(org_unit_id),
--       null
--     )
--   );
-- (20260723120000_create_commercial_prospect_lifecycle.sql:522-530 -- the original,
-- and only, creation.)
--
-- Confirmed via grep across ALL of supabase/migrations/*.sql, sorted by filename:
--   grep -n "create policy" ... | grep prospects_select_scoped  -> exactly ONE hit,
--     the 20260723120000 creation above.
--   grep -n "alter policy.*prospects" (repo-wide)                -> ZERO hits.
--   grep -n "prospects_select_scoped" (repo-wide, any statement) -> the single hit above
--     only; no other file even mentions this policy name.
--   grep -n "drop policy.*prospect" (repo-wide)                  -> ZERO hits.
-- In particular, 20260730560000_harden_customer_user_layer_default_deny.sql (the
-- migration that added "AND NOT app.actor_holds_customer_user_layer(tenant_id)" to
-- app.accounts/app.contacts/app.customer_contracts/app.credit_profiles/etc.) does NOT
-- touch app.prospects at all (grepped "prospect" case-insensitively inside that file --
-- no hit). This is consistent with app.prospects never having been reachable by a
-- customer_user-layer principal via has_active_tenant_membership alone in the first
-- place -- its policy was never has_active_tenant_membership-only, it was already the
-- narrower app.can_access_record predicate from day one (the same shape 20260730560000
-- was busy retrofitting onto OTHER tables). Conclusion: the predicate above, exactly as
-- originally written, is still the CURRENT, unaltered authority envelope for reading
-- app.prospects. Both new functions below reproduce it exactly (neither wider nor
-- narrower), row by row, since SECURITY DEFINER bypasses RLS and must restate it
-- explicitly.
--
-- ============================================================================
-- RULE C -- precedent staleness check
-- ============================================================================
-- app.can_access_record -- grep -rln "function app.can_access_record" supabase/
-- migrations/*.sql, sorted:
--   20260716110430_create_field_record_access.sql        (ORIGINAL, PLT-114)
--   20260723180000_create_commercial_sales_pipeline.sql   (CREATE OR REPLACE, COM-146)
-- No later replace exists. The COM-146 body (5-arg: p_auth_user_id, p_tenant_id,
-- p_owner_user_id, p_shared_org_unit_ids, p_customer_account_ref) is used below, per the
-- policy text itself -- NOT the stale PLT-114 original.
--
-- app.assert_actor_is_session_identity -- grep confirms exactly one definition
-- (20260730440000_harden_actor_identity_session_crosscheck.sql:59, ATW-031/ISS-2026-017),
-- never replaced. RULE A's leading call in both functions below.
--
-- app.lead_record_scope_org_unit_ids -- grep confirms exactly one definition
-- (20260723090000_create_commercial_lead_management.sql:164), never replaced.
--
-- Authority-check precedent modeled on: app.list_contacts / app.get_contact_by_id
-- (batch 1, 20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:898-1138) --
-- the closest possible sibling, because app.contacts'
-- own unaltered contacts_select_scoped predicate (`app.can_access_record(actor,
-- tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)`) is
-- LOGICALLY IDENTICAL in shape to app.prospects' own prospects_select_scoped above --
-- same helper, same argument order, same "no tenant-membership-only shortcut, no
-- customer_user-layer exclusion" structure. That precedent's own "no pre-flight raise;
-- apply the predicate as a per-row WHERE filter so a non-member/zero-visibility actor
-- gets a silent empty page (never an exception), matching what RLS already did" and "zero
-- rows (never an exception) collapses not-found and not-visible for get-by-id" contracts
-- are reproduced verbatim below, for the same reason: neither original `.from()` call
-- site raised on an empty/denied result, and RLS could never distinguish the two cases
-- either.
--
-- NOT used as authority precedent: app.find_duplicate_prospects. Per RULE C, its most
-- recent body is the 20260810400000_harden_crm_ops_actor_identity_gaps.sql:180
-- CREATE OR REPLACE (which added assert_actor_is_session_identity -- confirmed via grep,
-- no later replace exists), but even that current body still gates ONLY on
-- `app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)`, never
-- app.can_access_record -- i.e. it is, and always was, DELIBERATELY BROADER than
-- prospects_select_scoped's own RLS envelope (a disclosed exception for
-- duplicate-detection during conversion, exactly like app.find_duplicate_contacts /
-- app.find_duplicate_accounts on their own tables). Copying that forward here would
-- over-grant relative to the policy these two directory/detail reads must mirror, so it
-- is rejected as precedent for list_prospects/get_prospect_by_id specifically -- the same
-- reasoning the batch-1 app.contacts migration already applied to reject
-- find_duplicate_contacts as its own precedent.
--
-- ============================================================================
-- PAGINATION SHAPE
-- ============================================================================
-- The replaced call (server/queries/prospect.ts:85-90) is
-- `.from("prospects").select("*", { count: "exact" }).eq("tenant_id", ...)
-- .order("updated_at", { ascending: false }).range(from, to)`, feeding
-- ListProspectsResult.totalCount into components/tables/pagination.tsx's numbered
-- page-N UI (app/(tenant)/[tenantSlug]/commercial/prospects/page.tsx) -- an exact total
-- count and jump-to-arbitrary-page-number requirement, exactly like listContacts'. This
-- reproduces app.list_contacts' own established technique for that exact requirement: a
-- plain OFFSET/LIMIT plus a `count(*) over()` window column computed once per query (same
-- semantics and per-request cost as PostgREST's own `count: "exact"`), rather than this
-- schema's newer keyset (p_limit/p_after_id) list convention, which cannot support
-- jump-to-page. p_page/p_page_size are defensively clamped server-side
-- (least/greatest), matching prospect.ts's own existing MAX_PAGE_SIZE=100/
-- DEFAULT_PAGE_SIZE=50 client-side clamp exactly, since an RPC is directly callable and
-- must not trust a caller-supplied page size.
-- ============================================================================

-- ============================================================================
-- 1. app.list_prospects -- replaces server/queries/prospect.ts:86 (listProspects).
-- ============================================================================

create function app.list_prospects(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  lead_id uuid,
  legal_name text,
  trade_name text,
  tax_id text,
  billing_address jsonb,
  contact_name text,
  contact_email text,
  contact_phone text,
  status text,
  disqualify_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
  v_page integer;
begin
  -- RULE A (ISS-2026-017/032, HDN-372/373): first executable statement, before any
  -- lookup or authority check -- the claimed actor must genuinely be the calling
  -- session, never merely an actor the caller asserts is allowed.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  -- No pre-flight has_active_tenant_membership raise: this read's own replaced contract
  -- (RLS under `.from()`) never raised on a non-member or a member with zero visible
  -- rows -- both silently yielded an empty page. app.can_access_record's own first
  -- AND-clause is app.has_active_tenant_membership, so applying it as a per-row WHERE
  -- filter (below) rather than a guard clause preserves that exact no-error-on-non-member
  -- behavior, matching app.list_contacts precedent.
  return query
    select
      p.id, p.tenant_id, p.lead_id, p.legal_name, p.trade_name, p.tax_id,
      p.billing_address, p.contact_name, p.contact_email, p.contact_phone,
      p.status, p.disqualify_reason, p.owner_user_id, p.org_unit_id,
      p.merged_into_id, p.merged_at, p.merged_by, p.record_version,
      p.created_by, p.created_at, p.updated_at,
      count(*) over() as total_count
    from app.prospects p
    where p.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, p.tenant_id, p.owner_user_id,
        app.lead_record_scope_org_unit_ids(p.org_unit_id), null
      )
    order by p.updated_at desc, p.id desc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_prospects(uuid, uuid, integer, integer) is
  'COM-144: paginated Prospect queue read, replacing server/queries/prospect.ts:86''s broken .from("prospects") (app is not exposed to PostgREST). Row filter reproduces app.prospects'' own prospects_select_scoped RLS predicate exactly (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) -- unaltered since 20260723120000, confirmed via grep for a later ALTER POLICY, none found), never a second, different authority rule. total_count is an exact count(*) over() of every row matching the WHERE clause before LIMIT/OFFSET is applied -- the same per-request cost and semantics as the .from() call''s own count:"exact" option, so callers can still page to an arbitrary page number. Deliberate column exclusion, matching app.list_contacts/app.list_leads: normalized_legal_name, normalized_tax_id, duplicate_fingerprint, disqualified_at, and archived_at are never returned -- none is part of ProspectSchema/parseProspect (server/contracts/prospect/prospect.ts), the first three are internal identity-correlation columns, and Prospect never exposes them today. A non-member or zero-visible-row actor gets an empty page (rows=[], effective total 0), never a thrown error, matching the RLS-filtered .from() call''s own current behavior exactly.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_prospects with an identical grant set, never a reimplementation.
create function public.list_prospects(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  lead_id uuid,
  legal_name text,
  trade_name text,
  tax_id text,
  billing_address jsonb,
  contact_name text,
  contact_email text,
  contact_phone text,
  status text,
  disqualify_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_prospects(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_prospects(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_prospects with an identical grant set, never a reimplementation.';

revoke execute on function app.list_prospects(uuid, uuid, integer, integer) from public;
grant execute on function app.list_prospects(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_prospects(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_prospects(uuid, uuid, integer, integer) to authenticated, service_role;

-- TS INTEGRATION: server/queries/prospect.ts `listProspects`
-- 1. Change the client param type from `Pick<SupabaseClient, "from">` to
--    `Pick<SupabaseClient, "rpc">` (mirrors this file's own `ProspectQueryRpcClient`
--    alias, already defined and already used by findDuplicateProspects/
--    getProspectConversionReadiness/findExistingAccountsForProspect above -- reuse it
--    rather than adding a second client type).
-- 2. Add `actorAuthUserId: string` to `ListProspectsInput`. Its one call site,
--    app/(tenant)/[tenantSlug]/commercial/prospects/page.tsx:39, already resolves
--    `access.authUserId` via resolveCommercialAccessForRequest a few lines above the
--    call -- change `listProspects(supabase, { tenantId: access.tenant.id, page })` to
--    `listProspects(supabase, { tenantId: access.tenant.id, page, actorAuthUserId: access.authUserId })`.
-- 3. Replace the `.from("prospects").select("*", { count: "exact" })
--    .eq("tenant_id", input.tenantId).order("updated_at", { ascending: false })
--    .range(from, to)` chain with:
--      const { data, error } = await client.rpc("list_prospects", {
--        p_tenant_id: input.tenantId,
--        p_actor_auth_user_id: input.actorAuthUserId,
--        p_page: page,
--        p_page_size: pageSize,
--      });
--    (keep the existing `page`/`pageSize` clamping logic exactly as-is -- it still
--    bounds what gets sent as p_page/p_page_size).
-- 4. `count: "exact"`'s separate `count` return value goes away; total_count now rides
--    on each returned row:
--      const rows = (data ?? []) as Record<string, unknown>[];
--      const totalCount = rows.length > 0 ? Number(rows[0].total_count) : 0;
--      return { prospects: rows.map(parseProspect), totalCount, page, pageSize };
--    (parseProspect already ignores the extra total_count field, and every other
--    row.<snake_case> field it reads is present unchanged -- no contract change needed
--    on server/contracts/prospect/prospect.ts).
-- 5. Error handling is unchanged: `if (error) throw new ProspectQueryError(error.message);`.

-- ============================================================================
-- 2. app.get_prospect_by_id -- replaces server/queries/prospect.ts:106 (getProspectById).
-- ============================================================================

create function app.get_prospect_by_id(
  p_prospect_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  lead_id uuid,
  legal_name text,
  trade_name text,
  tax_id text,
  billing_address jsonb,
  contact_name text,
  contact_email text,
  contact_phone text,
  status text,
  disqualify_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_prospect from app.prospects p where p.id = p_prospect_id;

  -- Anti-enumeration, matching this read's own current contract (server/queries/
  -- prospect.ts:104's own docstring: "returns null (never an error) when RLS/no-match
  -- yields zero rows") and app.get_contact_by_id's own identical idiom: a nonexistent id
  -- and an id the actor cannot access both collapse to zero rows, never a thrown
  -- exception, so a caller cannot distinguish "wrong id" from "exists, not yours" --
  -- exactly RLS's own behavior today.
  if not found
     or not app.can_access_record(
       p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id,
       app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null
     )
  then
    return;
  end if;

  -- Deliberate column exclusion (see header): normalized_legal_name, normalized_tax_id,
  -- duplicate_fingerprint, disqualified_at, and archived_at are never returned -- none is
  -- part of ProspectSchema/parseProspect, matching app.get_contact_by_id.
  id := v_prospect.id; tenant_id := v_prospect.tenant_id; lead_id := v_prospect.lead_id;
  legal_name := v_prospect.legal_name; trade_name := v_prospect.trade_name;
  tax_id := v_prospect.tax_id;
  billing_address := v_prospect.billing_address; contact_name := v_prospect.contact_name;
  contact_email := v_prospect.contact_email; contact_phone := v_prospect.contact_phone;
  status := v_prospect.status; disqualify_reason := v_prospect.disqualify_reason;
  owner_user_id := v_prospect.owner_user_id; org_unit_id := v_prospect.org_unit_id;
  merged_into_id := v_prospect.merged_into_id; merged_at := v_prospect.merged_at;
  merged_by := v_prospect.merged_by; record_version := v_prospect.record_version;
  created_by := v_prospect.created_by; created_at := v_prospect.created_at;
  updated_at := v_prospect.updated_at;
  return next;
end;
$$;

comment on function app.get_prospect_by_id(uuid, uuid) is
  'COM-144: single-prospect read for the Prospect Detail view, replacing server/queries/prospect.ts:106''s broken .from("prospects") (app is not exposed to PostgREST). Authority predicate reproduces app.prospects'' own prospects_select_scoped RLS predicate exactly (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) -- unaltered since 20260723120000, confirmed via grep for a later ALTER POLICY, none found). Returns zero rows (never an exception) for a nonexistent id or one the actor cannot access, matching both the current .from()+RLS behavior and app.get_contact_by_id''s own anti-enumeration posture -- a caller cannot distinguish "does not exist" from "exists, not yours". Deliberate column exclusion, matching app.get_contact_by_id/app.get_lead_by_id: normalized_legal_name, normalized_tax_id, duplicate_fingerprint, disqualified_at, and archived_at are never returned -- none is part of ProspectSchema/parseProspect (server/contracts/prospect/prospect.ts), and the first three are internal identity-correlation columns.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_prospect_by_id with an identical grant set, never a reimplementation.
create function public.get_prospect_by_id(
  p_prospect_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  lead_id uuid,
  legal_name text,
  trade_name text,
  tax_id text,
  billing_address jsonb,
  contact_name text,
  contact_email text,
  contact_phone text,
  status text,
  disqualify_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  merged_into_id uuid,
  merged_at timestamptz,
  merged_by text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_prospect_by_id(p_prospect_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_prospect_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_prospect_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_prospect_by_id(uuid, uuid) from public;
grant execute on function app.get_prospect_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_prospect_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_prospect_by_id(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION: server/queries/prospect.ts `getProspectById`
-- 1. Signature changes from `(client: Pick<SupabaseClient, "from">, prospectId: string)`
--    to `(client: ProspectQueryRpcClient, prospectId: string, actorAuthUserId: string)`
--    (reuse the same `ProspectQueryRpcClient` alias as listProspects, above).
-- 2. Its one call site (app/(tenant)/[tenantSlug]/commercial/prospects/[prospectId]/
--    page.tsx:30) already has `access.authUserId` in scope (resolved at line 20, before
--    this call) -- change to `getProspectById(supabase, prospectId, access.authUserId)`.
-- 3. Replace `.from("prospects").select("*").eq("id", prospectId).maybeSingle()` with:
--      const { data, error } = await client.rpc("get_prospect_by_id", {
--        p_prospect_id: prospectId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) throw new ProspectQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseProspect(row as Record<string, unknown>);
--    (a set-returning RPC always comes back as an array, never single-row-shaped the way
--    `.maybeSingle()` was -- `Array.isArray(data) ? data[0] : data` yields `undefined` on
--    an empty array, so `!row` still correctly maps to the "not found or denied -> null"
--    return, matching app.get_account_by_id/app.get_contact_by_id's own established idiom).
-- 4. The page's own existing post-fetch tenant check
--    (`if (!prospect || prospect.tenantId !== access.tenant.id) notFound();`) is
--    unchanged and remains correct -- defense-in-depth on top of the RPC's own
--    tenant-scoped authority predicate, not a replacement for it.
-- 5. server/queries/prospect.test.ts: update the fake client fixtures for these two
--    functions from `.from()`-shaped stubs to `.rpc()`-shaped stubs, mirroring how this
--    same file's existing findDuplicateProspects/getProspectConversionReadiness tests
--    already stub `.rpc(...)`.

-- ============================================================================
-- RULE A / RULE B / COLUMN-EXCLUSION SELF-CHECK (re-read immediately before shipping)
-- ============================================================================
-- COLUMN EXCLUSION (added on review): server/contracts/prospect/prospect.ts's
-- ProspectSchema/parseProspect were read directly, not inferred from "no exclusion was
-- called out." ProspectSchema has no normalizedLegalName/normalizedTaxId/
-- duplicateFingerprint/disqualifiedAt/archivedAt field, so app.list_prospects,
-- app.get_prospect_by_id, and both public.* wrappers all exclude
-- normalized_legal_name/normalized_tax_id/duplicate_fingerprint/disqualified_at/
-- archived_at from both their RETURNS TABLE clause and their SELECT/assignment list --
-- matching the app.contacts (batch 1) / app.leads (sibling batch) precedent's actual
-- rule of returning exactly what the TS contract consumes, not everything the replaced
-- `select *` call happened to return.
-- RULE A: both app.* functions above (app.list_prospects, app.get_prospect_by_id) take
-- an explicit p_actor_auth_user_id and are granted to `authenticated` -- in both,
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- statement inside `begin ... end`, before any lookup, any app.can_access_record /
-- app.lead_record_scope_org_unit_ids call, and any `return query` / `return next`.
-- Neither relies on a service_role-only exception, so neither could skip it.
--
-- RULE B: grepped "alter policy" (repo-wide) and the bare policy name
-- "prospects_select_scoped" (repo-wide) across every file in supabase/migrations/*.sql --
-- exactly ONE hit total for the policy name (the original CREATE POLICY at
-- 20260723120000), ZERO ALTER POLICY hits naming app.prospects or this policy anywhere,
-- and confirmed 20260730560000_harden_customer_user_layer_default_deny.sql (the
-- customer_user-layer hardening migration that touched dozens of OTHER tables) does not
-- mention "prospect" at all. The predicate reproduced in both functions above --
-- app.can_access_record(actor, tenant_id, owner_user_id,
-- app.lead_record_scope_org_unit_ids(org_unit_id), null) -- is therefore still the
-- CURRENT, unaltered authority envelope, reproduced verbatim (row-bound to each
-- candidate row's own tenant_id/owner_user_id/org_unit_id, since the original `.from()`
-- call sites filtered by `.eq("tenant_id", ...)` / `.eq("id", ...)` respectively, exactly
-- as app.prospects' own RLS policy itself does not take a caller-supplied tenant as a
-- separate trust boundary either).
-- ============================================================================

-- ===========================================================================
-- TABLE 3 of 6: app.quotations_directory
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- app.quotations_directory
-- (COM-151/152/153/154, CG-S7-COM-010).
--
-- Replaces four broken `.from("quotations_directory")` reads in
-- server/queries/quotation.ts (supabase/config.toml exposes only public/graphql_public to
-- PostgREST; `app` -- and therefore every view inside it -- is completely invisible to it,
-- so all four calls have never worked in production):
--   * server/queries/quotation.ts:32  getQuotationById              (Quotation Detail page,
--     the quote-compare "otherQuotation" lookup, and the Approvals Inbox row lookup)
--   * server/queries/quotation.ts:45  listQuotationVersions          (Quotation Detail
--     page's version-history panel)
--   * server/queries/quotation.ts:58  listQuotationsForOpportunity   (Opportunity Detail
--     page's quotations sub-list)
--   * server/queries/quotation.ts:72  listQuotationsForTenant        (tenant-wide
--     Quotations list page, bounded to 200 rows)
--
-- Four functions are authored below -- app.get_quotation_by_id, app.list_quotation_versions,
-- app.list_quotations_for_opportunity, app.list_quotations_for_tenant -- one per call site,
-- per the task's own instruction (get-by-id vs. three differently-filtered lists are
-- genuinely different shapes, matching how app.list_opportunities/app.get_opportunity_by_id
-- were split in the immediately preceding batch, 20260909000000). This migration does NOT
-- touch app.quotation_lines_directory (server/queries/quotation.ts:84 listQuotationLines) --
-- a separate view, out of this task's declared scope -- nor any quotation MUTATION function
-- (create_quotation_draft/submit_quotation/clone_quotation/recalculate_quotation_totals/
-- update_quotation_terms), nor app.get_quotation_submission_readiness (a different readiness
-- computation, already RPC-reachable), nor app.get_quotation_for_customer_decision (the
-- SEPARATE unauthenticated, bearer-token, customer-facing read -- a structurally different
-- authority model that must never be reused here; confirmed its own grant is
-- `to service_role` only, never `authenticated`, so it could not even be cited as an
-- authenticated-actor precedent).
--
-- ===========================================================================
-- WHAT IS BEING READ, AND WHY IT IS A VIEW, NOT A BASE TABLE
-- ===========================================================================
--
-- `app.quotations_directory` is a VIEW. Grepped `create (or replace )?view app\.quotations_
-- directory` across every file in supabase/migrations/*.sql, sorted by filename: FOUR hits,
-- not one -- this view has been widened three times since its original creation, each time
-- appending new columns at the end (the only shape CREATE OR REPLACE VIEW structurally
-- allows), never removing or renaming an existing one:
--   1. CREATE VIEW  -- 20260724210000_create_commercial_quotation_builder.sql:807  (COM-151,
--      original 29-column shape)
--   2. CREATE OR REPLACE -- 20260724240000_create_commercial_quotation_versioning.sql:788
--      (COM-152, appends root_quotation_id/version_number/is_current/superseded_by_id/
--      revision_reason -- 34 columns)
--   3. CREATE OR REPLACE -- 20260724270000_create_commercial_quotation_approval.sql:467
--      (COM-153, appends approval_status/approval_request_id/approval_rule_version_id/
--      approval_required_reasons -- 38 columns)
--   4. CREATE OR REPLACE -- 20260724280000_create_commercial_quotation_customer_acceptance.sql:472
--      (COM-154, appends customer_decision/customer_decision_at -- 40 columns, CURRENT;
--      independently recounted column-by-column against the file during review -- the
--      original draft of this migration undercounted this as "39 columns" throughout, an
--      arithmetic slip in the prose only, never in the actual reproduced column lists below,
--      which were independently verified column-for-column against this SELECT and are
--      correct)
-- No later `create or replace view app.quotations_directory` exists anywhere after
-- 20260724280000 (every subsequent file that mentions the view name -- 20260724290000,
-- 20260724320000, 20260724340000, 20260727090000 -- only REFERENCES it in a comment while
-- describing a different table's own masking precedent; none contains a `create` or `alter`
-- statement naming it). #4's SELECT is therefore the CURRENT, full defining SELECT (read in
-- full, not skimmed, per the task's own instruction):
--
--   select
--     q.id, q.tenant_id, q.quote_number, q.opportunity_id, q.source_opportunity_version,
--     q.prospect_id, q.contact_id, q.customer_snapshot, q.currency, q.validity_from,
--     q.validity_to, q.terms,
--     case when app.has_view_selling_price(q.tenant_id) then q.subtotal_amount else null end as subtotal_amount,
--     case when app.has_view_selling_price(q.tenant_id) then q.discount_amount else null end as discount_amount,
--     case when app.has_view_selling_price(q.tenant_id) then q.tax_amount else null end as tax_amount,
--     case when app.has_view_selling_price(q.tenant_id) then q.total_amount else null end as total_amount,
--     not app.has_view_selling_price(q.tenant_id) as sell_masked,
--     q.status, q.cancel_reason, q.cloned_from_id, q.document_ref, q.submitted_at,
--     q.submitted_by, q.owner_user_id, q.org_unit_id, q.record_version, q.created_by,
--     q.created_at, q.updated_at,
--     q.root_quotation_id, q.version_number, q.is_current, q.superseded_by_id, q.revision_reason,
--     q.approval_status, q.approval_request_id, q.approval_rule_version_id, q.approval_required_reasons,
--     q.customer_decision, q.customer_decision_at
--   from app.quotations q
--   where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id,
--         app.lead_record_scope_org_unit_ids(q.org_unit_id), null);
--
-- Two things this view does that all four new functions below must replicate EXACTLY, not
-- simplify or guess at (per the task's own instruction):
--   1. Field masking: `subtotal_amount`/`discount_amount`/`tax_amount`/`total_amount` are
--      nulled out, and `sell_masked` is set true, for any actor lacking the real, seeded
--      `COM:View selling price` permission, via `app.has_view_selling_price(tenant_id)` --
--      the exact same gate (COM-147) `app.opportunities_directory` already masks
--      `value_amount`/`value_currency`/`probability` with, whose body is `select
--      (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM', 'View selling
--      price')).allowed`. Grepped `create (or replace )?function app\.has_view_selling_price`
--      across every migration file: exactly ONE hit (20260723210000, COM-147's own creation
--      migration) -- never replaced, no RULE C staleness risk. Every column appended by
--      COM-152/153/154 (version/approval/customer-decision axes) is deliberately NEVER
--      sell-masked -- each is a status/reference/reason-code column, never a dollar figure,
--      per their own migrations' header comments quoted above ("Reason/status-like, never a
--      dollar figure, visible to any record-scoped viewer regardless of COM:View
--      cost/selling price") -- so only the four original COM-151 monetary columns carry a
--      `case when ... else null end`, exactly matching the view's own never-widened masking
--      set.
--   2. Row filter: `app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id,
--      app.lead_record_scope_org_unit_ids(q.org_unit_id), null)` -- necessary because this
--      view masks column-REVOKEd values (authenticated has no direct column grant on
--      subtotal_amount/discount_amount/tax_amount/total_amount on the base table itself --
--      `grant select (id, tenant_id, ..., updated_at) on app.quotations to authenticated;`,
--      20260724210000:906-910, deliberately omits the four monetary columns), which requires
--      the view to run in view-owner (non-invoker) mode -- the same reasoning
--      app.opportunities_directory's own header already established at length for the
--      identical column-REVOKE-plus-view-masking technique. View-owner mode means the base
--      table's RLS policy does not apply to a read of the view, so the view restates the row
--      filter itself instead of relying on RLS transparently.
--
-- All four new functions below pass the caller's verified `p_actor_auth_user_id` EXPLICITLY
-- into `app.has_view_selling_price(tenant_id, p_actor_auth_user_id)` and
-- `app.can_access_record(p_actor_auth_user_id, ...)`, and read directly off the BASE TABLE
-- `app.quotations` rather than `select ... from app.quotations_directory` itself (which would
-- rely on the view's own bare `auth.uid()`, silently wrong inside a nested SECURITY DEFINER
-- call with no live session GUC). This is the same, already-established fix
-- app.list_opportunities/app.get_opportunity_by_id (20260909000000, the immediately
-- preceding batch) applied for the byte-for-byte identical problem against
-- app.opportunities_directory, itself tracing to COM-149's app.search_vendor_rates.
--
-- ===========================================================================
-- RULE B -- authority envelope (current RLS predicate / view WHERE clause, not stale)
-- ===========================================================================
-- The BASE TABLE's own RLS SELECT policy is `quotations_select_scoped`, created at
-- 20260724210000_create_commercial_quotation_builder.sql:890-892:
--   create policy quotations_select_scoped on app.quotations
--     for select to authenticated
--     using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--            app.lead_record_scope_org_unit_ids(org_unit_id), null));
-- Grepped BOTH `alter policy.*quotations\b` and the bare policy name
-- `quotations_select_scoped` across every file in supabase/migrations/*.sql (sorted by
-- filename, excluding quotation_lines/quotation_number_counters/quotation_acceptance_*/
-- quotation_customer_decisions/quotation_approval_rules -- different tables/policies with
-- their own names): the ONLY hit anywhere is the CREATE POLICY above. No ALTER POLICY on
-- `quotations_select_scoped` exists anywhere.
--
-- Specifically checked against 20260730560000_harden_customer_user_layer_default_deny.sql
-- (the migration that added `AND NOT app.actor_holds_customer_user_layer(tenant_id)` to 98
-- other policies): `quotations_select_scoped` is NOT among the 98 policies that migration's
-- own `alter policy` list rewrites (grepped `alter policy.*quotations` there: only
-- `quotation_approval_rules_select_scoped` appears -- a different table). This is not an
-- oversight to flag -- it is that migration's own DECLARED exclusion criterion, quoted
-- verbatim from its header: "Policies with a legitimate customer path are deliberately
-- excluded. Any policy already carrying an owner-scope branch, a warehouse-eligibility
-- gate, `app.can_access_record`, or an org-unit/branch predicate is untouched -- those are
-- either the designed customer-visible paths ... or already fail closed on their own. Only
-- policies where tenant membership is the ENTIRE test are narrowed." `quotations_select_
-- scoped` uses `app.can_access_record`, which is exactly the excluded shape -- it was
-- deliberately left alone because `can_access_record` already folds the correct
-- customer_user-layer-aware, owner/org-unit/customer-account-ref logic in on its own (see
-- RULE C below: `can_access_record`'s current body already has its own
-- `has_active_tenant_membership` branch plus an explicit, narrower
-- `pm.layer = 'customer_user'` + `pm.customer_account_ref = p_customer_account_ref` branch
-- for the one legitimate customer path, never a bare "any active member" test). The
-- predicate above, exactly as originally written (and exactly as the view's own WHERE clause
-- already restates it), is therefore still the CURRENT, unaltered authority envelope -- what
-- all four new functions below reproduce, neither wider nor narrower. (This is the identical
-- conclusion, reached via the identical grep discipline, that app.list_opportunities/
-- app.get_opportunity_by_id's own header reached for `opportunities_select_scoped` --
-- another `can_access_record`-gated policy the same hardening migration also left alone,
-- there because the table was simply absent from its audited list rather than deliberately
-- excluded by name; the *outcome* -- current predicate is the original, unaltered one -- is
-- the same either way.)
--
-- Column shape: grepped `alter table app\.quotations\b` across every migration file. Every
-- hit is one of the four column-adding migrations already accounted for above (COM-152's
-- root_quotation_id/version_number/is_current/superseded_by_id/revision_reason, COM-153's
-- approval_status/approval_request_id/approval_rule_version_id/approval_required_reasons,
-- COM-154's customer_decision/customer_decision_at) plus COM-152's own NOT NULL/constraint
-- tightening on root_quotation_id -- no column was ever added to the base table that the
-- view's own SELECT list has NOT already picked up (unlike app.opportunities' account_id,
-- which was added AFTER its directory view's last CREATE OR REPLACE and so was never
-- exposed by it). All 40 of the view's current columns are reproduced below; no column gap
-- exists to disclose here.
--
-- ===========================================================================
-- RULE C -- precedent staleness check
-- ===========================================================================
-- Helper signatures used below, each confirmed to be its own most-recent CREATE OR REPLACE:
--   app.can_access_record(p_auth_user_id uuid, p_tenant_id uuid, p_owner_user_id uuid,
--     p_shared_org_unit_ids uuid[] default '{}', p_customer_account_ref text default null)
--     -- grepped `create (or replace )?function app\.can_access_record`: two hits, the
--     -- ORIGINAL at 20260716110430_create_field_record_access.sql:31 and the CURRENT
--     -- `create or replace` at 20260723180000_create_commercial_sales_pipeline.sql:50
--     -- (COM-146, fixes a NULL-owner-defeats-the-guard defect via `coalesce(..., false)`).
--     -- No later replace exists. The body cited/reproduced below is the current one. Its
--     -- current body: `has_active_tenant_membership(tenant_id) and coalesce(is_supreme_admin
--     -- (...) or (owner match) or (shared org-unit exists(...)) or (customer_account_ref is
--     -- not null and exists(select 1 from app.principal_memberships pm where pm.auth_user_id
--     -- = p_auth_user_id and pm.tenant_id = p_tenant_id and pm.layer = 'customer_user' and
--     -- pm.status = 'active' and pm.customer_account_ref = p_customer_account_ref)), false)`
--     -- -- confirming the RULE B analysis above: this predicate already fails closed for a
--     -- bare customer_user-layer member with no matching customer_account_ref (quotations'
--     -- call passes `null` for p_customer_account_ref, so that whole branch is always false
--     -- for this table -- a customer_user gets in only via owner-match or shared org-unit,
--     -- same as any other principal).
--   app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- called transitively inside app.can_access_record's own body, never inlined directly
--     -- by any function below -- whichever body is current at call time is the one that
--     -- runs. (For completeness: its own most-recent CREATE OR REPLACE is
--     -- 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64.)
--   app.has_view_selling_price(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- grepped `create (or replace )?function app\.has_view_selling_price`: exactly ONE hit
--     -- (20260723210000, COM-147's own creation migration) -- never replaced.
--   app.lead_record_scope_org_unit_ids(p_org_unit_id uuid)
--     -- grepped: exactly ONE hit (20260723090000_create_commercial_lead_management.sql:164)
--     -- -- never replaced.
--   app.assert_actor_is_session_identity(p_actor_auth_user_id uuid)
--     -- grepped: exactly ONE hit
--     -- (20260730440000_harden_actor_identity_session_crosscheck.sql:59) -- never replaced.
--
-- Authority-check shape precedent: `app.get_opportunity_by_id`/`app.list_opportunities`
-- (20260909000000) -- the immediately preceding batch's own directory-view remediation,
-- reading directly off the base table with the identical `can_access_record(p_actor_
-- auth_user_id, row.tenant_id, row.owner_user_id, app.lead_record_scope_org_unit_ids(row.
-- org_unit_id), null)` shape. This table's OWN sibling mutation functions
-- (app.create_quotation_draft, app.submit_quotation, app.add_quotation_line, app.
-- update_quotation_terms) all resolve the quotation row first (`select * into v_quotation
-- from app.quotations where id = ...`) and then gate via `app.can_access_record(p_actor_
-- auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_
-- org_unit_ids(v_quotation.org_unit_id), null)` -- e.g. app.submit_quotation
-- (20260724270000_create_commercial_quotation_approval.sql, current body, no later
-- CREATE OR REPLACE of app.submit_quotation exists anywhere -- grepped `create (or replace
-- )?function app\.submit_quotation`, one hit) -- confirming the SAME predicate shape this
-- table's own mutations already use is what all four read functions below reproduce, not an
-- invented one.
--
-- RULE A precedent: `app.list_opportunities`/`app.get_opportunity_by_id` (20260909000000)
-- and `app.list_accounts`/`app.get_account_by_id` (20260908020000) -- both confirmed current
-- (each is its own file's original, never-since-replaced body; no later
-- `create or replace function app.get_opportunity_by_id` /
-- `create or replace function app.list_opportunities` exists in any migration filed after
-- 20260909000000). `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is
-- their first executable statement, before any lookup or authority check -- the same
-- placement all four functions below use.
--
-- Pagination/bounding shape for app.list_quotations_for_tenant: the ONLY one of the four
-- reads with an existing bound (`server/queries/quotation.ts:69-80` already calls
-- `boundedRange()`/`.range(0, 200)`/`toBoundedList()` -- this is the same `.from()`-based
-- "fetch 201, slice, flag truncated" trick `server/queries/bounded-list.ts` documents, and
-- the same read `bounded-list.ts`'s own header names as one of the four ISS-2026-238
-- unbounded-read defects it was written to fix: "listAccounts, listCustomerContracts,
-- listQuotationsForTenant and listFilesForTenant each fetch every row for the tenant"). An
-- RPC's plain `limit` cannot recreate the "fetch one extra row" trick without changing the
-- return shape, so this reproduces `app.list_accounts`'s own already-established convention
-- instead (20260908020000): a `p_limit integer default 200` parameter, hard-clamped
-- server-side via `limit least(coalesce(p_limit, 200), 200)` regardless of what is
-- requested, with the TS caller switching its truncation-DETECTION technique from
-- `toBoundedList` to the already-exported `toBoundedListByCapReached` (see TS INTEGRATION
-- below for app.list_quotations_for_tenant, and the disclosed "exactly 200 rows" edge-case
-- behavior change this implies -- the identical, already-accepted trade-off
-- app.list_accounts's own TS INTEGRATION note already disclosed).
--
-- app.list_quotation_versions and app.list_quotations_for_opportunity are NOT given a
-- p_limit/bound: their original `.from()` call sites never called `.range()`/`.limit()`
-- either, and `bounded-list.ts`'s own ISS-2026-238 finding names only `listAccounts`,
-- `listCustomerContracts`, `listQuotationsForTenant` and `listFilesForTenant` as unbounded
-- defects -- NOT `listQuotationVersions`/`listQuotationsForOpportunity`. The same reasoning
-- `app.list_customer_contract_versions`'s own header already gives for leaving a
-- version-history read unbounded applies verbatim here: "Unbounded: a contract's own version
-- count is real business cardinality, not an ISS-2026-238 unbounded-base-table defect" --
-- the number of versions one quotation accrues, or the number of quotations one opportunity
-- accrues, is real, naturally small business cardinality (bounded by how many times a human
-- revises one deal), never a tenant-wide, ever-growing collection. Reproducing the original
-- unbounded shape here is therefore correct, not a regression to fix.
--
-- Ordering: `listQuotationVersions`' original `.order("version_number", { ascending: true })`
-- and `listQuotationsForOpportunity`'s original `.order("created_at", { ascending: false })`
-- carried no secondary sort key. `version_number` is already guaranteed unique per
-- `root_quotation_id` by the base table's own `quotations_root_version_unique` constraint
-- (20260724240000:68: `unique (root_quotation_id, version_number)`), so no tie-breaker is
-- needed or added for app.list_quotation_versions -- ties are structurally impossible.
-- `created_at` has no such uniqueness guarantee for app.list_quotations_for_opportunity (two
-- quotations for the same opportunity could share a timestamp), so -- mirroring
-- app.list_opportunities' own disclosed, deliberate `order by created_at desc, id desc`
-- addition for the identical reason (20260909000000) -- `id desc` is added as a tie-breaker
-- there. This is a minor, deliberate improvement over a byte-for-byte match, not a
-- behavior-preserving requirement; flagged as an open question below, exactly as
-- app.list_opportunities' own precedent flagged it.
--
-- Deliberate column exclusion: none. Every column the view currently exposes (all 40) is
-- exposed by all four functions below, unchanged, in the same order.
--
-- All four functions take an explicit `p_actor_auth_user_id` and are granted to
-- `authenticated` (not service_role-only) -- RULE A applies to all four:
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- executable statement in each, before any lookup or authority check.
--
-- None of the four raises on a denied/absent actor -- each simply yields zero rows (or an
-- empty page), mirroring `app.get_opportunity_by_id`/`app.list_opportunities`'s own posture
-- for the identical `can_access_record`-gated (record-scoped, not bare-membership-gated)
-- shape, and matching every one of these four reads' own existing `.maybeSingle()`/plain-
-- array contract today (RLS-filtered reads never distinguished "wrong id"/"no rows for this
-- filter" from "exists, not yours" -- collapsing that distinction is itself a deliberate
-- anti-enumeration property, not a gap to close). This is deliberately NOT
-- `app.list_accounts`'s own `raise insufficient_authority` posture -- that posture belongs to
-- a policy where tenant membership alone is alone the entire test (a caller with zero
-- standing in the named tenant is a genuine misuse, worth raising on); `quotations_select_
-- scoped` is `can_access_record`-gated (record-scoped: owner/org-unit/customer-ref, not bare
-- membership), the same shape `app.list_opportunities` already established should degrade to
-- a silent empty result instead.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own explicit
-- `revoke execute on all functions in schema app from public` before its final grants, the
-- standing per-migration convention. Per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md, closed
-- by 20260830200000_correct_public_wrapper_grant_parity.sql): a bare
-- `revoke execute on function public.FN(...) from public` does NOT strip the
-- `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT PRIVILEGES rule applies
-- to every new function in schema public at CREATE time. Every `public.*` wrapper below
-- therefore explicitly revokes from `anon, authenticated, service_role, public` before
-- re-granting exactly the roles its `app.*` counterpart itself grants (authenticated,
-- service_role -- never anon, which no `app.quotations`-adjacent function has ever granted).
-- ===========================================================================

-- ===========================================================================
-- 1. app.get_quotation_by_id -- replaces server/queries/quotation.ts:32 (getQuotationById)
-- ===========================================================================
-- Reproduces app.quotations_directory's exact defining SELECT against the base table
-- app.quotations directly (never the view itself, to avoid a nested-SECURITY-DEFINER
-- auth.uid() reliance -- see header above), with the identical has_view_selling_price
-- masking (only the four COM-151 monetary columns) and can_access_record row filter (RULE
-- B/C above), keyed on `id` alone -- no p_tenant_id parameter, since the original
-- `.eq("id", quotationId).maybeSingle()` call site never supplied one either and
-- can_access_record's own first argument already resolves tenancy from the row.
create function app.get_quotation_by_id(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Anti-enumeration, matching this read's own current contract
  -- (server/queries/quotation.ts:31's own doc-comment: "returns null for both 'does not
  -- exist' and 'exists but RLS denies it'") and app.get_opportunity_by_id/app.get_account_
  -- by_id's identical posture: a nonexistent id and an id the actor cannot access both
  -- collapse to zero rows below, never a thrown exception.
  return query
    select
      q.id,
      q.tenant_id,
      q.quote_number,
      q.opportunity_id,
      q.source_opportunity_version,
      q.prospect_id,
      q.contact_id,
      q.customer_snapshot,
      q.currency,
      q.validity_from,
      q.validity_to,
      q.terms,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.subtotal_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.discount_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.tax_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.total_amount else null end,
      not app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id),
      q.status,
      q.cancel_reason,
      q.cloned_from_id,
      q.document_ref,
      q.submitted_at,
      q.submitted_by,
      q.owner_user_id,
      q.org_unit_id,
      q.record_version,
      q.created_by,
      q.created_at,
      q.updated_at,
      q.root_quotation_id,
      q.version_number,
      q.is_current,
      q.superseded_by_id,
      q.revision_reason,
      q.approval_status,
      q.approval_request_id,
      q.approval_rule_version_id,
      q.approval_required_reasons,
      q.customer_decision,
      q.customer_decision_at
    from app.quotations q
    where q.id = p_quotation_id
      and app.can_access_record(
        p_actor_auth_user_id, q.tenant_id, q.owner_user_id,
        app.lead_record_scope_org_unit_ids(q.org_unit_id), null
      );
end;
$$;

comment on function app.get_quotation_by_id(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: single-quotation, field-masked read for the Quotation Detail page (and the quote-compare/Approvals-Inbox lookups), replacing server/queries/quotation.ts:32''s broken .from("quotations_directory") (app is not exposed to PostgREST). Reproduces app.quotations_directory''s CURRENT defining SELECT (4th create-or-replace, 20260724280000, 40 columns) against the base table app.quotations directly (same auth.uid()-avoidance reasoning as app.get_opportunity_by_id): subtotal_amount/discount_amount/tax_amount/total_amount are nulled out and sell_masked=true unless the actor holds COM:View selling price (app.has_view_selling_price, unaltered since 20260723210000); every version/approval/customer-decision column added by COM-152/153/154 is never masked, matching the view''s own choice. Row filter is app.can_access_record, reproducing quotations_select_scoped''s current (and only ever) predicate -- deliberately excluded from 20260730560000''s customer_user-layer hardening sweep because can_access_record already fails closed on its own. Returns zero rows (never an exception) for a nonexistent id or one the actor cannot access, matching both the original .maybeSingle() contract and app.get_opportunity_by_id/app.get_account_by_id''s own anti-enumeration posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_quotation_by_id with an identical grant set, never a
-- reimplementation.
create function public.get_quotation_by_id(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_quotation_by_id(p_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_quotation_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_quotation_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_quotation_by_id(uuid, uuid) from public;
grant execute on function app.get_quotation_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_quotation_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_quotation_by_id(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION -- app.get_quotation_by_id
-- server/queries/quotation.ts:
--   * Add `actorAuthUserId: string` as a required third parameter to getQuotationById.
--   * Change its client parameter type from `QuotationQueryTableClient` to the already-
--     exported `QuotationReadinessRpcClient` (Pick<SupabaseClient, "rpc">) -- this function
--     no longer calls `.from()`.
--   * New body:
--       export async function getQuotationById(client: QuotationReadinessRpcClient, quotationId: string, actorAuthUserId: string): Promise<Quotation | null> {
--         const { data, error } = await client.rpc("get_quotation_by_id", {
--           p_quotation_id: quotationId,
--           p_actor_auth_user_id: actorAuthUserId,
--         });
--         if (error) {
--           throw new QuotationQueryError(error.message);
--         }
--         const row = Array.isArray(data) ? data[0] : data;
--         if (!row) {
--           return null;
--         }
--         return parseQuotation(row as Record<string, unknown>);
--       }
--     Return type is unchanged (Promise<Quotation | null>); the "not found or denied -> null"
--     contract is preserved exactly.
-- Call-site mechanical changes (three call sites, all with access.authUserId already in
-- scope):
--   - app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx:68
--       quotation = await getQuotationById(supabase, quotationId);
--       -> quotation = await getQuotationById(supabase, quotationId, access.authUserId);
--   - app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx:116
--       const otherQuotation = await getQuotationById(supabase, compareWith);
--       -> const otherQuotation = await getQuotationById(supabase, compareWith, access.authUserId);
--   - app/(tenant)/[tenantSlug]/commercial/approvals/page.tsx:41
--       items.map((item) => getQuotationById(supabase, item.quotationId))
--       -> items.map((item) => getQuotationById(supabase, item.quotationId, access.authUserId))
-- server/queries/quotation.test.ts: update the fake client fixtures for getQuotationById
-- from a `.from()`-shaped stub to a `.rpc("get_quotation_by_id", ...)`-shaped stub, mirroring
-- how server/queries/account.test.ts already stubs the equivalent app.get_account_by_id RPC.

-- ===========================================================================
-- 2. app.list_quotation_versions -- replaces server/queries/quotation.ts:45
--    (listQuotationVersions)
-- ===========================================================================
-- Reads app.quotations filtered by root_quotation_id, ordered oldest-version-first. No
-- p_tenant_id parameter -- the original `.eq("root_quotation_id", rootQuotationId)` call
-- site never supplied one either, relying purely on RLS-equivalent filtering per row (same
-- reasoning app.list_subsidiary_accounts/app.get_opportunity_by_id already establish for
-- this call shape). Unbounded (RULE C above: real, small business cardinality, not an
-- ISS-2026-238 defect). No secondary sort key: version_number is already unique per
-- root_quotation_id (quotations_root_version_unique), so no tie can occur.
create function app.list_quotation_versions(
  p_root_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select
      q.id,
      q.tenant_id,
      q.quote_number,
      q.opportunity_id,
      q.source_opportunity_version,
      q.prospect_id,
      q.contact_id,
      q.customer_snapshot,
      q.currency,
      q.validity_from,
      q.validity_to,
      q.terms,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.subtotal_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.discount_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.tax_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.total_amount else null end,
      not app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id),
      q.status,
      q.cancel_reason,
      q.cloned_from_id,
      q.document_ref,
      q.submitted_at,
      q.submitted_by,
      q.owner_user_id,
      q.org_unit_id,
      q.record_version,
      q.created_by,
      q.created_at,
      q.updated_at,
      q.root_quotation_id,
      q.version_number,
      q.is_current,
      q.superseded_by_id,
      q.revision_reason,
      q.approval_status,
      q.approval_request_id,
      q.approval_rule_version_id,
      q.approval_required_reasons,
      q.customer_decision,
      q.customer_decision_at
    from app.quotations q
    where q.root_quotation_id = p_root_quotation_id
      and app.can_access_record(
        p_actor_auth_user_id, q.tenant_id, q.owner_user_id,
        app.lead_record_scope_org_unit_ids(q.org_unit_id), null
      )
    order by q.version_number asc;
end;
$$;

comment on function app.list_quotation_versions(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: every version sharing one root_quotation_id, oldest first, for the Quotation Detail page''s version-history panel, replacing server/queries/quotation.ts:45''s broken .from("quotations_directory") (app is not exposed to PostgREST). Reproduces app.quotations_directory''s CURRENT 40-column defining SELECT against the base table directly (same auth.uid()-avoidance reasoning as app.get_quotation_by_id), with the identical has_view_selling_price masking and can_access_record row filter. No p_tenant_id parameter and no raise on a denied/absent actor -- a wrong-tenant or inaccessible root_quotation_id silently yields zero rows, matching the original RLS-filtered array contract. Deliberately unbounded: one quotation''s own version count is real, small business cardinality, not an ISS-2026-238 unbounded-table defect (mirrors app.list_customer_contract_versions'' identical reasoning). No secondary sort key: version_number is already unique per root_quotation_id (quotations_root_version_unique), so ties are structurally impossible.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_quotation_versions with an identical grant set, never a
-- reimplementation.
create function public.list_quotation_versions(
  p_root_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_quotation_versions(p_root_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_quotation_versions(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_quotation_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_quotation_versions(uuid, uuid) from public;
grant execute on function app.list_quotation_versions(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_quotation_versions(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_quotation_versions(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION -- app.list_quotation_versions
-- server/queries/quotation.ts:
--   * Add `actorAuthUserId: string` as a required third parameter to listQuotationVersions.
--   * Change its client parameter type from `QuotationQueryTableClient` to
--     `QuotationReadinessRpcClient` (Pick<SupabaseClient, "rpc">).
--   * New body:
--       export async function listQuotationVersions(client: QuotationReadinessRpcClient, rootQuotationId: string, actorAuthUserId: string): Promise<Quotation[]> {
--         const { data, error } = await client.rpc("list_quotation_versions", {
--           p_root_quotation_id: rootQuotationId,
--           p_actor_auth_user_id: actorAuthUserId,
--         });
--         if (error) {
--           throw new QuotationQueryError(error.message);
--         }
--         return (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
--       }
--     Return type is unchanged (Promise<Quotation[]>).
-- Call-site mechanical change (access.authUserId already in scope):
--   - app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx:87
--       listQuotationVersions(supabase, quotation.rootQuotationId)
--       -> listQuotationVersions(supabase, quotation.rootQuotationId, access.authUserId)
-- server/queries/quotation.test.ts: update the fake client fixture for listQuotationVersions
-- from a `.from()`-shaped stub to a `.rpc("list_quotation_versions", ...)`-shaped stub.

-- ===========================================================================
-- 3. app.list_quotations_for_opportunity -- replaces server/queries/quotation.ts:58
--    (listQuotationsForOpportunity)
-- ===========================================================================
-- Reads app.quotations filtered by opportunity_id, most-recently-created first. No
-- p_tenant_id parameter -- the original `.eq("opportunity_id", opportunityId)` call site
-- never supplied one either (same reasoning as app.list_quotation_versions above).
-- Unbounded (RULE C above: real, small business cardinality -- how many quotes exist for one
-- opportunity -- not an ISS-2026-238 defect). `id desc` added as a deterministic tie-breaker
-- on created_at, mirroring app.list_opportunities' own identical, disclosed addition for the
-- same reason (created_at is not unique) -- see the open question this draft raises below.
create function app.list_quotations_for_opportunity(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select
      q.id,
      q.tenant_id,
      q.quote_number,
      q.opportunity_id,
      q.source_opportunity_version,
      q.prospect_id,
      q.contact_id,
      q.customer_snapshot,
      q.currency,
      q.validity_from,
      q.validity_to,
      q.terms,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.subtotal_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.discount_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.tax_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.total_amount else null end,
      not app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id),
      q.status,
      q.cancel_reason,
      q.cloned_from_id,
      q.document_ref,
      q.submitted_at,
      q.submitted_by,
      q.owner_user_id,
      q.org_unit_id,
      q.record_version,
      q.created_by,
      q.created_at,
      q.updated_at,
      q.root_quotation_id,
      q.version_number,
      q.is_current,
      q.superseded_by_id,
      q.revision_reason,
      q.approval_status,
      q.approval_request_id,
      q.approval_rule_version_id,
      q.approval_required_reasons,
      q.customer_decision,
      q.customer_decision_at
    from app.quotations q
    where q.opportunity_id = p_opportunity_id
      and app.can_access_record(
        p_actor_auth_user_id, q.tenant_id, q.owner_user_id,
        app.lead_record_scope_org_unit_ids(q.org_unit_id), null
      )
    order by q.created_at desc, q.id desc;
end;
$$;

comment on function app.list_quotations_for_opportunity(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: field-masked quotations for one opportunity, most recently created first, for the Opportunity Detail page''s quotations sub-list, replacing server/queries/quotation.ts:58''s broken .from("quotations_directory") (app is not exposed to PostgREST). Reproduces app.quotations_directory''s CURRENT 40-column defining SELECT against the base table directly, with the identical has_view_selling_price masking and can_access_record row filter. No p_tenant_id parameter and no raise on a denied/absent actor -- mirrors app.list_quotation_versions'' identical posture. Deliberately unbounded (real, small per-opportunity cardinality, not an ISS-2026-238 defect). `id desc` is a disclosed, deliberate tie-breaker addition on created_at (not present in the original .order() call, which had no secondary key) -- mirrors app.list_opportunities'' own identical addition for the same "created_at is not unique" reason.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_quotations_for_opportunity with an identical grant set, never a
-- reimplementation.
create function public.list_quotations_for_opportunity(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_quotations_for_opportunity(p_opportunity_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_quotations_for_opportunity(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_quotations_for_opportunity with an identical grant set, never a reimplementation.';

revoke execute on function app.list_quotations_for_opportunity(uuid, uuid) from public;
grant execute on function app.list_quotations_for_opportunity(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_quotations_for_opportunity(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_quotations_for_opportunity(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION -- app.list_quotations_for_opportunity
-- server/queries/quotation.ts:
--   * Add `actorAuthUserId: string` as a required third parameter to
--     listQuotationsForOpportunity.
--   * Change its client parameter type from `QuotationQueryTableClient` to
--     `QuotationReadinessRpcClient` (Pick<SupabaseClient, "rpc">).
--   * New body:
--       export async function listQuotationsForOpportunity(client: QuotationReadinessRpcClient, opportunityId: string, actorAuthUserId: string): Promise<Quotation[]> {
--         const { data, error } = await client.rpc("list_quotations_for_opportunity", {
--           p_opportunity_id: opportunityId,
--           p_actor_auth_user_id: actorAuthUserId,
--         });
--         if (error) {
--           throw new QuotationQueryError(error.message);
--         }
--         return (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
--       }
--     Return type is unchanged (Promise<Quotation[]>).
-- Call-site mechanical change (access.authUserId already in scope):
--   - app/(tenant)/[tenantSlug]/commercial/opportunities/[opportunityId]/page.tsx:53
--       listQuotationsForOpportunity(supabase, opportunity.id)
--       -> listQuotationsForOpportunity(supabase, opportunity.id, access.authUserId)
-- server/queries/quotation.test.ts: update the fake client fixture for
-- listQuotationsForOpportunity from a `.from()`-shaped stub to a
-- `.rpc("list_quotations_for_opportunity", ...)`-shaped stub.

-- ===========================================================================
-- 4. app.list_quotations_for_tenant -- replaces server/queries/quotation.ts:72
--    (listQuotationsForTenant, the tenant-wide Quotations list page)
-- ===========================================================================
-- Reads app.quotations filtered by tenant_id, most-recently-created first, hard-capped
-- server-side -- the one call site among these four that is a genuine ISS-2026-238
-- unbounded-tenant-scan target (see RULE C above). Explicit p_tenant_id parameter (the
-- original `.eq("tenant_id", tenantId)` call site already supplied one) plus
-- p_limit/least(...)-clamp, mirroring app.list_accounts' own already-established
-- convention. No raise on a member-with-zero-visible-rows or a non-member -- mirrors
-- app.list_opportunities' posture (can_access_record-gated, record-scoped, not bare
-- membership), NOT app.list_accounts' raise (bare-membership-gated) -- see header above.
create function app.list_quotations_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select
      q.id,
      q.tenant_id,
      q.quote_number,
      q.opportunity_id,
      q.source_opportunity_version,
      q.prospect_id,
      q.contact_id,
      q.customer_snapshot,
      q.currency,
      q.validity_from,
      q.validity_to,
      q.terms,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.subtotal_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.discount_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.tax_amount else null end,
      case when app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id) then q.total_amount else null end,
      not app.has_view_selling_price(q.tenant_id, p_actor_auth_user_id),
      q.status,
      q.cancel_reason,
      q.cloned_from_id,
      q.document_ref,
      q.submitted_at,
      q.submitted_by,
      q.owner_user_id,
      q.org_unit_id,
      q.record_version,
      q.created_by,
      q.created_at,
      q.updated_at,
      q.root_quotation_id,
      q.version_number,
      q.is_current,
      q.superseded_by_id,
      q.revision_reason,
      q.approval_status,
      q.approval_request_id,
      q.approval_rule_version_id,
      q.approval_required_reasons,
      q.customer_decision,
      q.customer_decision_at
    from app.quotations q
    where q.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, q.tenant_id, q.owner_user_id,
        app.lead_record_scope_org_unit_ids(q.org_unit_id), null
      )
    order by q.created_at desc, q.id desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_quotations_for_tenant(uuid, uuid, integer) is
  'CG-AUDIT-2026-09-02 O1: tenant-wide, field-masked quotation list, most recent first, server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_accounts'' own established cap convention; ISS-2026-238), for the tenant-wide Quotations list page, replacing server/queries/quotation.ts:72''s broken .from("quotations_directory") (app is not exposed to PostgREST). Reproduces app.quotations_directory''s CURRENT 40-column defining SELECT against the base table directly, with the identical has_view_selling_price masking and can_access_record row filter (quotations_select_scoped, unaltered since 20260724210000 -- deliberately excluded from 20260730560000''s hardening sweep because can_access_record already fails closed on its own; see header). No raise on a non-member/zero-visible-row actor -- silently yields an empty page, mirroring app.list_opportunities'' identical posture for the same can_access_record-gated (record-scoped) shape, NOT app.list_accounts'' bare-membership raise. `id desc` tie-breaker added on created_at for the same disclosed, deliberate determinism reason as app.list_opportunities/app.list_quotations_for_opportunity.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_quotations_for_tenant with an identical grant set, never a
-- reimplementation.
create function public.list_quotations_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  id uuid,
  tenant_id uuid,
  quote_number text,
  opportunity_id uuid,
  source_opportunity_version integer,
  prospect_id uuid,
  contact_id uuid,
  customer_snapshot jsonb,
  currency text,
  validity_from timestamptz,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  sell_masked boolean,
  status text,
  cancel_reason text,
  cloned_from_id uuid,
  document_ref text,
  submitted_at timestamptz,
  submitted_by text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  root_quotation_id uuid,
  version_number integer,
  is_current boolean,
  superseded_by_id uuid,
  revision_reason text,
  approval_status text,
  approval_request_id uuid,
  approval_rule_version_id uuid,
  approval_required_reasons text[],
  customer_decision text,
  customer_decision_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_quotations_for_tenant(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_quotations_for_tenant(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_quotations_for_tenant with an identical grant set, never a reimplementation.';

revoke execute on function app.list_quotations_for_tenant(uuid, uuid, integer) from public;
grant execute on function app.list_quotations_for_tenant(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_quotations_for_tenant(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_quotations_for_tenant(uuid, uuid, integer) to authenticated, service_role;

-- TS INTEGRATION -- app.list_quotations_for_tenant
-- server/queries/quotation.ts:
--   * Add `actorAuthUserId: string` as a required third parameter to listQuotationsForTenant.
--   * Change its client parameter type from `QuotationQueryTableClient` to
--     `QuotationReadinessRpcClient` (Pick<SupabaseClient, "rpc">).
--   * Switch the import from `boundedRange, toBoundedList` to `toBoundedListByCapReached`
--     (already exported by ./bounded-list.ts, already used there for exactly this
--     "RPC hard-caps, no extra row available" situation -- today for app.list_files_for_
--     tenant/app.list_accounts for the same reason).
--   * New body:
--       export async function listQuotationsForTenant(client: QuotationReadinessRpcClient, tenantId: string, actorAuthUserId: string): Promise<BoundedList<Quotation>> {
--         const { data, error } = await client.rpc("list_quotations_for_tenant", {
--           p_tenant_id: tenantId,
--           p_actor_auth_user_id: actorAuthUserId,
--           p_limit: BOUNDED_LIST_LIMIT,
--         });
--         if (error) {
--           throw new QuotationQueryError(error.message);
--         }
--         const rows = (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
--         return toBoundedListByCapReached(rows, BOUNDED_LIST_LIMIT);
--       }
--     Keep the external return type as Promise<BoundedList<Quotation>> (the Quotations list
--     page reads `page.rows`/`page.truncated` and must not change) but switch the
--     truncation-DETECTION technique from `boundedRange()`/`toBoundedList()` (fetching one
--     extra row past the cap via `.range()`, a `.from()`-only capability) to
--     `toBoundedListByCapReached`. DISCLOSED BEHAVIOR CHANGE: a tenant with EXACTLY 200
--     quotations will now show "there may be more" even though there is not -- the same
--     accepted, documented trade-off app.list_accounts'' own TS INTEGRATION note already
--     disclosed for the identical technique switch ("over-warning costs a reader one
--     unnecessary sentence" -- see server/queries/bounded-list.ts''s own
--     toBoundedListByCapReached docstring). Flagged in openQuestions below.
-- Call-site mechanical change (access.authUserId already in scope):
--   - app/(tenant)/[tenantSlug]/commercial/quotations/page.tsx:32
--       const page = await listQuotationsForTenant(supabase, access.tenant.id);
--       -> const page = await listQuotationsForTenant(supabase, access.tenant.id, access.authUserId);
-- server/queries/quotation.test.ts: update the fake client fixture for
-- listQuotationsForTenant from a `.from()`-shaped, `.range()`-returning stub to a
-- `.rpc("list_quotations_for_tenant", ...)`-shaped stub.
--
-- Shared, file-wide TS note: none of the four migrated functions above still need
-- `QuotationQueryTableClient` (Pick<SupabaseClient, "from">) -- but `listQuotationLines`
-- (server/queries/quotation.ts:84, out of this task's scope, reading the separate
-- app.quotation_lines_directory view) still does, so `QuotationQueryTableClient` itself must
-- NOT be removed from server/queries/quotation.ts, only left unused by these four functions.

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-execute
-- default, applied before the role-specific grants above are relied upon (the individual
-- `revoke ... from public` lines per function above are kept too, for the same
-- belt-and-suspenders reason every other checkpoint in this repository keeps them; this
-- final sweep is the standing convention's closing statement, not a substitute for the
-- per-function grant hygiene above).
revoke execute on function app.get_quotation_by_id(uuid, uuid) from public;
revoke execute on function app.list_quotation_versions(uuid, uuid) from public;
revoke execute on function app.list_quotations_for_opportunity(uuid, uuid) from public;
revoke execute on function app.list_quotations_for_tenant(uuid, uuid, integer) from public;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping, per the task's own instruction)
-- ===========================================================================
-- RULE A: all four app.* functions above take an explicit p_actor_auth_user_id and are
-- granted to `authenticated` -- in every one, `perform app.assert_actor_is_session_identity
-- (p_actor_auth_user_id);` is the first statement inside `begin ... end`, before any lookup,
-- any has_view_selling_price/can_access_record call, and any `return query`. Re-checked
-- against the literal source text above, function by function:
--   1. app.get_quotation_by_id            -- assert is line 1 of the body. CONFIRMED.
--   2. app.list_quotation_versions        -- assert is line 1 of the body. CONFIRMED.
--   3. app.list_quotations_for_opportunity -- assert is line 1 of the body. CONFIRMED.
--   4. app.list_quotations_for_tenant     -- assert is line 1 of the body. CONFIRMED.
-- None of the four relies on a "service_role-only" exception (none is), so RULE A''s
-- "reachable by authenticated" condition is met by all four, and none is exempt.
--
-- RULE B: grepped `create policy.*quotations\b` (excluding quotation_lines/quotation_
-- number_counters/quotation_acceptance_*/quotation_customer_decisions/quotation_approval_
-- rules -- distinct tables) AND `alter policy.*quotations\b` across every file in
-- supabase/migrations/*.sql, sorted by filename. Exactly ONE hit total for either pattern:
-- the original `create policy quotations_select_scoped on app.quotations`
-- (20260724210000:890). No ALTER POLICY exists. Independently cross-checked against
-- 20260730560000_harden_customer_user_layer_default_deny.sql''s own `alter policy` list (98
-- entries) by name -- `quotations_select_scoped` does not appear in it, consistent with that
-- migration''s own declared exclusion criterion for `can_access_record`-gated policies
-- (quoted verbatim in the header above). The predicate reproduced in all four functions above
-- -- `app.can_access_record(p_actor_auth_user_id, row.tenant_id, row.owner_user_id, app.
-- lead_record_scope_org_unit_ids(row.org_unit_id), null)` -- is therefore the CURRENT,
-- unaltered authority envelope, with `tenant_id`/`owner_user_id`/`org_unit_id` bound to each
-- row''s own columns (never a single caller-supplied tenant substituted in their place, since
-- can_access_record''s own signature takes the tenant as a value, not a table reference).
-- ===========================================================================

-- ===========================================================================
-- OPEN QUESTIONS (disclosed, not blocking)
-- ===========================================================================
-- 1. `order by created_at desc, id desc` in app.list_quotations_for_opportunity and
--    app.list_quotations_for_tenant is a deliberate, disclosed addition over the original
--    `.order("created_at", { ascending: false })` call (no secondary key at all) --
--    mirrors app.list_opportunities'' own identical, already-shipped addition (20260909000000)
--    for the same "created_at is not unique" reason. Does not change which rows appear in the
--    common case (distinct created_at values), only the relative order of ties.
-- 2. app.list_quotations_for_tenant''s truncation-detection technique changes from
--    `toBoundedList` (fetch 201, slice, exact truncation signal) to
--    `toBoundedListByCapReached` (infer from reaching the 200 cap) because a plain SQL
--    `limit` inside an RPC cannot cheaply recreate the "fetch one extra row" trick without
--    widening the returned shape -- the same, already-accepted trade-off
--    app.list_accounts'' own migration (20260908020000) made and disclosed for the identical
--    reason. A tenant with EXACTLY 200 quotations will show "there may be more" when there is
--    not; over-warning, never under-warning.
-- 3. app.quotations_directory itself (never edited by this migration) still does not surface
--    the base table''s newest columns as anything OTHER than what is listed above -- there is
--    no known column on app.quotations that the view has silently dropped (unlike
--    app.opportunities'' account_id gap), so there is no analogous disclosed gap to carry
--    forward here; noted only for completeness/symmetry with the batch-2 precedent''s own
--    open-questions section.
-- ===========================================================================

-- ===========================================================================
-- TABLE 4 of 6: app.quotation_lines_directory
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 0 (CRM/commercial),
-- app.quotation_lines_directory read path.
--
-- Replaces the broken PostgREST read at server/queries/quotation.ts:83-94
-- (listQuotationLines: `.from("quotation_lines_directory").select("*")
-- .eq("quotation_id", quotationId).order("line_no", { ascending: true })`).
-- supabase/config.toml only exposes "public"/"graphql_public" to PostgREST --
-- the "app" Postgres schema, where app.quotation_lines_directory actually lives,
-- is completely invisible to it. This .from() call has never worked in
-- production; it 404s as a nonexistent relation from PostgREST's point of view.
--
-- SOURCE OF TRUTH (RULE C -- precedent staleness, independently re-confirmed)
-- ------------------------------------------------------------------------
-- app.quotation_lines_directory is a VIEW (not a base table), created at
-- supabase/migrations/20260724210000_create_commercial_quotation_builder.sql:
-- 848-878:
--   create view app.quotation_lines_directory as
--   select
--     ql.id, ql.tenant_id, ql.quotation_id, ql.line_no, ql.line_type, ql.description,
--     ql.margin_calculation_id, ql.quantity,
--     case when app.has_view_selling_price(ql.tenant_id) then ql.unit_price else null end as unit_price,
--     case when app.has_view_selling_price(ql.tenant_id) then ql.discount_pct else null end as discount_pct,
--     ql.tax_pct,
--     case when app.has_view_selling_price(ql.tenant_id) then ql.line_gross_amount else null end as line_gross_amount,
--     case when app.has_view_selling_price(ql.tenant_id) then ql.line_discount_amount else null end as line_discount_amount,
--     case when app.has_view_selling_price(ql.tenant_id) then ql.line_tax_amount else null end as line_tax_amount,
--     case when app.has_view_selling_price(ql.tenant_id) then ql.line_total else null end as line_total,
--     case when app.has_view_cost(ql.tenant_id) then ql.cost_amount_snapshot else null end as cost_amount_snapshot,
--     case when app.has_view_cost(ql.tenant_id) then ql.margin_pct_snapshot else null end as margin_pct_snapshot,
--     not app.has_view_selling_price(ql.tenant_id) as sell_masked,
--     not app.has_view_cost(ql.tenant_id) as cost_masked,
--     ql.created_by, ql.created_at, ql.updated_at
--   from app.quotation_lines ql
--   join app.quotations q on q.id = ql.quotation_id
--   where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id,
--     app.lead_record_scope_org_unit_ids(q.org_unit_id), null);
-- Grepped `create or replace view.*quotation_lines_directory` and
-- `quotation_lines_directory` generally across every file in
-- supabase/migrations/*.sql (sorted by filename): the ONLY `create`/
-- `create or replace view` hit is this original 20260724210000 definition --
-- unlike its sibling app.quotations_directory (widened three further times, by
-- COM-152/153/154 in 20260724240000, 20260724270000, 20260724280000),
-- app.quotation_lines_directory itself has never been touched again. This is
-- therefore both the original AND the current definition -- no later rewrite
-- to reconcile.
--
-- RULE B -- authority envelope (current RLS predicate, not merely the original)
-- ------------------------------------------------------------------------
-- Grepped `create policy`/`alter policy` naming `app.quotation_lines` and the
-- bare policy name `quotation_lines_select_scoped` across every file in
-- supabase/migrations/*.sql, sorted by filename: the ONLY hit is the original
-- declaration at 20260724210000:894-902:
--   create policy quotation_lines_select_scoped on app.quotation_lines
--     for select to authenticated
--     using (
--       exists (
--         select 1 from app.quotations q
--         where q.id = quotation_lines.quotation_id
--           and app.can_access_record((select auth.uid()), q.tenant_id, q.owner_user_id,
--             app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
--       )
--     );
-- No later ALTER POLICY exists. 20260730560000_harden_customer_user_layer_
-- default_deny.sql (the migration that later hardened many tenant-membership
-- policies) does not touch this policy at all -- its own header explicitly
-- excludes policies that already route through app.can_access_record as
-- already fail-closed (the same reasoning batch 2's
-- app.list_margin_calculations_for_request header already documented for the
-- identical policy shape on app.margin_calculations). This table's policy is
-- exactly that shape, so it is confirmed current, not stale. The read
-- authority below reproduces this predicate exactly, joined through
-- app.quotations for tenant_id/owner_user_id/org_unit_id, with an explicit
-- p_actor_auth_user_id in place of the policy's own auth.uid().
--
-- Also grepped `alter table app.quotation_lines\b` and `alter table
-- app.quotations\b` (the view's column shape depends on both): app.quotations
-- gained five columns from COM-152 versioning (root_quotation_id,
-- version_number, is_current, superseded_by_id, revision_reason) and further
-- approval/acceptance columns later, but NONE of those are read here (only
-- tenant_id/owner_user_id/org_unit_id, already selected by the join), and
-- app.quotation_lines itself has never had a column added/dropped/renamed
-- since its original 20260724210000:140-169 definition -- the 22-column shape
-- reproduced below is still exhaustive and current.
--
-- Helper functions re-confirmed current (RULE C): grepped `create or replace
-- function app.has_view_selling_price|create function app.has_view_selling_
-- price` -- exactly one hit, 20260723210000_create_commercial_opportunity_
-- management.sql:134 (`app.has_view_selling_price(p_tenant_id uuid,
-- p_auth_user_id uuid default auth.uid())`), never replaced. Same grep for
-- `app.has_view_cost` -- exactly one hit, 20260724090000_create_commercial_
-- costing_request.sql:144, same two-argument shape, never replaced. Same grep
-- for `app.can_access_record` -- two hits (20260716110430 original,
-- 20260723180000_create_commercial_sales_pipeline.sql:50 the COM-146
-- NULL-owner-coalesced-to-false fix); the SECOND (20260723180000) is the
-- current body and the one reproduced here -- identical confirmation this same
-- batch's app.list_margin_calculations_for_request already made. Same grep for
-- `app.assert_actor_is_session_identity` -- current body is
-- 20260730440000_harden_actor_identity_session_crosscheck.sql:59. Same grep
-- for `app.lead_record_scope_org_unit_ids` -- exactly one hit,
-- 20260723090000_create_commercial_lead_management.sql:164, never replaced.
--
-- MASKING REPLICATION -- exact, line-for-line reproduction of the view's own
-- 4 CASE-WHEN pairs (unit_price/discount_pct/line_gross_amount/
-- line_discount_amount/line_tax_amount/line_total gated on
-- app.has_view_selling_price; cost_amount_snapshot/margin_pct_snapshot gated
-- on app.has_view_cost) plus its sell_masked/cost_masked booleans -- not a
-- reimplementation or simplification. The only change from the view's own
-- text is passing p_actor_auth_user_id explicitly as the second argument to
-- app.has_view_selling_price/app.has_view_cost/app.can_access_record instead
-- of relying on their `default auth.uid()` -- the identical
-- compose-on-a-view-keyed-to-auth.uid()-under-a-SECURITY-DEFINER-RPC fix this
-- same batch's app.list_margin_calculations_for_request already applied
-- (20260909000000_close_o1_query_layer_cluster0_batch2_pipeline_margin_
-- opportunity.sql:602-687), tracing back to app.search_vendor_rates and
-- app.list_customer_contract_price_components. `authenticated` has no direct
-- column grant on unit_price/discount_pct/line_gross_amount/
-- line_discount_amount/line_tax_amount/line_total/cost_amount_snapshot/
-- margin_pct_snapshot on the base table itself (only the narrower column-list
-- grant at 20260724210000:917-919, which omits exactly those eight columns),
-- so this function is the only place the masking logic may legally live.
--
-- RULE A: this function takes an explicit p_actor_auth_user_id and is granted
-- to `authenticated` (mirrors the view's own
-- `grant select on app.quotation_lines_directory to authenticated,
-- service_role;`, 20260724210000:921), so
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the
-- first executable statement, before any lookup or authority check --
-- confirmed by self-check below (RULE A self-check: PASS -- it is the sole
-- statement preceding `return query`).
--
-- Precedent modeled on: app.list_margin_calculations_for_request
-- (20260909000000_close_o1_query_layer_cluster0_batch2_pipeline_margin_
-- opportunity.sql:602-687), the most recent already-shipped fix in this exact
-- remediation effort for an identical "masked `_directory` view, unreachable
-- via .from(), needs re-expression against the base table with an explicit
-- actor argument" shape. That function's own header cites
-- app.search_vendor_rates (20260724150000_create_commercial_rate_cost_
-- lookup.sql:479-489) as the origin of the auth.uid()-default fix; the same
-- reasoning applies here verbatim.
--
-- Deliberate column exclusion: none -- all 22 columns of the view's own
-- projection are returned, in the view's own column order (money/discount
-- columns nulled per-row via sell_masked/cost_masked, exactly matching the
-- view's own contract, never omitted from the shape). This is also the exact
-- 22-field shape server/contracts/quotation/quotation.ts's QuotationLineSchema
-- (parseQuotationLine) already expects.
--
-- No p_limit/pagination: the original .from() call itself never paginated (no
-- `.range()`/`.limit()` in server/queries/quotation.ts:84-89), and one
-- quotation has at most a small, bounded number of lines (a single sales
-- document's line items, not an open-ended tenant-wide list). Adding a limit
-- would change behavior relative to the call this replaces, so none is added
-- here.
--
-- Ordering: reproduces the original call's own `.order("line_no", {
-- ascending: true })` server-side (`order by ql.line_no asc`).
--
-- Row-visibility posture: returns zero rows (never an exception) for a
-- nonexistent quotation_id or an actor with no record access to the owning
-- quotation, matching the original RLS-filtered view's own silent-empty-
-- result posture (and app.list_margin_calculations_for_request's identical
-- posture for the sibling app.margin_calculations_directory).

create function app.list_quotation_lines(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  line_no integer,
  line_type text,
  description text,
  margin_calculation_id uuid,
  quantity numeric,
  unit_price numeric,
  discount_pct numeric,
  tax_pct numeric,
  line_gross_amount numeric,
  line_discount_amount numeric,
  line_tax_amount numeric,
  line_total numeric,
  cost_amount_snapshot numeric,
  margin_pct_snapshot numeric,
  sell_masked boolean,
  cost_masked boolean,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select
    ql.id,
    ql.tenant_id,
    ql.quotation_id,
    ql.line_no,
    ql.line_type,
    ql.description,
    ql.margin_calculation_id,
    ql.quantity,
    case when app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) then ql.unit_price else null end as unit_price,
    case when app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) then ql.discount_pct else null end as discount_pct,
    ql.tax_pct,
    case when app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) then ql.line_gross_amount else null end as line_gross_amount,
    case when app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) then ql.line_discount_amount else null end as line_discount_amount,
    case when app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) then ql.line_tax_amount else null end as line_tax_amount,
    case when app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) then ql.line_total else null end as line_total,
    case when app.has_view_cost(ql.tenant_id, p_actor_auth_user_id) then ql.cost_amount_snapshot else null end as cost_amount_snapshot,
    case when app.has_view_cost(ql.tenant_id, p_actor_auth_user_id) then ql.margin_pct_snapshot else null end as margin_pct_snapshot,
    not app.has_view_selling_price(ql.tenant_id, p_actor_auth_user_id) as sell_masked,
    not app.has_view_cost(ql.tenant_id, p_actor_auth_user_id) as cost_masked,
    ql.created_by,
    ql.created_at,
    ql.updated_at
  from app.quotation_lines ql
  join app.quotations q on q.id = ql.quotation_id
  where ql.quotation_id = p_quotation_id
    and app.can_access_record(p_actor_auth_user_id, q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
  order by ql.line_no asc;
end;
$$;

comment on function app.list_quotation_lines(uuid, uuid) is
  'O1 remediation: read path for app.quotation_lines_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup. Row-visibility filter reproduces the CURRENT quotation_lines_select_scoped RLS policy / view WHERE clause (app.can_access_record through the owning app.quotations row) -- confirmed via grep that no later ALTER POLICY exists for this table, and that 20260730560000''s customer_user_layer hardening explicitly excludes policies already routed through app.can_access_record (this policy''s exact shape). The unit_price/discount_pct/line_gross_amount/line_discount_amount/line_tax_amount/line_total (COM:View selling price) and cost_amount_snapshot/margin_pct_snapshot (COM:View cost) CASE-WHEN mask is copied verbatim from the view''s own definition (20260724210000_create_commercial_quotation_builder.sql:848-878, never since replaced), re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid masking -- the same fix app.list_margin_calculations_for_request (this same remediation batch) already established for the identical auth.uid-in-a-view-under-RPC problem, tracing back to app.search_vendor_rates and app.list_customer_contract_price_components. Returns zero rows (never an exception) for a nonexistent quotation_id or an actor with no record access to it, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin
-- security-definer pass-through to app.list_quotation_lines with an
-- identical grant set, never a reimplementation.
create function public.list_quotation_lines(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  line_no integer,
  line_type text,
  description text,
  margin_calculation_id uuid,
  quantity numeric,
  unit_price numeric,
  discount_pct numeric,
  tax_pct numeric,
  line_gross_amount numeric,
  line_discount_amount numeric,
  line_tax_amount numeric,
  line_total numeric,
  cost_amount_snapshot numeric,
  margin_pct_snapshot numeric,
  sell_masked boolean,
  cost_masked boolean,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_quotation_lines(p_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_quotation_lines(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_quotation_lines with an identical grant set, never a reimplementation.';

-- app.list_quotation_lines: same grant set as the view it replaces
-- (`grant select on app.quotation_lines_directory to authenticated,
-- service_role;`, 20260724210000_create_commercial_quotation_builder.sql:921).
revoke execute on function app.list_quotation_lines(uuid, uuid) from public;
grant execute on function app.list_quotation_lines(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309: Supabase's own ALTER
-- DEFAULT PRIVILEGES rule grants EXECUTE on every new public.* function to
-- `anon` and `authenticated` at CREATE FUNCTION time, so `revoke ... from
-- public` alone (the PUBLIC pseudo-role) never removes those two
-- role-specific grants. Revoke all four explicitly, then grant back only the
-- roles app.list_quotation_lines itself grants to, minus anon.
revoke execute on function public.list_quotation_lines(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_quotation_lines(uuid, uuid) to authenticated, service_role;

-- FINAL SELF-CHECK (performed before finishing, per task instructions)
-- ------------------------------------------------------------------------
-- RULE A: app.list_quotation_lines takes an explicit p_actor_auth_user_id,
-- is granted to `authenticated`, and its FIRST executable statement is
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` --
-- before the `return query` lookup, before any authority check. PASS.
-- RULE B: the `where` clause's `app.can_access_record(p_actor_auth_user_id,
-- q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(
-- q.org_unit_id), null)` predicate is character-for-character the same
-- expression (modulo the explicit actor argument replacing auth.uid()) as
-- the CURRENT (and only-ever) quotation_lines_select_scoped policy body and
-- the view's own WHERE clause, both re-grepped immediately above with no
-- later ALTER POLICY / CREATE OR REPLACE VIEW found. PASS.

-- TS INTEGRATION:
-- File: server/queries/quotation.ts, function listQuotationLines (line 84-94).
--
-- 1. Add an `actorAuthUserId: string` parameter to listQuotationLines's own
--    signature (the RPC needs an explicit actor to run its authority/masking
--    checks; the old .from() call relied on the caller's own PostgREST
--    session/JWT implicitly):
--      export async function listQuotationLines(
--        client: QuotationQueryTableClient,
--        quotationId: string,
--        actorAuthUserId: string,
--      ): Promise<QuotationLine[]> {
--
-- 2. Widen `QuotationQueryTableClient` (line 20, currently
--    `Pick<SupabaseClient, "from">`) to `Pick<SupabaseClient, "from" | "rpc">`
--    -- getQuotationById/listQuotationVersions/listQuotationsForOpportunity/
--    listQuotationsForTenant keep using "from" against app.quotations_directory
--    unchanged for now (that view has the identical PostgREST-unreachable
--    problem, but its own read-function remediation is this same cluster's
--    separate, independently-tracked work item -- out of scope here); only
--    listQuotationLines switches to "rpc". This is the identical widening
--    server/queries/margin.ts's own listMarginCalculationsForRequest fix
--    already applied to its shared `MarginQueryTableClient` type.
--
-- 3. Replace the body:
--      const { data, error } = await client
--        .from("quotation_lines_directory")
--        .select("*")
--        .eq("quotation_id", quotationId)
--        .order("line_no", { ascending: true });
--    with:
--      const { data, error } = await client.rpc("list_quotation_lines", {
--        p_quotation_id: quotationId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_* argument names/order exactly as declared above: p_quotation_id
--    first, then p_actor_auth_user_id -- both required from the TS side even
--    though the SQL signature defaults p_actor_auth_user_id to auth.uid().)
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by ql.line_no asc` server-side.
--
-- 4. Row mapping is unchanged: the RPC returns the identical 22-column shape,
--    in the identical order, as the old view select (and exactly the shape
--    server/contracts/quotation/quotation.ts's QuotationLineSchema/
--    parseQuotationLine already expects), so
--    `(data ?? []).map((row: Record<string, unknown>) => parseQuotationLine(row))`
--    needs no change at all. Error handling (`if (error) throw new
--    QuotationQueryError(error.message)`) is also unchanged -- .rpc() surfaces
--    errors the same shape as .from().
--
-- 5. The function's exported return type (`Promise<QuotationLine[]>`) does
--    not change.
--
-- 6. Any caller of listQuotationLines (e.g. wherever a quotation-detail page
--    loader assembles a quotation + its lines) must be updated to pass
--    through the actor's auth_user_id it already has for the sibling
--    getQuotationSubmissionReadiness call on the same page.
--
-- 7. server/queries/quotation.test.ts's "queries the field-masked
--    quotation_lines_directory view, ordered by line_no ascending" test
--    (line 157-165) currently asserts on `capture.calls.table`/
--    `capture.calls.orderColumn`/`capture.calls.ascending` via the shared
--    `fakeTableClient` helper (which only implements `.from()`); it must
--    switch to a fake implementing `.rpc()` and assert on the function name
--    ("list_quotation_lines") and its args object
--    (p_quotation_id/p_actor_auth_user_id) instead -- the same restructuring
--    server/queries/margin.test.ts's equivalent
--    listMarginCalculationsForRequest test already applied in this same
--    remediation effort.

-- ===========================================================================
-- TABLE 5 of 6: app.quotation_approval_rules
-- ===========================================================================
-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 0 (CRM/commercial).
--
-- SCOPE: closes app.quotation_approval_rules (server/queries/quotation-approval.ts:32,
-- listQuotationApprovalRuleVersions). supabase/config.toml exposes only "public"/
-- "graphql_public" to PostgREST -- "app" (where this table lives) is completely invisible
-- to it, so `client.from("quotation_approval_rules").select("*").eq("tenant_id",
-- tenantId).order("created_at", { ascending: false })` has NEVER worked in production; it
-- 404s as a nonexistent relation from PostgREST's point of view. This is a live, currently
-- broken read path, not an architectural backlog item.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 remediation commit in this
-- series, including this same effort's own batch 2): author a new app.* SECURITY DEFINER
-- function performing the equivalent SELECT with correct tenant/RLS/authority scoping, plus
-- a thin public.* pass-through wrapper (the only PostgREST-reachable surface, since app
-- itself is invisible) carrying an IDENTICAL grant set -- never a reimplementation.
--
-- ===========================================================================
-- Table shape (RULE B applies to column shape too, not just policies)
-- ===========================================================================
-- app.quotation_approval_rules is a REAL BASE TABLE (not a view), created at
-- supabase/migrations/20260724270000_create_commercial_quotation_approval.sql:80-98.
-- Grepped "alter table app.quotation_approval_rules" across every file in
-- supabase/migrations/*.sql: zero hits -- no add/drop/rename-column statement exists
-- anywhere. Full, current column list (unchanged since creation):
--   id uuid, tenant_id uuid, min_margin_pct numeric(5,2), max_discount_pct numeric(5,2),
--   min_value_amount numeric(14,2), status text, supersedes_version_id uuid,
--   record_version integer, created_by text, created_at timestamptz, updated_at timestamptz.
-- The one broken call site selects `*` with no column list, so the function below returns
-- `setof app.quotation_approval_rules` (the full row shape) rather than an explicit column
-- list -- no per-column list to keep in sync.
--
-- No column exclusion: per the task's own framing and this table's own migration header
-- (20260724270000 lines 23-32, explicitly modeling this table on COM-150's
-- app.margin_rule_versions), this is tenant-wide policy/reference data -- a margin/discount/
-- value THRESHOLD policy, not a specific deal's financial figure -- and is deliberately never
-- field-masked. Confirmed by the table's own grant: `grant select on
-- app.quotation_approval_rules to authenticated, service_role;` (20260724270000:523) is an
-- unrestricted table-level grant with no column list, exactly mirroring
-- app.margin_rule_versions' own `grant select on app.margin_rule_versions to authenticated,
-- service_role;` (batch 2 precedent, 20260909000000:148). The function below therefore
-- selects every column, exactly as the original .from() call site did.
--
-- -----------------------------------------------------------------------------
-- RULE B -- authority envelope (current RLS predicate, not the original)
-- -----------------------------------------------------------------------------
-- `create policy quotation_approval_rules_select_scoped on app.quotation_approval_rules`
-- was ORIGINALLY declared in 20260724270000_create_commercial_quotation_approval.sql:515-517
-- as:
--     for select to authenticated
--     using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
-- Grepped for every later touch across supabase/migrations/*.sql (both
-- `alter policy.*quotation_approval_rules` and the bare policy name
-- `quotation_approval_rules_select_scoped`, sorted by filename): the ONLY later statement is
-- 20260730560000_harden_customer_user_layer_default_deny.sql:295-296, which rewrites the
-- USING clause (no ROLE/TO change, so "to authenticated" carries forward unchanged) to:
--     using (((app.has_active_tenant_membership(tenant_id)
--              AND NOT app.actor_holds_customer_user_layer(tenant_id))
--             OR app.is_supreme_admin()))
-- No further alter/create-or-replace of this policy exists anywhere in
-- supabase/migrations/*.sql. This later, narrower predicate -- membership AND NOT
-- customer_user-layer, OR supreme admin -- is therefore the envelope the function below
-- reproduces. This is the IDENTICAL predicate shape (same three helper calls) that this
-- same remediation effort's own batch 2 already confirmed and reproduced for
-- app.margin_rule_versions (20260909000000:155-174) -- both tables were rewritten by the
-- same 20260730560000 hardening pass, in the same sweep.
--
-- -----------------------------------------------------------------------------
-- RULE C -- precedent staleness check
-- -----------------------------------------------------------------------------
-- No dedicated "check_quotation_approval_rule_authority" (or similarly named) helper exists
-- for this table -- grepped `create (or replace )?function app\..*authority`
-- repository-wide; the only hits are app.check_quotation_send_authority (a different table,
-- COM-151) and app.check_api_webhook_admin_authority (a different domain entirely). This
-- table's own mutation functions (app.create_quotation_approval_rule_version,
-- app.publish_quotation_approval_rule_version) inline
-- app.has_active_tenant_membership/app.evaluate_permission calls directly rather than
-- routing through a shared helper, so inlining the three-call SELECT-policy predicate
-- directly below -- exactly as app.get_published_margin_rule/app.list_margin_rule_versions
-- already do for app.margin_rule_versions under the identical policy shape -- is the
-- established pattern, not an invented one.
--
-- Checked app.publish_quotation_approval_rule_version's MOST RECENT
-- `create or replace function` (not its 20260724270000 original) as the obvious same-table
-- precedent for assert-placement SHAPE: there is exactly one later rewrite,
-- 20260902200000_harden_tenant_id_disclosure_commercial.sql:1875-1944 (confirmed no third
-- `create or replace function app.publish_quotation_approval_rule_version` exists after it).
-- That CURRENT body still does NOT call app.assert_actor_is_session_identity anywhere --
-- 20260902200000's own concern was a different bug class (tenant_id existence disclosure via
-- a cross-tenant not-found message, fixed there by folding has_active_tenant_membership into
-- the not-found branch), not actor impersonation; it predates ATW-031/032's assert-call sweep
-- and was never brought forward. Per RULE C this is NOT a safe assert-placement precedent to
-- copy. The actually-current precedent for the assert-call SHAPE, for this exact
-- "tenant-wide, never-masked policy table" read shape, is this same remediation effort's own
-- already-shipped, already-gate-verified app.get_published_margin_rule /
-- app.list_margin_rule_versions (batch 2,
-- 20260909000000_close_o1_query_layer_cluster0_batch2_pipeline_margin_opportunity.sql:305-333
-- and 369-399) over app.margin_rule_versions -- the direct sibling table this table's own
-- creation migration (20260724270000:23-32) explicitly modeled itself on. Both functions
-- below follow that shape verbatim (assert-then-authority-then-query), never the stale
-- publish_quotation_approval_rule_version shape.
--
-- Helper signatures used below, each confirmed to be its own most-recent CREATE OR REPLACE
-- (RULE C applied to every helper too):
--   app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- current body: 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64
--     -- (supersedes the 20260716111315 body; no later replace found after 20260907110000)
--   app.actor_holds_customer_user_layer(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- only ever created once: 20260730311000_harden_customer_inventory_access_rls_isolation.sql:71
--   app.is_supreme_admin(p_auth_user_id uuid default auth.uid())
--     -- only ever created once: 20260716105512_create_rls_tenant_policies.sql:45
--   app.assert_actor_is_session_identity(p_actor_auth_user_id uuid)
--     -- only ever created once: 20260730440000_harden_actor_identity_session_crosscheck.sql:59
--
-- -----------------------------------------------------------------------------
-- Design notes
-- -----------------------------------------------------------------------------
-- * The function takes an explicit p_tenant_id (mirroring the original .from() call site,
--   which `.eq("tenant_id", tenantId)`) and RAISEs insufficient_authority on failure -- a
--   caller asking about a specific tenant's approval rules without standing to see that
--   tenant at all is an error, not a silent empty result, matching
--   app.list_margin_rule_versions/app.list_accounts precedent for this exact "list for one
--   named tenant" call shape.
-- * Applies the repository's standard bounded-list cap (`limit least(coalesce(p_limit, 200),
--   200)`), the same convention app.list_margin_rule_versions/app.list_accounts/
--   app.list_rfqs/app.list_finance_invoices/app.list_api_keys_for_tenant already use. The
--   original .from() call site applied no limit at all, but a tenant-wide policy-version
--   history is unbounded in principle (one row per create_quotation_approval_rule_version
--   call, forever) exactly like app.margin_rule_versions -- same disclosed, low-risk
--   tightening as batch 2's own app.list_margin_rule_versions.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration must carry its own
-- explicit `revoke execute on all functions in schema app from public` before its final
-- grants, the standing per-migration convention -- included below.
-- Per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md, closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): a bare `revoke execute on
-- function public.FN(...) from public` does NOT strip the anon/authenticated EXECUTE grants
-- Supabase's own ALTER DEFAULT PRIVILEGES rule applies to every new function in schema
-- public at CREATE time. The public.* wrapper below therefore explicitly revokes from
-- `anon, authenticated, service_role, public` before re-granting exactly the roles its
-- app.* counterpart itself grants (authenticated, service_role -- anon excluded).

-- ===========================================================================
-- app.list_quotation_approval_rule_versions -- replaces
-- server/queries/quotation-approval.ts:32 (listQuotationApprovalRuleVersions)
-- ===========================================================================
-- Reads app.quotation_approval_rules as a tenant-wide, most-recent-first, bounded list of
-- ALL statuses (draft/published/archived). No existing app.* function does this as a
-- standalone read (the equivalent `select * into v_rule from app.quotation_approval_rules
-- where tenant_id = ... and status = 'published'` lives inline inside
-- app.evaluate_quotation_approval_requirement, a different single-published-row read, not
-- this all-versions list). Authority: current quotation_approval_rules_select_scoped
-- predicate (RULE B, see header above). RULE A: assert_actor_is_session_identity is the
-- first executable statement, since this function takes an explicit p_actor_auth_user_id
-- and is granted to `authenticated`.
create function app.list_quotation_approval_rule_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.quotation_approval_rules
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list quotation approval rules for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.quotation_approval_rules
    where tenant_id = p_tenant_id
    order by created_at desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_quotation_approval_rule_versions(uuid, uuid, integer) is
  'COM-153: every quotation approval rule version for one tenant (any status), most-recent first, server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_margin_rule_versions/app.list_accounts/app.list_rfqs/app.list_finance_invoices/app.list_api_keys_for_tenant''s own established cap convention -- the original .from() call site applied no limit, a disclosed, low-risk tightening). Authority reproduces the CURRENT quotation_approval_rules_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql. Raises insufficient_authority (never a silent empty list) when the actor has no standing for p_tenant_id at all, matching app.list_margin_rule_versions/app.list_accounts for this same "list for one named tenant" shape. Tenant-wide policy/reference data -- never field-masked, mirroring app.margin_rule_versions (COM-150) -- so every column is returned unconditionally.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_quotation_approval_rule_versions with an identical grant set,
-- never a reimplementation.
create function public.list_quotation_approval_rule_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.quotation_approval_rules
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_quotation_approval_rule_versions(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_quotation_approval_rule_versions(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_quotation_approval_rule_versions with an identical grant set, never a reimplementation.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on function app.list_quotation_approval_rule_versions(uuid, uuid, integer) from public;
grant execute on function app.list_quotation_approval_rule_versions(uuid, uuid, integer) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309: Supabase's own ALTER DEFAULT
-- PRIVILEGES rule grants EXECUTE on every new public.* function to `anon` and
-- `authenticated` at CREATE FUNCTION time, so `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never removes those two role-specific grants. Revoke all four explicitly,
-- then grant back only the roles app.list_quotation_approval_rule_versions itself grants
-- to, minus anon.
revoke execute on function public.list_quotation_approval_rule_versions(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_quotation_approval_rule_versions(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping)
-- ===========================================================================
-- RULE A: app.list_quotation_approval_rule_versions takes an explicit p_actor_auth_user_id
-- and is granted to `authenticated` -- `perform
-- app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first statement inside
-- `begin ... end`, before any lookup, any has_active_tenant_membership/
-- actor_holds_customer_user_layer/is_supreme_admin call, and any `return query`. The
-- function does not rely on the "service_role-only" exception (it grants to `authenticated,
-- service_role`), so it did not skip the assert on that basis.
-- RULE B: grepped `quotation_approval_rules_select_scoped` (bare policy name) and
-- `alter policy.*quotation_approval_rules` across every file in supabase/migrations/*.sql.
-- Exactly two hits total: the original CREATE POLICY (20260724270000) and the one later
-- ALTER POLICY (20260730560000). No third statement exists. The predicate reproduced above
-- is the 20260730560000 (latest) version, verbatim in logical shape:
-- has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id),
-- OR is_supreme_admin() -- with `tenant_id` bound to the caller-supplied p_tenant_id (the
-- original call site always filtered by an explicit tenantId).

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/quotation-approval.ts.
--
-- 1) QuotationApprovalQueryClient (line 16) is currently
--    `Pick<SupabaseClient, "from" | "rpc">` because listQuotationApprovalRuleVersions used
--    "from" (line 32) while getQuotationApprovalOverview/listQuotationApprovalInboxForActor
--    already used "rpc" (lines 20, 81). Verified by reading the whole file: "from" appears
--    EXACTLY ONCE in it, at line 32, inside listQuotationApprovalRuleVersions itself. Once
--    that call switches to .rpc() below, nothing else in this file uses "from" at all --
--    narrow the type to `Pick<SupabaseClient, "rpc">`.
--
-- 2) listQuotationApprovalRuleVersions(client, tenantId) -- add a required
--    `actorAuthUserId: string` parameter (the RPC needs an explicit actor to run its
--    authority check; the old .from() call relied on the caller's own PostgREST
--    session/JWT implicitly, which never worked anyway since "app" is not exposed to
--    PostgREST). New body:
--
--      const { data, error } = await client.rpc("list_quotation_approval_rule_versions", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: 200,
--      });
--      if (error) {
--        throw new QuotationApprovalQueryError(error.message);
--      }
--      return (data ?? []).map((row: Record<string, unknown>) => parseQuotationApprovalRuleVersion(row));
--
--    Return type is unchanged (`Promise<QuotationApprovalRuleVersion[]>`). NOTE the one
--    behavior change: an actor with NO standing for tenantId at all now throws
--    QuotationApprovalQueryError (insufficient_authority) instead of silently returning an
--    empty array the way a raw RLS-filtered .from() read would have (had it ever reached
--    PostgREST at all) -- this matches app.list_margin_rule_versions/app.list_accounts
--    precedent (see header above) and is the same disclosed shape every other function in
--    this remediation series uses for a "list for one named tenant" call.
--
-- 3) Call-site mechanical changes (no other logic changes needed): every call site of
--    listQuotationApprovalRuleVersions must thread an actorAuthUserId (e.g. the page/API
--    route's own `access.authUserId`, the same value already threaded through
--    getQuotationApprovalOverview/listQuotationApprovalInboxForActor's actorAuthUserId
--    parameters in this same file today).
--
-- 4) server/queries/quotation-approval.test.ts (confirmed to exist, read in full for this
--    table): its "listQuotationApprovalRuleVersions" describe block (lines 55-61) currently
--    calls `listQuotationApprovalRuleVersions(client, TENANT_ID)` (no actor argument) and
--    asserts on `client.calls.table[0] === "quotation_approval_rules"` against the
--    `fakeClient`'s `tableResponses.quotation_approval_rules` fixture. Update it to:
--      - call `listQuotationApprovalRuleVersions(client, TENANT_ID, ACTOR_ID)` (the file
--        already declares an `ACTOR_ID` constant, used elsewhere in the same file);
--      - move `RULE_ROW` from `tableResponses.quotation_approval_rules` to
--        `rpcResponses.list_quotation_approval_rule_versions` (as `{ data: [RULE_ROW], error:
--        null }`);
--      - assert on `client.calls.rpc[0]` (`fn === "list_quotation_approval_rule_versions"`,
--        `args` containing `p_tenant_id`/`p_actor_auth_user_id`/`p_limit`) instead of
--        `client.calls.table[0]`.
--    This mirrors the same restructuring this remediation effort's own margin.test.ts update
--    already applied for the analogous listMarginRuleVersions conversion (batch 2 TS
--    INTEGRATION notes above). The fakeClient's `from()` stub in this file can then be
--    dropped entirely once QuotationApprovalQueryClient narrows to `Pick<SupabaseClient,
--    "rpc">` (step 1 above) -- no other describe block in this test file exercises `.from()`.
--
-- OPEN QUESTIONS (disclosed, not resolved here):
-- * The new p_limit=200 server-side cap is a defensive tightening with no live caller
--   supplying more than 200 rows today (same disclosed, low-risk shape as
--   app.list_margin_rule_versions) -- flagging per that same precedent's own open-question
--   discipline, not because a regression is expected.

-- ===========================================================================
-- TABLE 6 of 6: app.quotation_acceptance_tokens
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 0, table
-- app.quotation_acceptance_tokens.
--
-- Replaces the broken `.from("quotation_acceptance_tokens")` read at
-- server/queries/quotation-acceptance.ts:33 (listQuotationAcceptanceTokens):
--   .select("id, tenant_id, quotation_id, status, channel,
--            recipient_contact_id, recipient_email, expires_at, sent_at,
--            sent_by, revoked_at, revoked_reason, consumed_at, created_by,
--            created_at")
--   .eq("quotation_id", quotationId)
--   .order("sent_at", { ascending: false })
-- Internal, authenticated, RLS-scoped read powering the quotation detail
-- page's acceptance-token history panel
-- (app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx:89,
-- CustomerAcceptancePanel). Not to be confused with the SEPARATE, unauthenticated,
-- token-based `app.get_quotation_for_customer_decision` (same migration,
-- different actor context -- looks up by raw bearer token, not quotation_id,
-- and returns a customer-safe quotation projection, never a token list). This
-- new function reuses NONE of that function's shape or authority: it is an
-- ordinary authenticated, quotation_id-keyed, record-scoped list read.
--
-- Table + column list (RULE 1, confirmed via
-- `grep -n "create table app.quotation_acceptance_tokens"`):
-- supabase/migrations/20260724280000_create_commercial_quotation_customer_
-- acceptance.sql:72-93. Columns: id, tenant_id, quotation_id, token_hash
-- (text, not null, unique -- the one-way sha256 digest of the raw bearer
-- token, per that migration's own table comment at line 95-96, mirroring
-- app.api_keys/PLT-129), status, channel, recipient_contact_id,
-- recipient_email, expires_at, sent_at, sent_by, revoked_at, revoked_reason,
-- consumed_at, created_by, created_at.
--
-- *** token_hash EXCLUSION (security-critical, explicit) ***
-- token_hash does NOT appear anywhere below -- not in either RETURNS TABLE
-- clause, not in either function body's SELECT list. This mirrors: (a) the
-- original broken .from() call's own explicit column list, which already
-- omitted it; (b) that same migration's own column-level grant at line 547
-- (`grant select (id, tenant_id, ..., created_at) on
-- app.quotation_acceptance_tokens to authenticated` -- token_hash is not
-- among the granted columns); and (c) the column-exclusion PRECEDENT set by
-- app.list_contacts in batch 1
-- (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:863-873,
-- excluding normalized_email/normalized_phone/duplicate_fingerprint from
-- app.contacts) -- same discipline, applied here to a bearer-credential digest
-- instead of correlation plumbing, which makes the exclusion even more
-- load-bearing: token_hash leaving the database to any authenticated internal
-- caller would hand that caller everything needed to impersonate the
-- customer-decision bearer flow for a live token.
--
-- RULE B (RLS predicate currency): `grep -rn "create policy.*quotation_
-- acceptance_tokens\|alter policy.*quotation_acceptance_tokens"
-- supabase/migrations/*.sql` and, separately, `grep -rln "quotation_
-- acceptance_tokens_select_scoped" supabase/migrations/*.sql` both return
-- EXACTLY ONE file -- 20260724280000_create_commercial_quotation_customer_
-- acceptance.sql:524-530 -- so that migration's own original policy body is
-- also its current, final one (never later ALTER POLICY'd). Current text:
--   create policy quotation_acceptance_tokens_select_scoped
--     on app.quotation_acceptance_tokens
--     for select to authenticated
--     using (exists (
--       select 1 from app.quotations q
--       where q.id = quotation_acceptance_tokens.quotation_id
--         and app.can_access_record((select auth.uid()), q.tenant_id,
--             q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
--     ));
-- app.list_quotation_acceptance_tokens below reproduces this predicate
-- exactly (join to app.quotations on quotation_id, same
-- app.can_access_record(...) call with the same four positional arguments in
-- the same order, actor substituted for auth.uid() since this is SECURITY
-- DEFINER), never a widened or narrowed rule.
--
-- RULE C (precedent staleness):
--   * `grep -n "create or replace function app.can_access_record\|create
--     function app.can_access_record" supabase/migrations/*.sql` returns
--     exactly one real definition -- 20260723180000_create_commercial_sales_
--     pipeline.sql:50 (create commercial_sales_pipeline) -- never replaced;
--     the other hits in batch1/batch2/batch3 migrations are prose comments
--     referencing that same grep, not additional definitions. Current
--     signature: app.can_access_record(actor_auth_user_id uuid, tenant_id
--     uuid, owner_user_id uuid, org_unit_ids uuid[], extra_condition
--     <whatever that migration declares>) -- matches the RLS policy's own
--     call shape used above.
--   * `grep -n "create (or replace )?function app.assert_actor_is_session_
--     identity" supabase/migrations/*.sql` returns exactly one real
--     definition -- 20260730440000_harden_actor_identity_session_
--     crosscheck.sql:59 (ATW-031/ISS-2026-017) -- never replaced since. This
--     is the RULE A helper invoked below.
--   * app.send_quotation_for_acceptance / app.revoke_quotation_acceptance_
--     token (both in this table's own creation migration,
--     20260724280000:168-256,261-306) are mutations gated by
--     app.check_quotation_send_authority (COM:Edit permission AND
--     app.can_access_record) -- NOT reused here on purpose: that helper
--     additionally requires COM:Edit, which is an authoring/send permission,
--     not a read permission, and would over-narrow this read relative to the
--     actual RLS SELECT policy above (which requires only
--     app.can_access_record, no permission-code check at all). Confirmed via
--     `grep -n "create or replace function app.check_quotation_send_
--     authority\|create function app.check_quotation_send_authority"
--     supabase/migrations/*.sql` that its only definition is this same
--     migration's own original (never later replaced) -- so it is current,
--     just the wrong precedent to reuse for a plain read. This function
--     instead inlines app.can_access_record directly, the same shape batch 1
--     already established for app.list_contacts/app.get_contact_by_id
--     (20260908020000:898-959,1039-...) and batch 1's own COM-155 account-
--     conversion read (20260908020000:613-677, "Authority mirrors app.get_
--     account_conversion_readiness's own current body ... assert_actor_is_
--     session_identity, then app.can_access_record keyed off the SAME
--     quotation's tenant/owner/org-unit").
--   * app.get_quotation_for_customer_decision (this table's own creation
--     migration, 20260724280000:314-369) is confirmed NOT reused: it takes a
--     raw bearer token (not p_actor_auth_user_id, not reachable by
--     `authenticated` at all -- granted only to service_role at line 555), is
--     LANGUAGE plpgsql with no SECURITY DEFINER search_path narrowing beyond
--     `app, public, extensions, pg_temp` for pgcrypto's digest(), and returns
--     a customer-safe quotation projection shape entirely unrelated to a
--     token list. Different actor context, different lookup key, different
--     return shape -- correctly NOT the model for this function.
--
-- RULE A: p_actor_auth_user_id is an explicit parameter and this function is
-- granted to `authenticated` -> `perform app.assert_actor_is_session_
-- identity(p_actor_auth_user_id);` is the first executable statement, before
-- any lookup or authority check (including the app.can_access_record join
-- below).
--
-- No LIMIT/pagination: the original `.from("quotation_acceptance_tokens")
-- .select(...).eq("quotation_id", ...).order("sent_at", {ascending:false})`
-- call site never applied a `.range()`/`.limit()` either, and
-- quotation_acceptance_tokens_quotation_active_unique already bounds this to
-- at most one 'active' row per quotation_id at any time (send/resend revokes
-- the prior active token first, this table's own creation migration's own
-- header) -- the full history per quotation is small and human-driven
-- (one send/resend event at a time), not an unbounded feed. An artificial cap
-- here would be a behavior change the caller never asked for.
--
-- A nonexistent quotation_id, a cross-tenant quotation_id, or an in-tenant
-- quotation_id the actor cannot otherwise reach (per app.can_access_record)
-- all yield an EMPTY result set here, never a thrown error -- exactly the
-- current RLS-filtered `.from()` read's own posture (no matching visible row
-- ever raises; it just returns `data: []`).

create function app.list_quotation_acceptance_tokens(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  status text,
  channel text,
  recipient_contact_id uuid,
  recipient_email text,
  expires_at timestamptz,
  sent_at timestamptz,
  sent_by text,
  revoked_at timestamptz,
  revoked_reason text,
  consumed_at timestamptz,
  created_by text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select
      t.id,
      t.tenant_id,
      t.quotation_id,
      t.status,
      t.channel,
      t.recipient_contact_id,
      t.recipient_email,
      t.expires_at,
      t.sent_at,
      t.sent_by,
      t.revoked_at,
      t.revoked_reason,
      t.consumed_at,
      t.created_by,
      t.created_at
    from app.quotation_acceptance_tokens t
    join app.quotations q on q.id = t.quotation_id
    where t.quotation_id = p_quotation_id
      and app.can_access_record(
        p_actor_auth_user_id, q.tenant_id, q.owner_user_id,
        app.lead_record_scope_org_unit_ids(q.org_unit_id), null
      )
    order by t.sent_at desc;
end;
$$;

comment on function app.list_quotation_acceptance_tokens(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 cluster 0: acceptance-token send/resend/revoke history for one quotation, most recently sent first -- replaces server/queries/quotation-acceptance.ts:33''s broken .from("quotation_acceptance_tokens") (app is not exposed to PostgREST). Row filter reproduces quotation_acceptance_tokens_select_scoped''s own current (and only, never ALTER POLICY''d) predicate exactly: exists a app.quotations row with this quotation_id where app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) holds -- expressed here as an inner join since this is SECURITY DEFINER and the base table''s own RLS never applies to it. token_hash is never selected -- deliberately narrower than a bare `select *`, matching the original .from() call''s own explicit column list and this table''s own column-level grant to authenticated (20260724280000:547), which also excludes it. Deliberately does NOT reuse app.check_quotation_send_authority (send/revoke''s own authority helper): that helper additionally requires COM:Edit, which would over-narrow a plain read relative to the actual SELECT RLS policy above. A nonexistent quotation_id, a cross-tenant one, or an in-tenant one the actor cannot otherwise reach all yield an empty result set, never a thrown error, matching the RLS-filtered .from() read''s own current behavior exactly.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin
-- security-definer pass-through to app.list_quotation_acceptance_tokens with
-- an identical grant set, never a reimplementation.
create function public.list_quotation_acceptance_tokens(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  status text,
  channel text,
  recipient_contact_id uuid,
  recipient_email text,
  expires_at timestamptz,
  sent_at timestamptz,
  sent_by text,
  revoked_at timestamptz,
  revoked_reason text,
  consumed_at timestamptz,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_quotation_acceptance_tokens(p_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_quotation_acceptance_tokens(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_quotation_acceptance_tokens with an identical grant set, never a reimplementation.';

-- Per ERR-2026-004: explicit revoke of the app-schema PUBLIC-execute default
-- before any role-specific grant (standing per-migration convention).
revoke execute on function app.list_quotation_acceptance_tokens(uuid, uuid) from public;
grant execute on function app.list_quotation_acceptance_tokens(uuid, uuid) to authenticated, service_role;

-- Per ISS-2026-309 (closed by 20260830200000_correct_public_wrapper_grant_
-- parity.sql): a bare `revoke ... from public` does NOT strip the
-- anon/authenticated EXECUTE grants Supabase's ALTER DEFAULT PRIVILEGES rule
-- applies to every new function in schema public at CREATE time -- revoke
-- from every role explicitly, then re-grant only the app.* function's own
-- roles (no anon: this is an internal authenticated read, never public).
revoke execute on function public.list_quotation_acceptance_tokens(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_quotation_acceptance_tokens(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/quotation-acceptance.ts listQuotationAcceptanceTokens
-- ===========================================================================
-- 1. Change the client param type from
--    `QuotationAcceptanceQueryTableClient` (`Pick<SupabaseClient, "from">`) to
--    `QuotationAcceptanceQueryRpcClient` (`Pick<SupabaseClient, "rpc">`,
--    already defined in the same file for getQuotationForCustomerDecision --
--    reuse it, don't add a third type).
-- 2. Add an `actorAuthUserId: string` parameter to `listQuotationAcceptanceTokens`.
--    Its one call site (app/(tenant)/[tenantSlug]/commercial/quotations/
--    [quotationId]/page.tsx:89) already resolves `access.authUserId` via
--    resolveCommercialAccessForRequest (used two lines above it for
--    getQuotationApprovalOverview) and simply needs to pass it through:
--      listQuotationAcceptanceTokens(supabase, quotation.id, access.authUserId)
-- 3. Replace the `.from("quotation_acceptance_tokens").select("id, tenant_id,
--    quotation_id, status, channel, recipient_contact_id, recipient_email,
--    expires_at, sent_at, sent_by, revoked_at, revoked_reason, consumed_at,
--    created_by, created_at").eq("quotation_id", quotationId)
--    .order("sent_at", { ascending: false })` chain with:
--      const { data, error } = await client.rpc("list_quotation_acceptance_tokens", {
--        p_quotation_id: quotationId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
-- 4. Error handling and the return mapping are unchanged:
--      if (error) { throw new QuotationAcceptanceQueryError(error.message); }
--      return (data ?? []).map((row: Record<string, unknown>) => parseQuotationAcceptanceToken(row));
--    The RPC's row shape is byte-for-byte the same as the old explicit
--    column-list select (same column names, same order, still no token_hash),
--    so parseQuotationAcceptanceToken/QuotationAcceptanceTokenSchema in
--    server/contracts/quotation/quotation-acceptance.ts need no change.
-- 5. server/queries/quotation-acceptance.test.ts's fakeTableClient-based
--    "listQuotationAcceptanceTokens" tests need to become an rpc-mock (same
--    restructuring batch 1's own list_contacts TS-integration note implies
--    for its analogous test suite) -- assert the RPC is called with
--    `{ p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: <actor> }` and
--    that no row in the mocked response ever carries a `token_hash` key,
--    preserving the existing "never selecting token_hash" assertion's intent.
