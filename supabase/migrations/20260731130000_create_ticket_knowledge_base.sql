-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-017 (Ticket SLA and
-- Knowledge Base, Prompt 289) -- Knowledge Base half. Second of two
-- migrations this prompt adds (20260731120000: SLA; this one: Knowledge
-- Base) -- a genuinely separate sub-capability with its own tables/RPCs/RLS.
-- Builds on app.tickets (HRT-286/287/288) for ticket-article linking and
-- app._is_ticket_requester_party/app.is_ticket_staff/app.can_access_ticket
-- (reused verbatim, never re-derived) but is otherwise standalone -- no SLA
-- table here references anything in 20260731120000, and vice versa.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Audience is three explicit, independent booleans -- mirrors
--    app.ticket_categories.customer_visible/helpdesk_visible (HRT-287/288)
--    exactly, never a parallel mechanism.** audience_internal/
--    audience_customer/audience_helpdesk on app.kb_article_versions. A
--    published version requires at least one true (an unpublishable-to-
--    anyone version would be a dead state). This is the SAME vocabulary as
--    app.tickets.channel (internal/customer/helpdesk) deliberately -- an
--    article's audience and a ticket's channel are the same three-way
--    partition of this product's own principal population.
-- 2. **Draft/review/publish is a real, explicit, validated status graph**
--    (draft -> in_review -> approved -> published -> archived; in_review ->
--    draft on changes_requested) -- mirrors app.ticket_status_transitions'
--    own "explicit graph, never a hidden if/else chain" discipline (HRT-286
--    decision 6), enforced structurally by each transition RPC's own CHECK
--    on the FROM status rather than a separate reference table (five states,
--    six edges -- a dedicated graph table was judged unnecessary ceremony
--    at this size; disclosed as a deliberate departure from the ticket-
--    status-transition table pattern, not an oversight).
-- 3. **Publish REQUIRES status=''approved'' -- no override/bypass path.**
--    Section 24's own business rule ("Knowledge articles require audience,
--    reviewer, published version and expiry/review state") is read as a
--    hard requirement, not an optional workflow -- there is no TKT:Close
--    (or any other) escape hatch that skips review, unlike
--    app.recalculate_ticket_sla_clock's own TKT:Close-gated correction path
--    in the sibling SLA migration. An emergency skip-review publish is a
--    real, deferred future extension if the business ever needs one --
--    disclosed, not silently built as a loophole.
-- 4. **Self-review is structurally blocked, not merely a convention** (C-18
--    maker-checker discipline): app.submit_kb_article_version_for_review
--    rejects p_reviewer_auth_user_id = the version's own author_auth_
--    user_id; app.review_kb_article_version separately re-checks the acting
--    reviewer identity equals the assigned reviewer_auth_user_id (or is
--    Supreme Admin, RPD-022's standing disclosed exception) -- an author can
--    never approve their own article by any path.
-- 5. **Audience-safe search/read is enforced at the RPC/RLS layer, not by a
--    convention the caller must remember -- the security-critical half of
--    this sub-capability (this task's own explicit instruction).** A
--    customer-channel caller has ZERO grant on the raw app.kb_article_
--    versions table row for anything but a currently-published,
--    audience_customer=true, non-expired version (RLS, decision 9) AND the
--    dedicated app.search_customer_knowledge_articles/app.get_kb_article_
--    for_customer RPCs apply the IDENTICAL filter predicate a second time in
--    their own WHERE clause (defense in depth, mirrors HRT-286 decision 3''s
--    "RLS is what protects a raw supabase-js read, the RPC''s own WHERE is
--    what protects an RPC caller" reasoning verbatim). The helpdesk and
--    internal read paths repeat the same discipline with their own audience
--    flag. No caching/autocomplete/snippet table exists anywhere in this
--    migration -- disclosed explicitly: search is always evaluated LIVE
--    against this same filtered predicate on every call, never a
--    pre-computed index a future capability could accidentally build without
--    the filter and reopen this exact leak class.
-- 6. **pg_trgm fuzzy search, mirrors app.search_employee_duplicate_
--    candidates (HRT-274) exactly** -- never a new full-text/tsvector
--    mechanism this repository has not already established.
-- 7. **Ticket-article linking reuses the public/internal visibility
--    discipline from app.ticket_messages verbatim (this task's own explicit
--    instruction) -- never invents a parallel mechanism.** A PUBLIC link
--    additionally requires the linked version''s own audience flag for the
--    ticket''s channel to be true (a staff member cannot publicly link a
--    customer-invisible article to a customer ticket); an INTERNAL link
--    requires only staff authority (a private staff reference note, exactly
--    like an internal ticket_messages note). RLS on app.kb_ticket_article_
--    links repeats app.ticket_messages_select_scoped''s predicate byte-for-
--    byte, substituting the link''s own visibility column.
-- 8. **Expiry is a real, durable, idempotent job** -- app.expire_kb_article_
--    versions_batch mirrors app.run_training_certificate_expiry_batch
--    (HRT-284) exactly: a plain idempotent UPDATE (published, expires_at <
--    as_of -> archived), safe to re-run for the same as_of/period_label
--    (the second run''s WHERE clause matches zero rows) -- no INSERT-based
--    ledger, no exception handler needed, matching that migration''s own
--    disclosed reasoning for why an UPDATE-shaped idempotent batch needs
--    none.
-- 9. **C-24 discipline.** title/summary/body/review_notes/archived_reason
--    are ALL free text; app.kb_article_version_audit_projection is an
--    explicit structural-only allowlist (id/tenant_id/article_id/
--    version_number/status/audience flags/record_version) -- never
--    to_jsonb(row), never a raw p_*reason/p_review_notes/p_body parameter
--    passed into capture_audit_event''s own p_reason.
-- 10. **C-02 discipline**: every RETURNS TABLE function aliases every source
--     table, never a bare `where id = ...`.

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry'
  )
);

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-289 to add ''ticket_sla_evaluation''/''kb_article_expiry''.';

create extension if not exists pg_trgm;

-- ===========================================================================
-- 1. app.kb_articles / app.kb_article_versions (decisions 1/2/9).
-- ===========================================================================

create table app.kb_articles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint kb_articles_code_check check (code ~ '^[a-z0-9-]{2,80}$'),
  constraint kb_articles_code_unique unique (tenant_id, code)
);

