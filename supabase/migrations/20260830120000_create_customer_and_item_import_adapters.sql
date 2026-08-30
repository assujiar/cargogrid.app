-- ISS-2026-274 (docs/runtime/KNOWN_ISSUES.md) -- no master-data (customer/vendor/item)
-- bulk-import mechanism exists anywhere. Every new tenant's own master data has to be
-- entered by hand, which is an onboarding-scalability wall rather than a live incident.
--
-- The `vendor` third of that entry was closed on 2026-08-30 by
-- `20260830100000_create_vendor_import_adapter.sql` (`ISS-2026-057`). This migration closes
-- the remaining two, `customer` and `item`, in the same shape and with the same discipline,
-- so the entry can be retired rather than partially annotated.
--
-- ---------------------------------------------------------------------------------------
-- A finding that goes beyond ISS-2026-274's own text, and changes what this fix has to be
-- ---------------------------------------------------------------------------------------
--
-- `ISS-2026-274` names `app.create_master_record` as the primitive a customer adapter
-- should compose. That is not correct for customers, and the reason matters: a customer
-- identity in this repository is **not** a `master_records` row. There is no `customer`
-- master type seeded anywhere (the seeded set is `vendor_rate`, `vendor`, `fleet`,
-- `vehicle`, `driver`, `employee`). A customer is an `app.accounts` row -- and, verified
-- directly against the whole migration set this checkpoint, **the only function in the
-- entire repository that has ever inserted into `app.accounts` is
-- `app.convert_quotation_to_account`** (COM-155).
--
-- So before this migration, a customer account could come into existence only by
-- converting an accepted quotation. There was no path at all for the case bulk import
-- exists to serve: a tenant migrating an existing customer book from another system at
-- cutover, where no quotation was ever raised in CargoGrid and fabricating one would be
-- inventing commercial history to satisfy a schema. That gap is a prerequisite of the
-- import adapter, not a side-effect of it, and it is fixed here first.
--
-- `app.create_customer_account_direct` is therefore added as a real second creation path.
-- It is deliberately NOT a lower-authority shortcut around the conversion flow:
--
--   * Same authority. `COM:Approve`, exactly what `app.convert_quotation_to_account`
--     requires -- creating a canonical customer identity is governance-weighted, and a
--     direct path that asked for less would be a privilege-escalation surface, not a
--     convenience.
--   * Same duplicate control, not a parallel one. It computes
--     `normalized_legal_name`/`normalized_tax_id`/`duplicate_fingerprint` through the same
--     `app.normalize_prospect_identifier`/`app.compute_prospect_duplicate_fingerprint`
--     functions, so the `accounts_tenant_fingerprint_active_unique` index sees identical
--     input. It cannot be used to slip a duplicate customer past a control the quotation
--     path enforces.
--   * Same create-or-link outcome on collision. A fingerprint collision resolves to the
--     existing active account, exactly as COM-155's own race-recovery arm does. That is
--     the designed behaviour of that index, not an error condition.
--   * `source_prospect_id` is left null, honestly. There was no prospect. It is not
--     back-filled with a fabricated one.
--
-- ---------------------------------------------------------------------------------------
-- One deliberate difference from the vendor adapter, called out so it is not "corrected"
-- ---------------------------------------------------------------------------------------
--
-- `app.commit_vendor_import_job` RAISES if a staged row resolves to a vendor profile
-- already bound to a different staged row, because `app.create_vendor_profile_draft` has no
-- create-or-link semantics and such a resolution could only mean something had gone wrong.
--
-- The customer and item adapters must NOT raise there, and the difference is not laxity.
-- Both underlying primitives are deliberately create-or-link:
-- `create_customer_account_direct` resolves a fingerprint collision to the existing
-- account, and `app.create_item_master` is idempotent on
-- `(tenant_id, owner_account_id, code)` and returns the existing row. So two staged rows
-- naming the same legal identity, or the same item code under the same owner -- an
-- entirely ordinary thing in a migration extract -- legitimately resolve to one record.
-- Aborting a thousand-row cutover file over that would be wrong. Those rows are counted
-- and reported as `linked_existing` in the commit's own audit payload, never silently
-- dropped and never miscounted as created.
--
-- Everything else follows `20260830100000` exactly: the generic `app.validate_staging_row`
-- is called unchanged and never reimplemented; domain writes go only through the canonical
-- primitive, never a direct INSERT (Prompt 131 §24); `unique_violation` is discriminated by
-- constraint name and never caught blanket; provenance is stamped through a partial unique
-- index with no `where ... is null` silent-no-op path; and `p_client_ip` carries
-- `ISS-2026-278`'s IP-allowlist shape at birth.
--
-- Per `ERR-2026-004`: explicit `revoke execute on all functions in schema app from public;`
-- before the final grants. No already-applied migration is edited.

