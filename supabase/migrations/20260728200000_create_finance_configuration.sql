-- Finance capability FIN-191 (Finance Configuration, CG-S9-FIN-002)
-- Tenant/company-scoped versioned Finance policy covering accounting dimensions,
-- document numbering, posting-map references, rounding rules, and a combined
-- budget-control/accrual/revenue-cost-recognition/close-dependency policy class.
--
-- Reuse decision (disclosed, matching every prior checkpoint's discipline; the
-- exact decision `docs/build-log/phase-04/00_FINANCE_WBS.md` section 6 records):
-- this migration adds **zero** new draft/publish/rollback/version state machine.
-- Finance Configuration is `PLT-121`'s own Configuration Engine
-- (`app.config_types`/`config_objects`/`config_versions`/`config_items`/
-- `config_dependencies`, `create_config_draft`/`set_config_items`/
-- `publish_config_version`/`discard_config_draft`/`rollback_config_version`/
-- `resolve_config`), reused directly -- the same "later phases register their own
-- real config content into this same mechanism via `app.register_config_type()`"
-- extension point `PLT-121`'s own migration header names explicitly. Finance is
-- the first business-domain module in this repository to exercise that
-- extension point (every capability through `OPS-188` either left the 10
-- bootstrap platform-primitive config types alone or read an existing one,
-- `'approval'`, rather than registering a new one -- confirmed by direct
-- `grep -rn "insert into app.config_types"` across all 71 prior migrations).
--
-- What this migration adds on top of the reused engine (disclosed, not a parallel
-- copy of the generic mechanics themselves):
-- * Six new `app.config_types` rows (finance-owned, `owner_primitive_code='FIN'`)
--   -- structurally identical registration to `PLT-121`'s own 10 bootstrap rows.
-- * `app.finance_rounding_modes`: a small, bounded reference table of rounding
--   *conventions* (half-up/half-even/down/up) -- a math convention, never a tax
--   or legal rate, so RPD-016's "no invented legal rate" boundary does not apply
--   here. `FIN-194` (Currency and Exchange-Rate) reuses this same table for its
--   own conversion rounding, per Prompt 191 section 6's "rounding tie-in to 191's
--   rounding policy" requirement -- one rounding-mode catalogue, not two.
-- * `app.validate_finance_config_version()`: a per-class structural validation
--   dispatcher, run at publish time (Finance-specific; the generic engine's own
--   `publish_config_version()` only checks the dependency-cycle graph, which
--   applies uniformly across every config_type). Bounded enums only (rounding
--   mode, budget-control mode, accrual method, revenue/cost-recognition method)
--   -- no tax/legal content, satisfying RPD-016/021's "not invent legal rates or
--   advice" boundary; every mode here is an accounting *mechanism* label, not a
--   jurisdiction-specific statutory rule.
-- * Six `app.create_finance_config_draft`/`set_finance_config_items`/
--   `publish_finance_config_version`/`discard_finance_config_draft`/
--   `rollback_finance_config_version`/`resolve_finance_config` wrapper functions:
--   each (a) rejects any `config_type_code` outside the six Finance types
--   (`not_finance_config_type`) -- defense in depth so this Finance-labelled
--   surface can never be used to draft/publish/rollback an unrelated config type
--   such as `'approval'`; (b) enforces `FIN:Edit` (draft/set-items/discard) or
--   `FIN:Approve` (publish/rollback) via `app.evaluate_permission` -- "Finance
--   Admin drafts; configured approvers publish" (Prompt 191 section 26) mapped onto
--   this repository's own canonical, already-registered `FIN` permission
--   catalogue (`PLT-111`) rather than inventing a new permission action; (c)
--   delegates every actual draft/publish/rollback mechanic to the unmodified
--   generic engine function. `resolve_finance_config` mirrors `resolve_config`'s
--   own security posture exactly (no in-function actor check -- "the resolver
--   bypasses RLS internally, its own parameters are the boundary," `PLT-121`'s
--   own disclosed pattern for every one of its `evaluate_*`-shaped resolvers);
--   the calling layer (Finance portal guard, section 15/26) is the real boundary,
--   the same posture every prior `resolve_*`/`evaluate_*` function in this
--   repository already uses.
-- * `app.preview_finance_config_impact()`: the "preview-impact" operation Prompt
--   191 section 14 requires -- runs the same structural validator plus, for the
--   `finance_posting_map` class only, lists every referenced account-code
--   candidate as `pending_chart_of_accounts` (FIN-192 has not run yet in this
--   dependency order -- Prompt 191 section 6's own "posting map preview must be
--   ... source-reconcilable" is honoured by disclosing exactly what is not yet
--   resolvable, never by silently claiming a resolution this capability cannot
--   make). `FIN-192`'s own migration extends `publish_finance_config_version`
--   (`CREATE OR REPLACE FUNCTION`, its own existing extension convention -- see
--   `20260724290000_create_commercial_customer_account_conversion.sql` for the
--   established precedent of a later migration extending an earlier one's
--   function by full replacement) to add the real existence/active-state check
--   once `app.finance_accounts` exists.
--
-- Posting-map account-code references are stored structurally only at this
-- checkpoint (regex-shaped, `^[A-Z0-9._-]{1,20}$`, uniqueness within one version)
-- -- Prompt 191 section 25's "every posting map resolves to active compatible
-- accounts and dimensions" is a `FIN-192` dependency (chart of accounts does not
-- exist yet, correctly reflected by the dependency order in
-- `189_FINANCE_README.md` section 4: `191` precedes `192`), not silently promised here.
--
-- Money/decimal discipline (Prompt 191 section 24/section 68 binding rule): this
-- migration introduces zero money-shaped column of its own (Finance Configuration
-- is policy metadata, not a transaction) -- the `finance_rounding` class's own
-- `precision` item value is a bounded integer (0-6), never a float, and is the
-- exact-decimal rounding contract every later money-producing Finance capability
-- (`FIN-192`..`FIN-214`) must read rather than reinvent its own.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its
-- own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC`
-- statement before its final grants, the standing per-migration convention since
-- `PLT-118`.

-- The six Finance Configuration classes (Prompt 191 section 3's own feature-slice
-- list: "accounting dimensions, numbering, posting, rounding, budget/accrual/
-- recognition and close-policy baseline"). Registered directly (matching
-- `PLT-121`'s own bootstrap `insert into app.config_types` -- `app.register_config_type()`
-- itself is Supreme-Admin-runtime-only, not how migration-time bootstrap rows are
-- seeded anywhere in this repository).
insert into app.config_types (code, name, owner_primitive_code, registered_by) values
  ('finance_dimensions', 'Finance Accounting Dimensions', 'FIN', 'finance-foundation'),
  ('finance_numbering', 'Finance Document Numbering', 'FIN', 'finance-foundation'),
  ('finance_posting_map', 'Finance Posting Map', 'FIN', 'finance-foundation'),
  ('finance_rounding', 'Finance Rounding Rules', 'FIN', 'finance-foundation'),
  ('finance_recognition', 'Finance Budget/Accrual/Recognition Policy', 'FIN', 'finance-foundation'),
  ('finance_close_policy', 'Finance Close Dependency Baseline', 'FIN', 'finance-foundation');

-- A bounded catalogue of rounding *conventions* (never a tax/legal rate -- see
-- this migration's own header). Reused by `FIN-194`'s own exchange-rate
-- conversion rounding (Prompt 191 section 6 / Prompt 194 section 6's "rounding rules
-- tie-in to 191's rounding policy" requirement) -- one catalogue, not two.
create table app.finance_rounding_modes (
  code text primary key,
  name text not null,
  description text not null
);

comment on table app.finance_rounding_modes is
  'FIN-191: the bounded set of exact-decimal rounding conventions any Finance money computation may declare (never a tax/legal rate -- see this migration''s own header). Referenced by finance_rounding config items and reused directly by FIN-194''s exchange-rate conversion rounding.';

insert into app.finance_rounding_modes (code, name, description) values
  ('round_half_up', 'Round half up', 'Round 0.5 away from zero -- the common commercial-rounding default.'),
  ('round_half_even', 'Round half to even (banker''s rounding)', 'Round 0.5 to the nearest even digit -- minimizes cumulative rounding bias across many transactions.'),
  ('round_down', 'Round down (truncate toward zero)', 'Always drop the excess fractional amount -- never rounds in the payer''s favor.'),
  ('round_up', 'Round up (away from zero)', 'Always add a unit at the declared precision -- never rounds in the payer''s favor.');

-- The six Finance-owned config_type codes this migration's wrapper functions may
-- ever touch -- checked by every wrapper below via `= any(...)`, never
-- hardcoded six times over (single source of truth for the whitelist).
create function app.is_finance_config_type(p_config_type_code text)
returns boolean
language sql
immutable
as $$
  select p_config_type_code = any (array[
    'finance_dimensions', 'finance_numbering', 'finance_posting_map',
    'finance_rounding', 'finance_recognition', 'finance_close_policy'
  ]);
$$;

comment on function app.is_finance_config_type is
  'FIN-191: the single whitelist every Finance Configuration wrapper function checks before delegating to the generic Configuration Engine -- defense in depth so this Finance-labelled surface can never draft/publish/rollback an unrelated config type (e.g. ''approval'').';

-- Per-class structural validation, run at publish/preview time (Prompt 191 section 20
-- task 2's "validate dependencies" / section 25's validation rules). Bounded enums
-- only; no tax/legal content (RPD-016/021).
create function app.validate_finance_config_version(p_version_id uuid, p_config_type_code text)
returns boolean
language plpgsql
as $$
declare
  v_item record;
  v_count integer;
  v_precision integer;
  v_mode text;
  v_order text;
  v_seq_occurrences integer;
  v_format text;
  v_reset_period text;
  v_padding integer;
  v_tokens text[];
  v_token text;
  v_allowed_tokens text[] := array['YYYY', 'YY', 'MM', 'DD', 'SEQ'];
  v_seen_codes text[] := array[]::text[];
begin
  select count(*) into v_count from app.config_items where config_version_id = p_version_id;
  if v_count = 0 then
    raise exception 'finance_config_empty: version % has no items to validate', p_version_id
      using errcode = 'check_violation';
  end if;

  if p_config_type_code = 'finance_dimensions' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      if not (v_item.key ~ '^[A-Z][A-Z0-9_]{0,31}$') then
        raise exception 'finance_dimension_invalid_code: dimension code % must be uppercase snake_case (max 32 chars)', v_item.key
          using errcode = 'check_violation';
      end if;
      if v_item.value ->> 'name' is null or length(trim(v_item.value ->> 'name')) = 0 then
        raise exception 'finance_dimension_missing_name: dimension % has no non-empty name', v_item.key
          using errcode = 'check_violation';
      end if;
      if jsonb_typeof(v_item.value -> 'required') is distinct from 'boolean' then
        raise exception 'finance_dimension_invalid_required: dimension % must declare a boolean required flag', v_item.key
          using errcode = 'check_violation';
      end if;
    end loop;

  elsif p_config_type_code = 'finance_numbering' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      v_format := v_item.value ->> 'format';
      v_reset_period := v_item.value ->> 'resetPeriod';
      v_padding := (v_item.value ->> 'padding')::integer;

      if v_format is null or length(v_format) = 0 then
        raise exception 'finance_numbering_missing_format: document class % has no non-empty format', v_item.key
          using errcode = 'check_violation';
      end if;

      v_seq_occurrences := (length(v_format) - length(replace(v_format, '{SEQ}', ''))) / length('{SEQ}');
      if v_seq_occurrences <> 1 then
        raise exception 'finance_numbering_invalid_seq_token_count: document class % format must contain exactly one {SEQ} token, found %', v_item.key, v_seq_occurrences
          using errcode = 'check_violation';
      end if;

      select array_agg(m[1]) into v_tokens from regexp_matches(v_format, '\{([A-Z_]+)\}', 'g') as m;
      foreach v_token in array coalesce(v_tokens, array[]::text[]) loop
        if not (v_token = any (v_allowed_tokens)) then
          raise exception 'finance_numbering_unknown_token: document class % format references unrecognized token {%}', v_item.key, v_token
            using errcode = 'check_violation';
        end if;
      end loop;

      if v_reset_period is null or v_reset_period not in ('never', 'yearly', 'monthly') then
        raise exception 'finance_numbering_invalid_reset_period: document class % reset period % is not one of never/yearly/monthly', v_item.key, v_reset_period
          using errcode = 'check_violation';
      end if;

      if v_padding is null or v_padding < 1 or v_padding > 10 then
        raise exception 'finance_numbering_invalid_padding: document class % padding % must be between 1 and 10', v_item.key, v_padding
          using errcode = 'check_violation';
      end if;
    end loop;

  elsif p_config_type_code = 'finance_posting_map' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      if v_item.value ->> 'accountCodeRef' is null or not ((v_item.value ->> 'accountCodeRef') ~ '^[A-Z0-9._-]{1,20}$') then
        raise exception 'finance_posting_map_invalid_account_ref: posting map key % has no valid accountCodeRef (A-Z0-9._- up to 20 chars)', v_item.key
          using errcode = 'check_violation';
      end if;
      if v_item.value ->> 'accountCodeRef' = any (v_seen_codes) then
        null; -- multiple posting-map keys may legitimately target the same account; not a conflict
      end if;
      v_seen_codes := v_seen_codes || (v_item.value ->> 'accountCodeRef');
    end loop;

  elsif p_config_type_code = 'finance_rounding' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      v_mode := v_item.value ->> 'mode';
      v_precision := (v_item.value ->> 'precision')::integer;
      v_order := v_item.value ->> 'order';

      if not exists (select 1 from app.finance_rounding_modes where code = v_mode) then
        raise exception 'finance_rounding_invalid_mode: rounding class % mode % is not a registered rounding mode', v_item.key, v_mode
          using errcode = 'check_violation';
      end if;
      if v_precision is null or v_precision < 0 or v_precision > 6 then
        raise exception 'finance_rounding_invalid_precision: rounding class % precision % must be between 0 and 6', v_item.key, v_precision
          using errcode = 'check_violation';
      end if;
      if v_order is null or v_order not in ('convert_then_round', 'round_then_convert') then
        raise exception 'finance_rounding_invalid_order: rounding class % order % is not one of convert_then_round/round_then_convert', v_item.key, v_order
          using errcode = 'check_violation';
      end if;
    end loop;

  elsif p_config_type_code = 'finance_recognition' then
    if v_count <> 1 or not exists (select 1 from app.config_items where config_version_id = p_version_id and key = 'policy') then
      raise exception 'finance_recognition_shape: finance_recognition version % must carry exactly one item keyed ''policy''', p_version_id
        using errcode = 'check_violation';
    end if;
    select value into v_item from app.config_items where config_version_id = p_version_id and key = 'policy';
    if (v_item.value ->> 'budgetControlMode') not in ('none', 'advisory', 'hard_block') then
      raise exception 'finance_recognition_invalid_budget_control_mode: % is not one of none/advisory/hard_block', v_item.value ->> 'budgetControlMode'
        using errcode = 'check_violation';
    end if;
    if (v_item.value ->> 'accrualMethod') not in ('cash', 'accrual') then
      raise exception 'finance_recognition_invalid_accrual_method: % is not one of cash/accrual', v_item.value ->> 'accrualMethod'
        using errcode = 'check_violation';
    end if;
    if (v_item.value ->> 'revenueRecognitionMethod') not in ('invoice_date', 'delivery_date', 'milestone') then
      raise exception 'finance_recognition_invalid_revenue_method: % is not one of invoice_date/delivery_date/milestone', v_item.value ->> 'revenueRecognitionMethod'
        using errcode = 'check_violation';
    end if;
    if (v_item.value ->> 'costRecognitionMethod') not in ('invoice_date', 'incurred_date', 'milestone') then
      raise exception 'finance_recognition_invalid_cost_method: % is not one of invoice_date/incurred_date/milestone', v_item.value ->> 'costRecognitionMethod'
        using errcode = 'check_violation';
    end if;

  elsif p_config_type_code = 'finance_close_policy' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      if v_item.value ->> 'label' is null or length(trim(v_item.value ->> 'label')) = 0 then
        raise exception 'finance_close_policy_missing_label: close dependency % has no non-empty label', v_item.key
          using errcode = 'check_violation';
      end if;
      if jsonb_typeof(v_item.value -> 'required') is distinct from 'boolean' then
        raise exception 'finance_close_policy_invalid_required: close dependency % must declare a boolean required flag', v_item.key
          using errcode = 'check_violation';
      end if;
    end loop;

  else
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', p_config_type_code
      using errcode = 'check_violation';
  end if;

  return true;
end;
$$;

comment on function app.validate_finance_config_version is
  'FIN-191: per-class structural publish-time gate (bounded enums/format-token rules only -- no tax/legal content, RPD-016/021). Mirrors PLT-125''s own app.validate_numbering_definition token-checking logic for the finance_numbering class rather than calling that function directly, since it validates multiple per-document-class definitions within one version while PLT-125''s own function assumes a single flat definition at the version level -- a disclosed, deliberate parallel rule, not a silent fork of unrelated mechanics (see this migration''s own header).';

-- "Finance Admin drafts; configured approvers publish; Finance users read
-- effective policy" (Prompt 191 section 26) mapped onto the canonical, already-
-- registered FIN permission catalogue (PLT-111) -- no new permission-catalogue
-- row needed.
create function app.check_finance_config_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_config_authority is
  'FIN-191: FIN:Edit gates draft/set-items/discard; FIN:Approve gates publish/rollback; FIN:View gates resolve/read -- the canonical PLT-111 FIN permission catalogue, reused directly (no new permission-catalogue row).';

create function app.create_finance_config_draft(
  p_config_type_code text,
  p_tenant_id uuid,
  p_scope_level text,
  p_scope_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.config_versions
language plpgsql
as $$
begin
  if not app.is_finance_config_type(p_config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', p_config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.create_config_draft(p_config_type_code, p_tenant_id, p_scope_level, p_scope_id, p_actor_auth_user_id, p_created_by);
end;
$$;

create function app.set_finance_config_items(
  p_version_id uuid,
  p_items jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.set_config_items(p_version_id, p_items, p_actor_auth_user_id, p_actor_label);
end;
$$;

create function app.publish_finance_config_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.validate_finance_config_version(p_version_id, v_object.config_type_code);

  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

comment on function app.publish_finance_config_version is
  'FIN-191: FIN:Approve-gated publish, structurally validated per class before delegating to the generic engine''s own dependency-cycle-checked publish. FIN-192 extends this function (CREATE OR REPLACE) to add real account-existence checking for the finance_posting_map class once app.finance_accounts exists.';

create function app.discard_finance_config_draft(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.discard_config_draft(p_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$$;

create function app.rollback_finance_config_version(
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_target app.config_versions;
  v_object app.config_objects;
begin
  select * into v_target from app.config_versions where id = p_target_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_target.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.rollback_config_version(p_target_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$$;

-- Resolve-effective-policy (Prompt 191 section 14). Mirrors app.resolve_config's own
-- security posture exactly -- no in-function actor check, the calling layer
-- (Finance portal guard) is the real boundary, the same disclosed pattern every
-- other resolve_*/evaluate_* function in this repository already uses.
create function app.resolve_finance_config(
  p_config_type_code text,
  p_tenant_id uuid,
  p_company_id uuid default null,
  p_branch_id uuid default null,
  p_role_id uuid default null,
  p_user_id uuid default null
)
returns table (
  config_type_code text,
  resolved_scope_level text,
  resolved_version_id uuid,
  effective_from timestamptz,
  items jsonb
)
language plpgsql
stable
as $$
begin
  if not app.is_finance_config_type(p_config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', p_config_type_code
      using errcode = 'check_violation';
  end if;

  return query select * from app.resolve_config(p_config_type_code, p_tenant_id, p_company_id, p_branch_id, p_role_id, p_user_id);
end;
$$;

-- Draft-content read path (needed by the admin UX's own re-edit flow -- the generic
-- engine deliberately gives app.config_items no direct authenticated grant at all,
-- "draft content should never be casually browsable mid-edit," and app.resolve_config
-- only ever returns *published* items, so an admin re-opening an existing, not-yet-
-- published draft would otherwise have no way to see what is already saved before
-- overwriting it with app.set_finance_config_items' own full-replace semantics).
-- Gated identically to editing itself (FIN:Edit + tenant_admin/Supreme) -- the same
-- authority required to change a draft is required to see its current content.
create function app.get_finance_config_version_items(p_version_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Edit', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return coalesce(
    (select jsonb_object_agg(key, value) from app.config_items where config_version_id = p_version_id),
    '{}'::jsonb
  );
end;
$$;

comment on function app.get_finance_config_version_items is
  'FIN-191: the one read path for a not-yet-published draft''s own current item set -- gated identically to app.set_finance_config_items (FIN:Edit + tenant_admin/Supreme), since draft content is deliberately not exposed by the generic engine''s own app.resolve_config (published only).';

-- "Preview impact" (Prompt 191 section 14): runs the structural validator and, for
-- finance_posting_map only, discloses which account-code references are not yet
-- resolvable (no Chart of Accounts exists until FIN-192).
create function app.preview_finance_config_impact(p_version_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_valid boolean;
  v_error text;
  v_item_count integer;
  v_pending_refs jsonb;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;

  select count(*) into v_item_count from app.config_items where config_version_id = p_version_id;

  begin
    v_valid := app.validate_finance_config_version(p_version_id, v_object.config_type_code);
  exception
    when others then
      v_valid := false;
      v_error := sqlerrm;
  end;

  v_pending_refs := '[]'::jsonb;
  if v_object.config_type_code = 'finance_posting_map' then
    select coalesce(jsonb_agg(distinct value ->> 'accountCodeRef'), '[]'::jsonb)
    into v_pending_refs
    from app.config_items
    where config_version_id = p_version_id and value ->> 'accountCodeRef' is not null;
  end if;

  return jsonb_build_object(
    'configTypeCode', v_object.config_type_code,
    'valid', v_valid,
    'error', v_error,
    'itemCount', v_item_count,
    'pendingChartOfAccountsRefs', case when v_object.config_type_code = 'finance_posting_map' then v_pending_refs else null end
  );
end;
$$;

comment on function app.preview_finance_config_impact is
  'FIN-191: preview-impact operation. For finance_posting_map, pendingChartOfAccountsRefs lists every referenced account code that cannot yet be existence-checked (FIN-192 has not run in this dependency order) -- disclosed, never silently claimed resolved.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.finance_rounding_modes enable row level security;

-- Platform-owned reference data (mirrors app.config_types'/app.finance_config_class
-- equivalents' own posture) -- safe to expose broadly.
create policy finance_rounding_modes_select_authenticated on app.finance_rounding_modes
  for select to authenticated
  using (true);

grant select on app.finance_rounding_modes to authenticated, service_role;
grant insert, update, delete on app.finance_rounding_modes to service_role;
grant execute on function app.is_finance_config_type(text) to authenticated, service_role;
grant execute on function app.validate_finance_config_version(uuid, text) to service_role;
grant execute on function app.check_finance_config_authority(text, uuid, uuid) to service_role;
grant execute on function app.create_finance_config_draft(text, uuid, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.set_finance_config_items(uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.publish_finance_config_version(uuid, uuid, timestamptz, text) to authenticated, service_role;
grant execute on function app.discard_finance_config_draft(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.rollback_finance_config_version(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.resolve_finance_config(text, uuid, uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.preview_finance_config_impact(uuid) to authenticated, service_role;
grant execute on function app.get_finance_config_version_items(uuid, uuid) to authenticated, service_role;