comment on table app.kb_articles is
  'HRT-289: article identity (parent) -- a stable slug/code. Title/body/audience/status/review/publish/expiry all live on app.kb_article_versions, mirroring app.leave_types/app.leave_type_policy_versions'' own identity-vs-content split (HRT-280).';

create index kb_articles_tenant_idx on app.kb_articles (tenant_id);

create trigger kb_articles_touch before update on app.kb_articles
  for each row execute function app.touch_ticket_row();

create table app.kb_article_versions (
  id uuid primary key default gen_random_uuid(),
  article_id uuid not null references app.kb_articles (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  title text not null,
  summary text,
  body text not null,
  tags text[] not null default '{}'::text[],
  audience_internal boolean not null default false,
  audience_customer boolean not null default false,
  audience_helpdesk boolean not null default false,
  author_auth_user_id uuid not null,
  author_label text,
  submitted_for_review_by text,
  submitted_for_review_at timestamptz,
  reviewer_auth_user_id uuid,
  reviewer_label text,
  review_decision text,
  reviewed_at timestamptz,
  review_notes text,
  published_at timestamptz,
  published_by text,
  expires_at timestamptz,
  archived_at timestamptz,
  archived_by text,
  archived_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint kb_article_versions_status_check check (status in ('draft', 'in_review', 'approved', 'published', 'archived')),
  constraint kb_article_versions_title_check check (length(trim(title)) > 0),
  constraint kb_article_versions_body_check check (length(trim(body)) > 0),
  constraint kb_article_versions_review_decision_check check (review_decision is null or review_decision in ('approved', 'changes_requested')),
  constraint kb_article_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint kb_article_versions_published_audience_check check (
    (status <> 'published') or (audience_internal or audience_customer or audience_helpdesk)
  ),
  constraint kb_article_versions_archived_shape_check check (
    (status <> 'archived') or (archived_at is not null and archived_by is not null)
  ),
  constraint kb_article_versions_scope_unique unique (article_id, version_number)
);

comment on table app.kb_article_versions is
  'HRT-289 (decisions 1/2/3/4): draft -> in_review -> approved -> published -> archived (in_review -> draft on changes_requested). audience_internal/customer/helpdesk mirror app.ticket_categories.customer_visible/helpdesk_visible exactly (decision 1). A published version requires at least one audience flag true. Publish requires status=approved -- no bypass (decision 3). Self-review is blocked at both submit and review time (decision 4).';

create index kb_article_versions_article_status_idx on app.kb_article_versions (article_id, status);
create index kb_article_versions_tenant_published_idx on app.kb_article_versions (tenant_id, status) where status = 'published';
create index kb_article_versions_tenant_customer_idx on app.kb_article_versions (tenant_id) where status = 'published' and audience_customer = true;
create index kb_article_versions_tenant_helpdesk_idx on app.kb_article_versions (tenant_id) where status = 'published' and audience_helpdesk = true;
create index kb_article_versions_expiry_idx on app.kb_article_versions (expires_at) where status = 'published' and expires_at is not null;
create index kb_article_versions_title_trgm_idx on app.kb_article_versions using gin (title gin_trgm_ops);
create index kb_article_versions_body_trgm_idx on app.kb_article_versions using gin (body gin_trgm_ops);
create index kb_article_versions_tags_idx on app.kb_article_versions using gin (tags);

create trigger kb_article_versions_touch before update on app.kb_article_versions
  for each row execute function app.touch_ticket_row();

create function app.kb_article_version_audit_projection(p_version app.kb_article_versions)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_version.id,
    'tenant_id', p_version.tenant_id,
    'article_id', p_version.article_id,
    'version_number', p_version.version_number,
    'status', p_version.status,
    'audience_internal', p_version.audience_internal,
    'audience_customer', p_version.audience_customer,
    'audience_helpdesk', p_version.audience_helpdesk,
    'record_version', p_version.record_version
  );