-- ===========================================================================
-- 1. RBAC seed additions (ADR-0020 shape) -- new (action, module) rows only.
--    The fixed permissions_action_check CHECK constraint is never altered;
--    'Import' is already an accepted action (PRC and HRS both seed it).
-- ===========================================================================

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Import', 'COM', 'standard', false),
  ('Import', 'OPS', 'standard', false);

-- ===========================================================================
-- 2. Provenance links.
-- ===========================================================================

alter table app.accounts
  add column source_import_staging_row_id uuid references app.import_staging_rows (id);

create unique index accounts_source_import_row_unique
  on app.accounts (source_import_staging_row_id)
  where source_import_staging_row_id is not null;

comment on column app.accounts.source_import_staging_row_id is
  'ISS-2026-274: set only by app.commit_customer_import_job -- the staged row that produced this account, uniquely indexed so a staged row can ever produce at most one account (idempotent-safe commit replay). Null for every account created through app.convert_quotation_to_account, and for any imported row that resolved to an already-existing account by duplicate fingerprint rather than creating one.';

alter table app.item_masters
  add column source_import_staging_row_id uuid references app.import_staging_rows (id);

create unique index item_masters_source_import_row_unique
  on app.item_masters (source_import_staging_row_id)
  where source_import_staging_row_id is not null;

comment on column app.item_masters.source_import_staging_row_id is
  'ISS-2026-274: set only by app.commit_item_import_job -- the staged row that produced this item master, uniquely indexed so a staged row can ever produce at most one item. Null for every hand-created item, and for any imported row that resolved to an already-existing (tenant, owner_account, code) item rather than creating one.';

-- ===========================================================================
-- 3. app.create_customer_account_direct -- the missing canonical primitive.
-- ===========================================================================

create function app.create_customer_account_direct(
  p_tenant_id uuid,
  p_legal_name text,
  p_trade_name text,
  p_tax_id text,
  p_billing_address jsonb,
  p_parent_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.accounts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_normalized_legal_name text;
  v_normalized_tax_id text;
  v_fingerprint text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_legal_name is null or length(trim(p_legal_name)) = 0 then
    raise exception 'missing_legal_name: legal_name is required to create a customer account'
      using errcode = 'check_violation';
  end if;

  -- COM:Approve, identical to app.convert_quotation_to_account. A direct creation path
  -- that asked for less authority than the conversion path would be a way around that
  -- gate rather than a second door to the same room.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_parent_account_id is not null and not exists (
    select 1 from app.accounts where id = p_parent_account_id and tenant_id = p_tenant_id and status = 'active'
  ) then
    raise exception 'parent_account_not_found: no active account % in tenant %', p_parent_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  -- The SAME normalization and fingerprint functions the quotation path uses, so the
  -- accounts_tenant_fingerprint_active_unique index sees identical input from both doors.
  v_normalized_legal_name := app.normalize_prospect_identifier(p_legal_name);
  v_normalized_tax_id := app.normalize_prospect_identifier(p_tax_id);
  v_fingerprint := app.compute_prospect_duplicate_fingerprint(p_tenant_id, v_normalized_legal_name, v_normalized_tax_id);

  -- Pre-check, then a nested handler for the genuine race, mirroring COM-155's own
  -- create-or-link arm. A collision resolves to the existing active account: that is what
  -- the fingerprint index is for, not an error.
  select * into v_account from app.accounts
  where tenant_id = p_tenant_id and duplicate_fingerprint = v_fingerprint and status = 'active';
  if found then
    return v_account;
  end if;

  begin
    insert into app.accounts (
      tenant_id, legal_name, trade_name, tax_id, normalized_legal_name, normalized_tax_id,
      duplicate_fingerprint, billing_address, parent_account_id, source_prospect_id,
      owner_user_id, created_by
    ) values (
      p_tenant_id, p_legal_name, nullif(trim(coalesce(p_trade_name, '')), ''), nullif(trim(coalesce(p_tax_id, '')), ''),
      v_normalized_legal_name, v_normalized_tax_id, v_fingerprint,
      coalesce(p_billing_address, '{}'::jsonb), p_parent_account_id,
      -- Deliberately null: there was no prospect. Never back-filled with a fabricated one
      -- to make the row look like it came through the quotation path.
      null,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_account;
  exception
    when unique_violation then
      -- Only the fingerprint index means "this customer already exists, link to it". Any
      -- other unique_violation is a real failure and must propagate.
      select * into v_account from app.accounts
      where tenant_id = p_tenant_id and duplicate_fingerprint = v_fingerprint and status = 'active';
      if not found then
        raise;
      end if;
      return v_account;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_customer_account_direct',
    'app.accounts', v_account.id, 'success', null, null,
    jsonb_build_object('legal_name', p_legal_name, 'tax_id', p_tax_id, 'source', 'direct')
  );

  return v_account;
end;
$$;

comment on function app.create_customer_account_direct is
  'ISS-2026-274: the second real creation path for a customer identity, added because app.convert_quotation_to_account was the ONLY function in this repository that had ever inserted into app.accounts -- so a tenant migrating an existing customer book at cutover had no path that did not involve inventing a quotation. Requires COM:Approve, exactly as the conversion path does. Computes normalization and the duplicate fingerprint through the same app.normalize_prospect_identifier/app.compute_prospect_duplicate_fingerprint functions, so it cannot slip a duplicate past a control the quotation path enforces; a fingerprint collision resolves to the existing active account (create-or-link), matching COM-155''s own race-recovery arm. source_prospect_id is left null honestly -- there was no prospect.';

-- ===========================================================================
-- 4. Schema-kind registrations.
-- ===========================================================================

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('customer_import', 'Customer Import', 'COM', 'system'),
       ('item_import', 'Item Master Import', 'OPS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:customer_import', 'Customer Import', 'COM', 'system'),
       ('import_export:item_import', 'Item Master Import', 'OPS', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 5. app.validate_customer_import_row
-- ===========================================================================

create function app.validate_customer_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['legal_name', 'trade_name', 'tax_id', 'billing_line1', 'billing_city', 'billing_region', 'billing_postal_code', 'billing_country'];
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  if coalesce(trim(v_payload ->> 'legal_name'), '') = '' then
    v_errors := v_errors || 'legal_name: must not be empty or whitespace-only'::text;
  end if;

  -- Lifecycle and identity fields the adapter alone controls. A file must not be able to
  -- claim a customer is already merged, nor supply its own duplicate fingerprint (which
  -- would be a way to steer, or defeat, the duplicate control).
  foreach v_field in array array['status', 'merged_into_id', 'duplicate_fingerprint', 'normalized_legal_name', 'normalized_tax_id', 'source_prospect_id'] loop
    if v_payload ? v_field then
      v_errors := v_errors || (v_field || ': is not an importable column -- it is derived or controlled by the platform, never supplied by a file');
    end if;
  end loop;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows
    set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id
    returning * into v_row;

    update app.jobs
    set valid_row_count = valid_row_count - 1, invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_customer_import_row is
  'ISS-2026-274: domain row validator for the customer_import schema. Calls app.validate_staging_row UNCHANGED for the structural pass, then adds formula/spreadsheet-injection rejection (with the raw payload preserved verbatim), a whitespace-only legal_name check, and refusal of any platform-derived or lifecycle column a file must never supply -- duplicate_fingerprint in particular, since supplying it would be a way to steer or defeat the duplicate control.';

-- ===========================================================================
-- 6. app.commit_customer_import_job
-- ===========================================================================

create function app.commit_customer_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_billing jsonb;
  v_account app.accounts;
  v_created_count integer := 0;
  v_linked_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'customer_import' then
    raise exception 'import_export_wrong_schema: job % is not a customer_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'COM', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.accounts where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    -- Billing address is assembled from flat columns: a spreadsheet cell cannot carry a
    -- jsonb object, and accepting raw JSON text from a file would be handing an importer
    -- direct control of a jsonb column's shape.
    v_billing := jsonb_strip_nulls(jsonb_build_object(
      'line1', nullif(v_payload ->> 'billing_line1', ''),
      'city', nullif(v_payload ->> 'billing_city', ''),
      'region', nullif(v_payload ->> 'billing_region', ''),
      'postalCode', nullif(v_payload ->> 'billing_postal_code', ''),
      'country', nullif(v_payload ->> 'billing_country', '')
    ));

    -- The canonical write path. No unique_violation handler here deliberately: the only
    -- collision this primitive can hit is the duplicate fingerprint, which it resolves
    -- internally to the existing account rather than raising. Anything that does escape is
    -- a genuine failure and must abort the whole commit.
    v_account := app.create_customer_account_direct(
      v_job.tenant_id,
      v_payload ->> 'legal_name',
      nullif(v_payload ->> 'trade_name', ''),
      nullif(v_payload ->> 'tax_id', ''),
      v_billing,
      null,
      p_actor_auth_user_id,
      p_actor_label
    );

    if v_account.source_import_staging_row_id = v_row.id then
      v_skipped_count := v_skipped_count + 1;
      continue;
    elsif v_account.source_import_staging_row_id is not null then
      -- Resolved by duplicate fingerprint to an account an EARLIER staged row created.
      -- See this migration's header: this is the designed behaviour of
      -- accounts_tenant_fingerprint_active_unique, not an anomaly, and it is counted and
      -- reported rather than silently dropped or miscounted as created.
      v_linked_count := v_linked_count + 1;
      continue;
    elsif v_account.created_at < v_job.created_at then
      -- Resolved to an account that predates this job entirely. Also a legitimate link,
      -- and deliberately NOT stamped: stamping it would rewrite the provenance of a record
      -- this import did not create.
      v_linked_count := v_linked_count + 1;
      continue;
    end if;

    begin
      update app.accounts
      set source_import_staging_row_id = v_row.id
      where id = v_account.id
      returning * into v_account;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'accounts_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_customer_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'accounts_created', v_created_count,
      'rows_linked_to_existing_account', v_linked_count,
      'rows_already_committed_skipped', v_skipped_count
    )
  );

  return v_updated;