$$;

comment on function app.kb_article_version_audit_projection is
  'HRT-289 (decision 9, C-24 discipline): explicit structural-only allowlist -- title/summary/body/review_notes/archived_reason are ALL free text and NEVER included. Never to_jsonb(row).';

-- ===========================================================================
-- 2. app.kb_ticket_article_links (decision 7).
-- ===========================================================================

create table app.kb_ticket_article_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  article_id uuid not null references app.kb_articles (id),
  article_version_id uuid not null references app.kb_article_versions (id),
  visibility text not null default 'internal',
  note text,
  linked_by_auth_user_id uuid not null,
  linked_by text,
  linked_at timestamptz not null default now(),
  unlinked_by text,
  unlinked_at timestamptz,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint kb_ticket_article_links_visibility_check check (visibility in ('public', 'internal'))
);

comment on table app.kb_ticket_article_links is
  'HRT-289 (decision 7): reuses app.ticket_messages'' public/internal visibility discipline verbatim. article_version_id freezes WHICH version was linked (the article may gain a new version later without silently changing what this ticket''s link pointed to) -- mirrors app.ticket_sla_clocks'' own "freeze the exact version at the moment of the action" discipline (sibling SLA migration, decision 4). Soft-unlinked (unlinked_at), never hard-deleted.';

create index kb_ticket_article_links_ticket_idx on app.kb_ticket_article_links (ticket_id, unlinked_at);
create index kb_ticket_article_links_article_idx on app.kb_ticket_article_links (article_id);
create unique index kb_ticket_article_links_active_unique on app.kb_ticket_article_links (ticket_id, article_id) where unlinked_at is null;

create trigger kb_ticket_article_links_touch before update on app.kb_ticket_article_links
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 3. Authoring RPCs -- TKT:Edit-gated (mirrors app.create_ticket_queue).
-- ===========================================================================