end;
$$;

comment on function app.commit_customer_import_job is
  'ISS-2026-274: the PLT-131 domain-write adapter for the customer_import schema. Requires BOTH app.is_support_grant_authority AND COM:Import; app.create_customer_account_direct then separately enforces its own COM:Approve gate per row. Writes only through that canonical primitive, never a direct INSERT. A staged row whose legal identity matches an existing active account resolves to it by duplicate fingerprint and is counted as rows_linked_to_existing_account -- an ordinary occurrence in a migration extract, never a silent drop and never miscounted as created; such a row is deliberately NOT stamped with provenance, since this import did not create that account. Idempotent per staged row (accounts_source_import_row_unique, defended by a pre-check, an explicit already-bound branch, a nested unique_violation handler scoped to that one constraint name, and a job-scoped advisory lock). p_client_ip carries ISS-2026-278''s IP-allowlist shape.';

-- ===========================================================================
-- 7. app.validate_item_import_row
-- ===========================================================================

create function app.validate_item_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_job app.jobs;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['code', 'name', 'description', 'base_uom_code', 'owner_account_tax_id', 'owner_account_legal_name'];
  v_owner_tax text;
  v_owner_name text;
  v_match_count integer;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;
  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  if coalesce(trim(v_payload ->> 'code'), '') = '' then
    v_errors := v_errors || 'code: must not be empty or whitespace-only'::text;
  end if;
  if coalesce(trim(v_payload ->> 'name'), '') = '' then
    v_errors := v_errors || 'name: must not be empty or whitespace-only'::text;
  end if;

  -- base_uom_code must resolve to a registered active UOM. The generic validator can only
  -- see that it is text; app.create_item_master would otherwise reject it mid-commit and
  -- abort every other row in the batch.
  if not app.validate_uom_code(v_payload ->> 'base_uom_code') then
    v_errors := v_errors || ('base_uom_code: ' || coalesce(v_payload ->> 'base_uom_code', '(missing)') || ' is not a registered active UOM code');
  end if;

  -- Owner account resolution. app.item_masters.owner_account_id is NOT NULL by design
  -- ("a 3PL item always belongs to exactly one customer account"), and a spreadsheet cannot
  -- meaningfully carry a uuid -- so the file names the owner by tax id (preferred, more
  -- precise) or legal name, and this validator resolves it. Ambiguity is an ERROR, never a
  -- silent pick: attaching a customer's items to the wrong account is a data-confidentiality
  -- problem, not a tidiness one.
  v_owner_tax := nullif(trim(coalesce(v_payload ->> 'owner_account_tax_id', '')), '');
  v_owner_name := nullif(trim(coalesce(v_payload ->> 'owner_account_legal_name', '')), '');

  if v_owner_tax is null and v_owner_name is null then
    v_errors := v_errors || 'owner_account: one of owner_account_tax_id or owner_account_legal_name is required -- every item master belongs to exactly one customer account'::text;
  else
    if v_owner_tax is not null then
      select count(*) into v_match_count from app.accounts
      where tenant_id = v_job.tenant_id and status = 'active'
        and normalized_tax_id = app.normalize_prospect_identifier(v_owner_tax);
      if v_match_count = 0 then
        v_errors := v_errors || ('owner_account_tax_id: ' || v_owner_tax || ' does not resolve to an active customer account in this tenant');
      elsif v_match_count > 1 then
        v_errors := v_errors || ('owner_account_tax_id: ' || v_owner_tax || ' matches ' || v_match_count || ' active accounts -- ambiguous, refusing to guess which customer owns this item');
      end if;
    else
      select count(*) into v_match_count from app.accounts
      where tenant_id = v_job.tenant_id and status = 'active'
        and normalized_legal_name = app.normalize_prospect_identifier(v_owner_name);
      if v_match_count = 0 then
        v_errors := v_errors || ('owner_account_legal_name: ' || v_owner_name || ' does not resolve to an active customer account in this tenant');
      elsif v_match_count > 1 then
        v_errors := v_errors || ('owner_account_legal_name: ' || v_owner_name || ' matches ' || v_match_count || ' active accounts -- ambiguous, supply owner_account_tax_id instead');
      end if;
    end if;
  end if;

  foreach v_field in array array['status', 'record_version'] loop
    if v_payload ? v_field then
      v_errors := v_errors || (v_field || ': is not an importable column -- it is controlled by the platform, never supplied by a file');
    end if;
  end loop;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows
    set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id
    returning * into v_row;

    update app.jobs
    set valid_row_count = valid_row_count - 1, invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_item_import_row is
  'ISS-2026-274: domain row validator for the item_import schema. Calls app.validate_staging_row UNCHANGED, then adds what it structurally cannot do: formula/spreadsheet-injection rejection, non-empty code/name, base_uom_code resolving to a registered active UOM (otherwise app.create_item_master would reject it mid-commit and abort the whole batch), and owner-account resolution by tax id or legal name. An owner name matching more than one active account is an ERROR, never a silent pick -- attaching one customer''s items to another customer''s account is a confidentiality problem, not a tidiness one.';

-- ===========================================================================
-- 8. app.commit_item_import_job
-- ===========================================================================

create function app.commit_item_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_owner_tax text;
  v_owner_name text;
  v_owner_account_id uuid;
  v_item app.item_masters;
  v_created_count integer := 0;
  v_linked_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'item_import' then
    raise exception 'import_export_wrong_schema: job % is not an item_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.item_masters where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_owner_tax := nullif(trim(coalesce(v_payload ->> 'owner_account_tax_id', '')), '');
    v_owner_name := nullif(trim(coalesce(v_payload ->> 'owner_account_legal_name', '')), '');
    v_owner_account_id := null;

    -- Re-resolved here, not carried from validation: an account could have been merged or
    -- deactivated between validate and commit, and the ambiguity check must hold at write
    -- time, not only at check time.
    if v_owner_tax is not null then
      select a.id into v_owner_account_id from app.accounts a
      where a.tenant_id = v_job.tenant_id and a.status = 'active'
        and a.normalized_tax_id = app.normalize_prospect_identifier(v_owner_tax);
      if not found then
        raise exception 'import_owner_account_not_found: staged row % names owner_account_tax_id %, which no longer resolves to exactly one active account in tenant %', v_row.row_number, v_owner_tax, v_job.tenant_id
          using errcode = 'check_violation';
      end if;
    else
      select a.id into v_owner_account_id from app.accounts a
      where a.tenant_id = v_job.tenant_id and a.status = 'active'
        and a.normalized_legal_name = app.normalize_prospect_identifier(v_owner_name);
      if not found then
        raise exception 'import_owner_account_not_found: staged row % names owner_account_legal_name %, which no longer resolves to exactly one active account in tenant %', v_row.row_number, v_owner_name, v_job.tenant_id
          using errcode = 'check_violation';
      end if;
    end if;

    -- The canonical write path -- app.create_item_master is itself idempotent on
    -- (tenant_id, owner_account_id, code) and returns the existing row, so no
    -- unique_violation handler belongs around this call.
    v_item := app.create_item_master(
      v_job.tenant_id,
      v_owner_account_id,
      v_payload ->> 'code',
      v_payload ->> 'name',
      nullif(v_payload ->> 'description', ''),
      v_payload ->> 'base_uom_code',
      coalesce((nullif(v_payload ->> 'lot_controlled', ''))::boolean, false),
      coalesce((nullif(v_payload ->> 'serial_controlled', ''))::boolean, false),
      coalesce((nullif(v_payload ->> 'expiry_controlled', ''))::boolean, false),
      p_actor_auth_user_id,
      p_actor_label
    );

    if v_item.source_import_staging_row_id = v_row.id then
      v_skipped_count := v_skipped_count + 1;
      continue;
    elsif v_item.source_import_staging_row_id is not null then
      v_linked_count := v_linked_count + 1;
      continue;
    elsif v_item.created_at < v_job.created_at then
      -- An item that predates this job. A legitimate link, deliberately not stamped.
      v_linked_count := v_linked_count + 1;
      continue;
    end if;

    begin
      update app.item_masters
      set source_import_staging_row_id = v_row.id
      where id = v_item.id
      returning * into v_item;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'item_masters_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_item_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'item_masters_created', v_created_count,
      'rows_linked_to_existing_item', v_linked_count,
      'rows_already_committed_skipped', v_skipped_count
    )
  );

  return v_updated;