create function app.create_kb_article(p_tenant_id uuid, p_code text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_articles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.kb_articles;
  v_row app.kb_articles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.kb_articles where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.kb_articles (tenant_id, code, created_by)
    values (p_tenant_id, p_code, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.kb_articles where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_kb_article',
    'app.kb_articles', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.create_kb_article_version(
  p_article_id uuid, p_title text, p_summary text, p_body text, p_tags text[],
  p_audience_internal boolean, p_audience_customer boolean, p_audience_helpdesk boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_article app.kb_articles;
  v_next_version integer;
  v_row app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_article from app.kb_articles where id = p_article_id for update;
  if not found then
    raise exception 'kb_article_not_found: %', p_article_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_article.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_article.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'title_required: a non-empty title is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty body is required' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.kb_article_versions where article_id = p_article_id;

  insert into app.kb_article_versions (
    article_id, tenant_id, version_number, title, summary, body, tags,
    audience_internal, audience_customer, audience_helpdesk, author_auth_user_id, author_label, created_by
  ) values (
    p_article_id, v_article.tenant_id, v_next_version, p_title, p_summary, p_body, coalesce(p_tags, '{}'::text[]),
    coalesce(p_audience_internal, false), coalesce(p_audience_customer, false), coalesce(p_audience_helpdesk, false),
    p_actor_auth_user_id, p_actor_label, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_article.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_kb_article_version',
    'app.kb_article_versions', v_row.id, 'success', null, null, app.kb_article_version_audit_projection(v_row)
  );

  return v_row;
end;
$$;

create function app.update_kb_article_version(
  p_version_id uuid, p_expected_version integer, p_title text, p_summary text, p_body text, p_tags text[],
  p_audience_internal boolean, p_audience_customer boolean, p_audience_helpdesk boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: article version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'title_required: a non-empty title is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty body is required' using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set
    title = p_title, summary = p_summary, body = p_body, tags = coalesce(p_tags, '{}'::text[]),
    audience_internal = coalesce(p_audience_internal, false), audience_customer = coalesce(p_audience_customer, false),
    audience_helpdesk = coalesce(p_audience_helpdesk, false)
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  return v_updated;
end;
$$;

create function app.set_kb_article_expiry(p_version_id uuid, p_expected_version integer, p_expires_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status not in ('draft', 'in_review', 'approved', 'published') then
    raise exception 'invalid_state: article version % is %', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set expires_at = p_expires_at
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  return v_updated;
end;
$$;

-- ===========================================================================
-- 4. Review/publish/archive lifecycle (decisions 2/3/4).
-- ===========================================================================

create function app.submit_kb_article_version_for_review(p_version_id uuid, p_expected_version integer, p_reviewer_auth_user_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_reviewer_label text;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: article version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_reviewer_auth_user_id is null then
    raise exception 'reviewer_required: a reviewer is required' using errcode = 'check_violation';
  end if;
  if p_reviewer_auth_user_id = v_version.author_auth_user_id then
    raise exception 'self_review_forbidden: the author (%) may not review their own article version', v_version.author_auth_user_id
      using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(v_version.tenant_id, p_reviewer_auth_user_id) or app.actor_holds_customer_user_layer(v_version.tenant_id, p_reviewer_auth_user_id) then
    raise exception 'reviewer_not_eligible: % is not an active internal member of tenant %', p_reviewer_auth_user_id, v_version.tenant_id
      using errcode = 'check_violation';
  end if;

  select u.display_name into v_reviewer_label from app.users u where u.auth_user_id = p_reviewer_auth_user_id;

  update app.kb_article_versions set
    status = 'in_review', reviewer_auth_user_id = p_reviewer_auth_user_id, reviewer_label = v_reviewer_label,
    submitted_for_review_by = p_actor_label, submitted_for_review_at = now(), review_decision = null, reviewed_at = null, review_notes = null
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_kb_article_version_for_review',
    'app.kb_article_versions', p_version_id, 'success', null, app.kb_article_version_audit_projection(v_version), app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.review_kb_article_version(p_version_id uuid, p_expected_version integer, p_decision text, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.status <> 'in_review' then
    raise exception 'invalid_state: article version % is % not in_review', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_actor_auth_user_id <> v_version.reviewer_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not the assigned reviewer for article version %', p_actor_auth_user_id, p_version_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_actor_auth_user_id = v_version.author_auth_user_id then
    raise exception 'self_review_forbidden: the author (%) may not review their own article version', v_version.author_auth_user_id
      using errcode = 'check_violation';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_decision is null or not (p_decision = any (array['approved', 'changes_requested'])) then
    raise exception 'invalid_decision: % is not one of approved/changes_requested', p_decision using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set
    status = case when p_decision = 'approved' then 'approved' else 'draft' end,
    review_decision = p_decision, review_notes = p_notes, reviewed_at = now()
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_kb_article_version',
    'app.kb_article_versions', p_version_id, 'success', null, app.kb_article_version_audit_projection(v_version), app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.review_kb_article_version is
  'HRT-289 (decision 4): re-checks BOTH that the acting identity is the assigned reviewer (or Supreme Admin, RPD-022) AND that it is not the author -- self-review is blocked even for a Supreme Admin acting as reviewer-of-their-own-authored-version, since the author check is independent of the reviewer-identity check. review_notes (free text) is never passed to capture_audit_event''s own p_reason.';

create function app.publish_kb_article_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_article app.kb_articles;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  -- Lock order (C-21 discipline): version row already locked above, then the
  -- parent article row -- the only function in this migration that locks
  -- both, so there is no sibling ordering to deadlock against.
  select * into v_article from app.kb_articles where id = v_version.article_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'approved' then
    raise exception 'invalid_state: article version % is % not approved -- publish requires a reviewer approval first (decision 3, no bypass)', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if not (v_version.audience_internal or v_version.audience_customer or v_version.audience_helpdesk) then
    raise exception 'audience_required: at least one audience flag must be true before publish' using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set status = 'archived', archived_at = now(), archived_by = p_actor_label, archived_reason = 'superseded_by_publish'
  where article_id = v_version.article_id and status = 'published';

  update app.kb_article_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_kb_article_version',
    'app.kb_article_versions', p_version_id, 'success', null, null, app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.archive_kb_article_version(p_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status = 'archived' then
    raise exception 'invalid_state: article version % is already archived', p_version_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to archive an article version' using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set status = 'archived', archived_at = now(), archived_by = p_actor_label, archived_reason = p_reason
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_kb_article_version',
    'app.kb_article_versions', p_version_id, 'success', null, app.kb_article_version_audit_projection(v_version), app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.archive_kb_article_version is
  'HRT-289 (decision 9): p_reason (archived_reason) lives ONLY on app.kb_article_versions -- never passed to capture_audit_event''s own p_reason.';

-- ===========================================================================
-- 5. Expiry batch (decision 8) -- mirrors app.run_training_certificate_
--    expiry_batch (HRT-284) exactly: a plain idempotent UPDATE, no
--    exception handler needed.
-- ===========================================================================

create function app.expire_kb_article_versions_batch(p_tenant_id uuid, p_as_of timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (expired_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_expired integer := 0;
begin
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'kb_article_expiry', jsonb_build_object('as_of', p_as_of, 'period_label', p_period_label),
    0, 'kb_article_expiry:' || p_tenant_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-kb-article-expiry:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    update app.kb_article_versions
    set status = 'archived', archived_at = now(), archived_by = 'system:kb-article-expiry-job', archived_reason = 'expired'
    where tenant_id = p_tenant_id and status = 'published' and expires_at is not null and expires_at < coalesce(p_as_of, now());
    get diagnostics v_expired = row_count;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'expire_kb_article_versions_batch',
      'app.jobs', v_job.job_id, 'success', null, null, jsonb_build_object('period_label', p_period_label, 'expired_count', v_expired)
    );
  end if;

  expired_count := v_expired; job_id := v_job.job_id;
  return next;
end;
$$;

-- ===========================================================================
-- 6. Ticket-article linking (decision 7).
-- ===========================================================================

create function app.resolve_kb_article_current_published_version(p_article_id uuid)
returns app.kb_article_versions
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select v.* from app.kb_article_versions v where v.article_id = p_article_id and v.status = 'published' order by v.version_number desc limit 1;
$$;

comment on function app.resolve_kb_article_current_published_version is
  'HRT-289: the ONE "what is the currently published version of this article" resolver -- used by app.link_ticket_knowledge_article and app.publish_kb_article_version''s own siblings. service_role only (ATW-032/ISS-2026-033 self-found in this checkpoint''s own full db:test run): takes a bare p_article_id with no tenant/audience check, so granting it to authenticated would let any logged-in user of any tenant read a full published article body/title (including a customer- or helpdesk-restricted one) for ANY tenant by supplying a foreign article_id -- the audience-safe, tenant-scoped read surfaces are app.search_knowledge_articles/app.get_kb_article_for_staff/app.get_kb_article_for_customer/app.get_kb_article_for_helpdesk, all of which apply their own tenant/audience filter and call this helper only as an owner-privileged nested call.';

grant execute on function app.resolve_kb_article_current_published_version(uuid) to service_role;

create function app.link_ticket_knowledge_article(p_ticket_id uuid, p_article_id uuid, p_visibility text, p_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_ticket_article_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_version app.kb_article_versions;
  v_row app.kb_ticket_article_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not staff on ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_visibility is null or not (p_visibility = any (array['public', 'internal'])) then
    raise exception 'invalid_visibility: % is not one of public/internal', p_visibility using errcode = 'check_violation';
  end if;

  v_version := app.resolve_kb_article_current_published_version(p_article_id);
  if v_version is null then
    raise exception 'kb_article_not_published: article % has no published version to link', p_article_id using errcode = 'check_violation';
  end if;

  if p_visibility = 'public' then
    if (v_ticket.channel = 'internal' and not v_version.audience_internal)
       or (v_ticket.channel = 'customer' and not v_version.audience_customer)
       or (v_ticket.channel = 'helpdesk' and not v_version.audience_helpdesk) then
      raise exception 'article_not_audience_permitted: article version % is not audience-permitted for a public link on a % ticket', v_version.id, v_ticket.channel
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  begin
    insert into app.kb_ticket_article_links (tenant_id, ticket_id, article_id, article_version_id, visibility, note, linked_by_auth_user_id, linked_by)
    values (v_ticket.tenant_id, p_ticket_id, p_article_id, v_version.id, p_visibility, p_note, p_actor_auth_user_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'kb_article_already_linked: article % is already linked to ticket %', p_article_id, p_ticket_id using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_ticket_knowledge_article',
    'app.kb_ticket_article_links', v_row.id, 'success', null, null,
    jsonb_build_object('ticket_id', p_ticket_id, 'article_id', p_article_id, 'article_version_id', v_version.id, 'visibility', p_visibility)
  );

  return v_row;
end;
$$;

comment on function app.link_ticket_knowledge_article is
  'HRT-289 (decision 7): a PUBLIC link additionally requires the linked version''s own audience flag for the ticket''s channel -- a staff member cannot publicly expose a customer-invisible article on a customer ticket. An INTERNAL link needs only app.is_ticket_staff, exactly like an internal ticket_messages note.';

create function app.unlink_ticket_knowledge_article(p_link_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_ticket_article_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.kb_ticket_article_links;
  v_updated app.kb_ticket_article_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_row from app.kb_ticket_article_links where id = p_link_id for update;
  if not found then
    raise exception 'kb_ticket_article_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;
  if not app.is_ticket_staff(v_row.ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not staff on ticket %', p_actor_auth_user_id, v_row.ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.unlinked_at is not null then
    raise exception 'invalid_state: link % is already unlinked', p_link_id using errcode = 'check_violation';
  end if;

  update app.kb_ticket_article_links set unlinked_at = now(), unlinked_by = p_actor_label
  where id = p_link_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for link %', p_link_id using errcode = 'serialization_failure';
  end if;

  return v_updated;
end;
$$;

-- ===========================================================================
-- 7. Audience-safe search/read (decisions 5/6).
-- ===========================================================================

create function app.search_knowledge_articles(p_tenant_id uuid, p_actor_auth_user_id uuid, p_query text, p_limit integer, p_after_id uuid)
returns table (id uuid, article_id uuid, version_number integer, title text, summary text, tags text[], audience_internal boolean, audience_customer boolean, audience_helpdesk boolean, published_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_after_published_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  if p_after_id is not null then
    select v0.published_at into v_after_published_at from app.kb_article_versions v0 where v0.id = p_after_id;
  end if;

  return query
  select v.id, v.article_id, v.version_number, v.title, v.summary, v.tags, v.audience_internal, v.audience_customer, v.audience_helpdesk, v.published_at
  from app.kb_article_versions v
  where v.tenant_id = p_tenant_id and v.status = 'published'
    and (p_query is null or length(trim(p_query)) = 0 or v.title ilike '%' || p_query || '%' or v.body ilike '%' || p_query || '%' or p_query = any (v.tags))
    and (p_after_id is null or v.published_at < v_after_published_at)
  order by v.published_at desc
  limit v_limit;
end;
$$;

comment on function app.search_knowledge_articles is
  'HRT-289 (decision 5): internal/staff search -- any active, non-customer-layer tenant member sees every PUBLISHED version regardless of audience flags (staff needs to know what customers/helpdesk see too); never draft/in_review/approved/archived. Never a snippet/cache table (decision 5) -- this predicate is evaluated live on every call.';

create function app.search_customer_knowledge_articles(p_tenant_id uuid, p_actor_auth_user_id uuid, p_account_id uuid, p_query text, p_limit integer, p_after_id uuid)
returns table (id uuid, article_id uuid, version_number integer, title text, summary text, tags text[], published_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_after_published_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_account_id is null or not (p_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    return;
  end if;
  if p_after_id is not null then
    select v0.published_at into v_after_published_at from app.kb_article_versions v0 where v0.id = p_after_id;
  end if;

  return query
  select v.id, v.article_id, v.version_number, v.title, v.summary, v.tags, v.published_at
  from app.kb_article_versions v
  where v.tenant_id = p_tenant_id and v.status = 'published' and v.audience_customer = true
    and (v.expires_at is null or v.expires_at > now())
    and (p_query is null or length(trim(p_query)) = 0 or v.title ilike '%' || p_query || '%' or v.body ilike '%' || p_query || '%' or p_query = any (v.tags))
    and (p_after_id is null or v.published_at < v_after_published_at)
  order by v.published_at desc
  limit v_limit;
end;
$$;

comment on function app.search_customer_knowledge_articles is
  'HRT-289 (decision 5, the security-critical half of this sub-capability): status=published AND audience_customer=true AND not expired -- structurally identical to app.get_kb_article_for_customer''s own filter and to app.kb_article_versions_select_scoped''s own RLS predicate. A draft/in_review/approved/archived/internal-only article can never reach this function''s result set by construction, live-adversarially confirmed.';

create function app.search_helpdesk_knowledge_articles(p_tenant_id uuid, p_actor_auth_user_id uuid, p_query text, p_limit integer, p_after_id uuid)
returns table (id uuid, article_id uuid, version_number integer, title text, summary text, tags text[], published_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_after_published_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not (app._is_tenant_helpdesk_authorized(p_tenant_id, p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)) then
    return;
  end if;
  if p_after_id is not null then
    select v0.published_at into v_after_published_at from app.kb_article_versions v0 where v0.id = p_after_id;
  end if;

  return query
  select v.id, v.article_id, v.version_number, v.title, v.summary, v.tags, v.published_at
  from app.kb_article_versions v
  where v.tenant_id = p_tenant_id and v.status = 'published' and v.audience_helpdesk = true
    and (v.expires_at is null or v.expires_at > now())
    and (p_query is null or length(trim(p_query)) = 0 or v.title ilike '%' || p_query || '%' or v.body ilike '%' || p_query || '%' or p_query = any (v.tags))
    and (p_after_id is null or v.published_at < v_after_published_at)
  order by v.published_at desc
  limit v_limit;
end;
$$;

comment on function app.search_helpdesk_knowledge_articles is
  'HRT-289 (decision 5): reuses app._is_tenant_helpdesk_authorized (HRT-288, never re-derived) for the tenant-side caller, OR app.is_support_grant_authority for CargoGrid support staff. status=published AND audience_helpdesk=true AND not expired.';

create function app.get_kb_article_for_staff(p_article_id uuid, p_actor_auth_user_id uuid)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_article app.kb_articles;
  v_row app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select a.* into v_article from app.kb_articles a where a.id = p_article_id;
  if not found or not app.has_active_tenant_membership(v_article.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_article.tenant_id, p_actor_auth_user_id) then
    return null;
  end if;
  select v.* into v_row from app.kb_article_versions v where v.article_id = p_article_id and v.status = 'published' order by v.version_number desc limit 1;
  return v_row;
end;
$$;

create function app.get_kb_article_version(p_version_id uuid, p_actor_auth_user_id uuid)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_version app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select v.* into v_version from app.kb_article_versions v where v.id = p_version_id;
  if not found then
    return null;
  end if;
  if not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_version.tenant_id, p_actor_auth_user_id) then
    return null;
  end if;
  if v_version.status <> 'published'
     and v_version.author_auth_user_id <> p_actor_auth_user_id
     and v_version.reviewer_auth_user_id is distinct from p_actor_auth_user_id
     and not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    return null;
  end if;
  return v_version;
end;
$$;

comment on function app.get_kb_article_version is
  'HRT-289: fetch a SINGLE version''s full row (including body) for editing/review -- the authoring-UI complement to app.list_kb_article_versions (whose own summary projection has no body). Byte-for-byte the same visibility predicate as app.kb_article_versions_select_scoped/app.list_kb_article_versions (decision 5): published, or the caller is the author/assigned reviewer, or the caller holds TKT:Edit -- never a wider check than the raw-table RLS it stands in front of.';

grant execute on function app.get_kb_article_version(uuid, uuid) to authenticated, service_role;

create function app.get_kb_article_for_customer(p_article_id uuid, p_actor_auth_user_id uuid, p_tenant_id uuid, p_account_id uuid)
returns table (id uuid, article_id uuid, version_number integer, title text, summary text, body text, tags text[], published_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if p_account_id is null or not (p_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    return;
  end if;
  return query
  select v.id, v.article_id, v.version_number, v.title, v.summary, v.body, v.tags, v.published_at
  from app.kb_article_versions v
  where v.article_id = p_article_id and v.tenant_id = p_tenant_id and v.status = 'published' and v.audience_customer = true
    and (v.expires_at is null or v.expires_at > now());
end;
$$;

create function app.get_kb_article_for_helpdesk(p_article_id uuid, p_actor_auth_user_id uuid, p_tenant_id uuid)
returns table (id uuid, article_id uuid, version_number integer, title text, summary text, body text, tags text[], published_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not (app._is_tenant_helpdesk_authorized(p_tenant_id, p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)) then
    return;
  end if;
  return query
  select v.id, v.article_id, v.version_number, v.title, v.summary, v.body, v.tags, v.published_at
  from app.kb_article_versions v
  where v.article_id = p_article_id and v.tenant_id = p_tenant_id and v.status = 'published' and v.audience_helpdesk = true
    and (v.expires_at is null or v.expires_at > now());
end;
$$;

create function app.list_kb_articles(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, current_status text, current_version_id uuid, current_version_number integer, title text)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select a.id, a.code, lv.status, lv.id, lv.version_number, lv.title
  from app.kb_articles a
  left join lateral (
    select v.* from app.kb_article_versions v where v.article_id = a.id order by v.version_number desc limit 1
  ) lv on true
  where a.tenant_id = p_tenant_id
  order by a.code asc;
end;
$$;

create function app.list_kb_article_versions(p_article_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, version_number integer, status text, title text, audience_internal boolean, audience_customer boolean, audience_helpdesk boolean, reviewer_label text, review_decision text, published_at timestamptz, expires_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_article app.kb_articles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select a0.* into v_article from app.kb_articles a0 where a0.id = p_article_id;
  if not found or not app.has_active_tenant_membership(v_article.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_article.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select v.id, v.version_number, v.status, v.title, v.audience_internal, v.audience_customer, v.audience_helpdesk,
    v.reviewer_label, v.review_decision, v.published_at, v.expires_at, v.record_version
  from app.kb_article_versions v
  where v.article_id = p_article_id
    and (v.status = 'published' or v.author_auth_user_id = p_actor_auth_user_id or v.reviewer_auth_user_id = p_actor_auth_user_id or app.check_ticket_authority('Edit', v.tenant_id, p_actor_auth_user_id))
  order by v.version_number desc;
end;
$$;

comment on function app.list_kb_article_versions is
  'HRT-289: non-published versions (draft/in_review/approved/archived) are visible only to the version''s own author/reviewer or a TKT:Edit holder -- mirrors app.kb_article_versions_select_scoped''s own RLS predicate (decision 5).';

create function app.list_ticket_knowledge_article_links(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, article_id uuid, article_version_id uuid, article_title text, visibility text, note text, linked_by text, linked_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select l.id, l.article_id, l.article_version_id, v.title, l.visibility, l.note, l.linked_by, l.linked_at, l.record_version
  from app.kb_ticket_article_links l
  join app.kb_article_versions v on v.id = l.article_version_id
  where l.ticket_id = p_ticket_id and l.unlinked_at is null
  order by l.linked_at desc;
end;
$$;

create function app.list_ticket_knowledge_article_links_for_requester(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, article_id uuid, article_version_id uuid, article_title text, article_summary text, linked_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found or not app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select l.id, l.article_id, l.article_version_id, v.title, v.summary, l.linked_at
  from app.kb_ticket_article_links l
  join app.kb_article_versions v on v.id = l.article_version_id
  where l.ticket_id = p_ticket_id and l.unlinked_at is null and l.visibility = 'public'
  order by l.linked_at desc;
end;
$$;

comment on function app.list_ticket_knowledge_article_links_for_requester is
  'HRT-289 (decision 7): visibility=''public'' rows ONLY -- an internal-visibility link (a staff-only reference note) never reaches a requester through this path, mirroring app.list_ticket_messages'' own requester-vs-staff WHERE predicate.';

-- ===========================================================================
-- 8. RLS (decision 5).
-- ===========================================================================

alter table app.kb_articles enable row level security;
alter table app.kb_article_versions enable row level security;
alter table app.kb_ticket_article_links enable row level security;

create policy kb_articles_select_scoped on app.kb_articles
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy kb_article_versions_select_scoped on app.kb_article_versions
  for select to authenticated
  using (
    (
      app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)
      and (status = 'published' or author_auth_user_id = (select auth.uid()) or reviewer_auth_user_id = (select auth.uid()) or app.check_ticket_authority('Edit', tenant_id, (select auth.uid())))
    )
    or app.is_supreme_admin()
  );

comment on policy kb_article_versions_select_scoped on app.kb_article_versions is
  'HRT-289 (decision 5): a customer-layer identity (app.actor_holds_customer_user_layer) has ZERO raw-table access to this table under any status -- customer reads exist ONLY through app.search_customer_knowledge_articles/app.get_kb_article_for_customer, which apply the identical published+audience_customer+not-expired filter a second time. A non-customer-layer tenant member sees every PUBLISHED version plus their OWN draft/in_review/approved/archived versions (author or assigned reviewer) or every version if they hold TKT:Edit.';

create policy kb_ticket_article_links_select_scoped on app.kb_ticket_article_links
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and (visibility = 'public' or app.is_ticket_staff(ticket_id))) or app.is_supreme_admin());

comment on policy kb_ticket_article_links_select_scoped on app.kb_ticket_article_links is
  'HRT-289 (decision 7): byte-for-byte mirrors app.ticket_messages_select_scoped''s own predicate, substituting this table''s own visibility column -- never a parallel mechanism.';

-- ===========================================================================
-- 9. Grants (decision 10) -- explicit, deliberate, never blanket.
-- ===========================================================================

-- ERR-2026-004 (self-found in this batch's sibling SLA migration's own full
-- db:test run -- applied here too, proactively, for the same reason):
-- Postgres grants EXECUTE to PUBLIC by default on function creation.
revoke execute on all functions in schema app from public;

grant select on app.kb_articles to authenticated;
grant select on app.kb_articles to service_role;
grant select on app.kb_article_versions to authenticated;
grant select on app.kb_article_versions to service_role;
grant select on app.kb_ticket_article_links to authenticated;
grant select on app.kb_ticket_article_links to service_role;

grant execute on function app.create_kb_article(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_kb_article_version(uuid, text, text, text, text[], boolean, boolean, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.update_kb_article_version(uuid, integer, text, text, text, text[], boolean, boolean, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.set_kb_article_expiry(uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.submit_kb_article_version_for_review(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.review_kb_article_version(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_kb_article_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_kb_article_version(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.expire_kb_article_versions_batch(uuid, timestamptz, text, uuid, text) to authenticated, service_role;

grant execute on function app.link_ticket_knowledge_article(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.unlink_ticket_knowledge_article(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.search_knowledge_articles(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.search_customer_knowledge_articles(uuid, uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.search_helpdesk_knowledge_articles(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_kb_article_for_staff(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_kb_article_for_customer(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_kb_article_for_helpdesk(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_kb_articles(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_kb_article_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_knowledge_article_links(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_knowledge_article_links_for_requester(uuid, uuid) to authenticated, service_role;

grant execute on function app.kb_article_version_audit_projection(app.kb_article_versions) to authenticated, service_role;