end;
$$;

comment on function app.commit_item_import_job is
  'ISS-2026-274: the PLT-131 domain-write adapter for the item_import schema. Requires BOTH app.is_support_grant_authority AND OPS:Import; app.create_item_master then separately enforces its own OPS:Create gate per row. The owner account is re-resolved at commit time, not carried from validation -- an account can be merged or deactivated in between, and the ambiguity check must hold at write time. A staged row matching an existing (tenant, owner_account, code) item resolves to it and is counted as rows_linked_to_existing_item, never a silent drop and never miscounted as created. Idempotent per staged row (item_masters_source_import_row_unique). p_client_ip carries ISS-2026-278''s IP-allowlist shape.';

-- ===========================================================================
-- 9. PostgREST wrappers (RGL-394 Option 2). Security mode MATCHES each app.*
--    counterpart exactly -- the validators are invoker, the writers are definer.
--    A definer wrapper over an invoker function is an RLS-bypass-class defect,
--    and scripts/db-tests/public-api-wrapper-regression.sql enforces parity.
-- ===========================================================================

create function public.create_customer_account_direct(p_tenant_id uuid, p_legal_name text, p_trade_name text, p_tax_id text, p_billing_address jsonb, p_parent_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.accounts
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.create_customer_account_direct(p_tenant_id, p_legal_name, p_trade_name, p_tax_id, p_billing_address, p_parent_account_id, p_actor_auth_user_id, p_actor_label);
$$;

create function public.validate_customer_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $$
  select app.validate_customer_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$$;

create function public.commit_customer_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.commit_customer_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$$;

create function public.validate_item_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $$
  select app.validate_item_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$$;

create function public.commit_item_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.commit_item_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$$;

-- ===========================================================================
-- 10. Grants (ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.create_customer_account_direct(uuid, text, text, text, jsonb, uuid, uuid, text) to service_role;
grant execute on function app.validate_customer_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_customer_import_job(uuid, boolean, uuid, text, text) to service_role;
grant execute on function app.validate_item_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_item_import_job(uuid, boolean, uuid, text, text) to service_role;

revoke execute on function public.create_customer_account_direct(uuid, text, text, text, jsonb, uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.create_customer_account_direct(uuid, text, text, text, jsonb, uuid, uuid, text) to service_role;

revoke execute on function public.validate_customer_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_customer_import_row(uuid, uuid, text) to service_role;

revoke execute on function public.commit_customer_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_customer_import_job(uuid, boolean, uuid, text, text) to service_role;

revoke execute on function public.validate_item_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_item_import_row(uuid, uuid, text) to service_role;

revoke execute on function public.commit_item_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_item_import_job(uuid, boolean, uuid, text, text) to service_role;
