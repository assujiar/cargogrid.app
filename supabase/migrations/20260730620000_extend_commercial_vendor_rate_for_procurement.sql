-- Procurement capability PRC-255 (Vendor Rate and Pricelist, CG-S11-PRC-006).
-- Extends the already-VERIFIED Phase 2 canonical vendor-rate engine
-- (supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql, COM-149,
-- ADR-0015) with Phase 6's own required capability: the ADR-0020-mandated vendor-identity
-- link, multi-tier weight/volume pricing, cross-version overlap detection, lead-time/
-- capacity terms, an exact reproducible calculate/lookup RPC, and the FIRST real domain
-- write adapter for the generic Import/Export Job Framework (PLT-131, ISS-2026-013).
-- NEVER edits 20260724150000 (or any other applied migration) -- every change here is a
-- new, additive migration: new nullable columns, a new child table, new functions, and
-- `create or replace function` on a handful of COM-149's own functions, always on a
-- backward-compatible signature (existing callers that omit the new trailing optional
-- parameters are unaffected).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **ADR-0020 vendor identity link (mandatory, minimal).** `app.vendor_rate_versions`
--    gains `vendor_master_id uuid references app.master_records(id)`, nullable,
--    structurally enforced (trigger, mirrors PRC-251's own `enforce_vendor_profile_
--    identity`) to reference a same-tenant `master_type_code='vendor'` row when
--    supplied. `master_record_id` (the `vendor_rate`-typed identity COM-149 already
--    owns) is untouched. `app.create_rate_version` gets ONE new optional trailing
--    parameter, `p_vendor_master_id` -- on a supersede (revision) call, an
--    unsupplied value defaults to the SOURCE row's own `vendor_master_id` (identity
--    continuity, mirroring how `master_record_id` itself is inherited on supersede)
--    rather than being silently dropped; an explicit value always overrides. Every
--    other business field on a revision (base_amount, currency, lanes, ...) is NEVER
--    auto-inherited, matching COM-149's own existing convention exactly -- only
--    identity-shaped fields inherit by default.
-- 2. **Multi-tier pricing is a genuinely new, additive child table,
--    `app.vendor_rate_tiers`.** Zero tiers stays a fully valid, unchanged shape (the
--    existing flat `cargo_weight_min/max`/`base_amount` single-tier default every
--    COM-149 db-test fixture already relies on) -- tiers are an opt-in capability, not
--    a forced migration of any existing rate shape. Tier rows may only be created
--    while the parent rate_version is `pending_approval` (mirrors PRC-252/253's own
--    "child rows only while parent is in an editable pre-published state"
--    convention) -- publishing a rate freezes its tier structure.
-- 3. **Tier boundary rule (this migration's own explicit, documented decision, Prompt
--    255 §13/§25 "ordered non-overlapping tiers"): half-open `[min, max)` intervals,
--    weight and volume validated as two INDEPENDENT 1-D partitions of the SAME tier
--    set, EACH ONLY WHEN THAT DIMENSION ACTUALLY VARIES** (not a combined 2-D box
--    match at validation time) -- i.e. sorting a rate version's tiers by
--    `weight_min` must itself yield a contiguous, non-overlapping staircase (each
--    tier's `weight_max` exactly equal to the next tier's `weight_min`; at most one
--    tier may carry a null/unbounded `weight_max`, and only as the last one), and
--    separately, sorting the SAME tiers by `volume_min` must independently satisfy
--    the identical contiguity rule -- but a dimension every tier shares the
--    identical `(min, max)` range on (`count(distinct (min, max)) <= 1`) is exempt
--    from that dimension's own check entirely, since it is by definition not the
--    dimension this rate's tiers vary by. This exemption is load-bearing, not
--    cosmetic: a live run of this migration's own db-test suite caught the
--    UNEXEMPTED first draft rejecting the single most common real shape (tiers
--    that vary by weight only, every tier sharing the same default `[0, null)`
--    volume range) as a false-positive "unbounded tier must be last" volume
--    violation -- fixed here, not silently left in place. In practice this means a
--    rate version's tiers are one single ordered ladder along whichever
--    dimension(s) actually vary (the common real-world shape: tiers vary by weight
--    OR by volume, not an arbitrary 2-D grid) -- a genuinely ambiguous 2-D grid
--    shape (tiers varying independently along BOTH dimensions at once) is out of
--    this checkpoint's own scope, disclosed here rather than silently
--    mis-validated. Validated once, at `app.approve_rate_version` time (publish),
--    never on every `app.add_vendor_rate_tier` call -- PRC-252's own "validate at
--    publish, not at every edit" precedent, applied here a second time.
-- 4. **Overlap detection across rate versions at the same scope (Prompt 255 §23
--    "block ambiguous overlap") is a REAL, DB-enforced constraint, not an
--    app-level check-then-insert.** Two new generated, stored columns --
--    `scope_key text` (`coalesce(vendor_master_id, 'legacy:'||master_record_id) |
--    tenant_id | service_type | mode | origin_lane | destination_lane |
--    equipment_type`) and `validity_range tstzrange` (`[effective_from,
--    effective_to)`, unbounded above when `effective_to` is null) -- back a
--    `btree_gist` `EXCLUDE` constraint, `vendor_rate_versions_no_ambiguous_overlap`,
--    scoped to `approval_status='approved'` rows only. PostgreSQL enforces this at
--    the index level on every INSERT/UPDATE that would produce two approved rows in
--    the identical scope with overlapping validity windows -- inherently
--    concurrency-safe (the same guarantee a unique index gives, stronger than an
--    advisory lock + a separate SELECT-then-INSERT check, and impossible to bypass
--    via a code path this migration did not anticipate). `app.approve_rate_version`
--    catches the raw `exclusion_violation` (sqlstate 23P01) and re-raises it as the
--    same clear, named `ambiguous_overlap` error class every other validation
--    failure in this repository uses.
-- 5. **Data-migration disclosure (Prompt 255 §19):** COM-149's own db-test fixture
--    (`scripts/db-tests/commercial-rate-cost-lookup.sql`) was read in full before
--    writing this constraint. It creates exactly one revision-supersede sequence for
--    the Jakarta/Surabaya/FCL scope -- the SOURCE row is marked `superseded`
--    (leaving the exclusion-constraint scope) BEFORE the REVISION is ever approved,
--    so no two rows are ever simultaneously `approved` in that scope; the file's own
--    "OTHER-TENANT-VENDOR" fixture shares the identical lane/service/mode but is a
--    different tenant (`scope_key` includes `tenant_id`), and no other approved
--    row anywhere in that file shares a scope with another approved row. Zero
--    existing db-test fixture creates a genuine ambiguous overlap; the constraint is
--    added with no fixture adjustment required, confirmed by direct inspection, not
--    assumed.
-- 6. **Lead time / capacity terms** (`lead_time_days integer`, `capacity_terms text`)
--    are two new nullable columns on `app.vendor_rate_versions` -- free-form
--    commercial terms mirroring `surcharge_components`'s own established
--    "commercial term that does not need to be queried/filtered" convention (a
--    structured jsonb shape was considered and rejected: neither field needs
--    component-level querying the way `surcharge_components` does). Cost-sensitivity
--    tier: masked identically to `base_amount`/`surcharge_components` (same
--    `app.has_view_cost` gate) -- capacity/lead-time terms are commercially
--    sensitive, negotiated-with-a-specific-vendor information, not public
--    operational metadata like `service_type`/lane names.
-- 7. **Exact calculate/lookup API (Prompt 255 §18, RPD-040).** The actual
--    computation lives in one private, ungated helper,
--    `app._compute_vendor_rate_amount` (no grant to `authenticated`/`service_role`,
--    callable only from within another function owned by the same role -- PRC-254's
--    own established private-helper convention, applied here a second time to avoid
--    two independent reimplementations of "match a tier, sum surcharges, apply the
--    minimum, round"). `app.calculate_vendor_rate` (public, read-only, `stable`,
--    gated on `PRC:View cost`, ADR-0020's own directed reuse for this checkpoint's
--    new sensitive-field class -- see design note 2's `app.has_prc_view_cost`) is
--    the read/preview entry point;
--    `app.select_vendor_rate` (COM-149, widened here with three new optional
--    trailing parameters `p_weight`/`p_volume`/`p_quantity`) calls the SAME private
--    helper to snapshot the exact tier-matched calculation into
--    `app.rate_selections.snapshot` when those inputs are supplied -- omitting them
--    (every existing caller) reproduces COM-149's original flat `base_amount`
--    behavior byte-for-byte, unchanged. Rounding is ALWAYS `app.apply_finance_
--    rounding(..., 2, 'round_half_up')` (FIN-194) -- never reimplemented.
-- 8. **The import adapter is the first real domain-write adapter for PLT-131**
--    (`supabase/migrations/20260719170000_create_import_export_job_framework.sql`),
--    confirmed by direct repository inspection to be the first ever caller of
--    `app.register_import_export_schema`'s own registered-schema convention. A new
--    schema code, `'vendor_rate_import'`, is registered directly (a structural,
--    tenant-independent registry row -- INSERTed directly into `app.import_export_
--    schemas`/`app.config_types`, the same direct-INSERT convention `app.master_
--    types`' own seed rows use, since `app.register_import_export_schema`/`app.
--    register_config_type` both gate on `app.is_supreme_admin(actor)` and a
--    migration-apply context has no live actor session). Each tenant still
--    separately configures and PUBLISHES its own `import_export:vendor_rate_import`
--    column definition via the existing, generic Configuration Engine
--    (`app.create_config_draft`/`app.set_config_items`/`app.publish_import_export_
--    schema`) before it can create a job against this schema code -- this migration
--    does not publish a tenant-scoped default (there is no tenant to publish one
--    for, and PLT-131's own `app.resolve_import_export_schema_columns` has no
--    platform-level fallback branch to lean on even if there were).
-- 9. **Column-mapping convention (disclosed, "repeated column groups"): one staged
--    row = one full rate proposal, with up to THREE fixed tier slots as flat
--    columns** (`tier1_..`/`tier2_..`/`tier3_..`), never the alternative "one row
--    per tier, grouped across rows" shape. A tier slot is considered present only
--    if its own `tierN_amount` column is non-empty; `weight_min`/`volume_min`
--    default to 0 when omitted, mirroring `app.add_vendor_rate_tier`'s own
--    coalesce behavior. A rate needing more than three tiers is created via the
--    structured API/UI directly, not bulk import -- a disclosed, bounded
--    simplification chosen because the alternative (cross-row grouping into one
--    rate + N tiers, with partial-group-failure semantics) is materially more
--    complex to implement and verify correctly within this checkpoint, and no
--    source requirement mandates unbounded tier counts specifically via import.
--    Full column list: `vendor_code`/`vendor_name` (text, required -- COM-149's own
--    `vendor_rate` identity), `vendor_master_code` (text, optional -- resolves
--    against a real `master_type_code='vendor'` row, item 1 above),
--    `service_type`/`origin_lane`/`destination_lane`/`currency` (text, required),
--    `mode`/`equipment_type`/`capacity_terms` (text, optional), `base_amount`
--    (number, required), `minimum_amount`/`lead_time_days` (number, optional), and
--    per slot N in 1..3: `tierN_weight_min`/`tierN_weight_max`/`tierN_volume_min`/
--    `tierN_volume_max`/`tierN_amount`/`tierN_minimum_charge` (number, optional).
-- 10. **Formula/spreadsheet-injection defense (Prompt 255 §16) rejects, never
--     silently strips.** `app.validate_vendor_rate_import_row` first calls `app.
--     validate_staging_row` UNCHANGED (the generic structural pass, reused exactly,
--     never reimplemented) and, only if still `valid`, applies a SECOND,
--     domain-specific pass: any of the ten text-shaped columns above whose value
--     begins with `=`, `+`, `-`, `@`, a tab, or a carriage return is rejected --
--     the row is marked `invalid` with a clear, named reason (never silently
--     sanitized/stripped, and never the generic PLT-131 `app.sanitize_formula_
--     injection` helper, which MUTATES a value for safe EXPORT-time cell writing,
--     a genuinely different, already-disclosed use case per that migration's own
--     header) -- plus a currency-format check and a `vendor_master_code`
--     existence check, the two cross-table domain checks the generic structural
--     validator cannot perform on its own.
-- 11. **The commit adapter, `app.commit_vendor_rate_import_job`, requires BOTH the
--     unchanged COM-149 authority `app.is_support_grant_authority` (tenant_admin/
--     Supreme -- since it ultimately calls `app.create_rate_version`, which this
--     migration does not widen the authority model of, per ADR-0020's own
--     Consequences) AND the new `PRC:Import` action.** `PRC:Import` alone is never
--     sufficient to bulk-create commercial rate data a direct `app.create_rate_
--     version` call would refuse the same actor -- disclosed here as a deliberate
--     choice to avoid a privilege-escalation path, not an oversight. Idempotent-safe
--     by construction: a new nullable, uniquely-indexed `source_import_staging_
--     row_id` column on `app.vendor_rate_versions` means a staged row can ever
--     produce at most one rate version, ever, defended both by a pre-check
--     (`not exists`, avoiding wasted work) and a nested `unique_violation`
--     race-recovery handler (pattern 4) around the actual INSERT, plus a
--     job-scoped `pg_advisory_xact_lock` (pattern 3, scoped to the job id itself --
--     the correct, actually-contended resource for "two concurrent commit calls on
--     the SAME job," resolved and locked before any row is read, mirroring PRC-254's
--     own corrected lock-on-the-real-contended-resource lesson). Tier rows for an
--     imported rate are inserted via the SAME private `app._insert_vendor_rate_tier`
--     helper `app.add_vendor_rate_tier` itself calls (factored out for exactly this
--     reason: the adapter is already fully authorized by its own two gates above and
--     must not additionally require every import-actor to separately hold
--     `PRC:Edit` just to import tiered rows).
-- 12. **Vendor-active check at approval, never at draft/create time** (Prompt 255's
--     own instruction): `app.approve_rate_version` (widened) rejects if `vendor_
--     master_id` is linked and the referenced `app.vendor_profiles.lifecycle_status`
--     is not exactly `'active'` -- a suspended/archived/blacklisted/unregistered
--     vendor can never have a rate published. `app.vendor_profiles.lifecycle_status`
--     itself is never written by this migration (read-only check, Prompt 255's own
--     explicit "what not to build" boundary).
-- 13. **`for update` added to `app.approve_rate_version`'s own initial SELECT**
--     (COM-149's original was a plain, unlocked SELECT, safe on its own via the
--     existing record_version optimistic-concurrency compare-and-swap, but never
--     covering a race against a NEW cross-table child, `app.vendor_rate_tiers`, this
--     migration adds). `app.add_vendor_rate_tier`/`app.remove_vendor_rate_tier`
--     both lock the SAME parent row (via `app.assert_vendor_rate_version_tier_
--     editable`) before touching a tier -- the two sides now serialize naturally on
--     one shared row lock, closing "a tier being added while the parent rate is
--     concurrently approved" (pattern 3's own named race).
-- 14. **Customer exposure prevention (Prompt 255 §16/§26, requirement 6): extends
--     COM-149's own masking view rather than building a second mechanism.**
--     `app.vendor_rate_versions_directory` is recreated (`create or replace view`,
--     purely additive trailing columns for `vendor_master_id`/`lead_time_days`/
--     `capacity_terms`, cost-masked identically to `base_amount`) with its row
--     filter ALSO hardened from the start to the exact pattern-5 predicate this
--     migration's own new table uses (`has_active_tenant_membership(...) and not
--     actor_holds_customer_user_layer(...)`) -- a pure AND-narrowing (mirrors
--     `20260730311000`'s own ATW-023-hardening technique byte-for-byte), so a
--     `customer_user`-layer principal now gets ZERO rows from this view (stronger
--     than the pre-existing cost-masking alone already provided). `app.v_active_
--     vendor_rates` (`select * from vendor_rate_versions_directory ...`) inherits
--     both the new columns and the hardened predicate automatically, with no
--     changes of its own required. `app.vendor_rate_tiers_directory` (new) uses the
--     identical hardened predicate from the start (pattern 5).
-- 15. RBAC reuses the 12 already-seeded PRC actions exclusively (View/Create/Edit/
--     Delete/Approve/Reject/Export/Override/Download/Import/View cost/View personal
--     data) -- no new `app.permissions` row is seeded by this migration. Mapping:
--     `Edit` = add/remove a tier (mirrors PRC-254's "child CRUD = Edit"); `View` =
--     `app.calculate_vendor_rate`; `Import` = the bulk commit adapter (design
--     note 11). `app.create_rate_version`/`app.approve_rate_version` themselves keep
--     COM-149's own unchanged `app.is_support_grant_authority` gate -- ADR-0020's
--     own Consequences are explicit that this migration does not widen that
--     authority model, only that table's data shape.
-- 16. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.
-- 17. True multi-session concurrent-race reproduction has no matching sequential
--     db-test proof (no `dblink`/`pg_background` in this test suite) -- the same
--     standing, already-disclosed limitation every prior Phase 6 checkpoint's build
--     log records. Verified instead by direct conformance to this repository's own
--     established locking patterns (the `EXCLUDE` constraint for overlap is
--     inherently concurrency-safe regardless; the advisory locks are verified by
--     code-path inspection) plus the full sequential suite passing unchanged.
-- 18. **Post-review fixes (four, applied after independent adversarial review of
--     this file's own first draft; each marked "BUG FIX (post-review, <severity>)"
--     at its exact location):**
--     (a) SECURITY, HIGH -- `app.select_vendor_rate`'s three new trailing
--         parameters let a caller holding only COM:View cost (no PRC permission
--         at all) retrieve the same sensitive tier cost breakdown
--         `app.calculate_vendor_rate`/`app.vendor_rate_tiers_directory` correctly
--         restrict to PRC:View cost -- live-reproducible with a real
--         COM-only-permissioned actor's own genuine identity, no forged JWT
--         needed. Fixed: PRC:View cost is now additionally required, but ONLY on
--         the branch where p_weight/p_volume/p_quantity is supplied -- every
--         pre-PRC-255 (COM-149) caller (all three null) is completely
--         unaffected.
--     (b) CORRECTNESS, CRITICAL -- `app.commit_vendor_rate_import_job`'s per-row
--         `unique_violation` handler caught ANY unique_violation, misclassifying
--         a genuine `vendor_code` collision (bubbling up from
--         `app.create_master_record`'s own unlocked check-then-insert, also
--         sqlstate unique_violation) as "already committed, skip" -- silently
--         dropping a row with the job still reporting full success and no
--         recoverable retry path. Fixed: `get stacked diagnostics constraint_name`
--         now distinguishes this adapter's own idempotency guard
--         (`vendor_rate_versions_source_import_row_unique`, the only case that
--         means "safe replay, skip") from any other unique_violation, which now
--         re-raises and aborts the transaction instead of silently continuing.
--     (c) CORRECTNESS, HIGH -- `app.create_rate_version`'s own supersede-marking
--         initial SELECT was unlocked and its terminal UPDATE had no
--         status-scoped WHERE / post-UPDATE "if not found" re-check (unlike
--         `app.approve_rate_version`'s own terminal UPDATE a few dozen lines
--         later in this SAME file) -- two concurrent revisions of the same
--         source row could both succeed, leaving two sibling pending_approval
--         revisions both claiming the same `supersedes_version_id` and
--         double-incrementing the source's `record_version`. Fixed: `for update`
--         on the initial read (serializes a second concurrent caller behind the
--         first, which then re-reads the post-commit, already-superseded row and
--         correctly hits `invalid_transition`) plus a status-scoped WHERE and
--         "if not found" re-check on the terminal UPDATE (defense in depth).
--     (d) CORRECTNESS, MEDIUM -- `app.approve_rate_version`'s exclusion-violation
--         handler caught only `exclusion_violation` (23P01); a GiST EXCLUDE
--         constraint under real concurrent contention can also surface as a raw
--         `deadlock_detected` (40P01, a documented PostgreSQL GiST-index
--         characteristic, live-reproduced across repeated trials) -- roughly half
--         of genuinely-conflicting concurrent approvals leaked an untranslated
--         "deadlock detected" error instead of the documented `ambiguous_overlap`
--         class. Fixed: `deadlock_detected` now translates identically, since
--         both sqlstates arise from the same underlying business conflict.

create extension if not exists btree_gist;

-- ===========================================================================
-- 1. ADR-0020 vendor identity link + lead time/capacity terms + import-adapter
--    lineage column + overlap-detection generated columns (design notes 1, 4, 6, 11).
-- ===========================================================================

alter table app.vendor_rate_versions add column vendor_master_id uuid references app.master_records (id);
alter table app.vendor_rate_versions add column lead_time_days integer;
alter table app.vendor_rate_versions add column capacity_terms text;
alter table app.vendor_rate_versions add column source_import_staging_row_id uuid references app.import_staging_rows (id);

alter table app.vendor_rate_versions add constraint vendor_rate_versions_lead_time_check check (lead_time_days is null or lead_time_days >= 0);

create index vendor_rate_versions_vendor_master_id_idx on app.vendor_rate_versions (vendor_master_id);
create unique index vendor_rate_versions_source_import_row_unique on app.vendor_rate_versions (source_import_staging_row_id) where source_import_staging_row_id is not null;

comment on column app.vendor_rate_versions.vendor_master_id is 'PRC-255 (ADR-0020): optional link to the real canonical vendor identity (app.vendor_profiles, master_type_code=''vendor''), distinct from master_record_id (the vendor_rate-typed identity row, unchanged). Nullable -- existing/ad-hoc/legacy rate rows with no linked Procurement vendor remain valid (Prompt 255 §22).';
comment on column app.vendor_rate_versions.source_import_staging_row_id is 'PRC-255: set only by app.commit_vendor_rate_import_job -- the staging row that produced this rate version, uniquely indexed so a staged row can ever produce at most one rate version (idempotent-safe commit replay).';

-- Structural enforcement (defense in depth alongside app.create_rate_version's own
-- explicit check) -- mirrors app.enforce_vendor_profile_identity (PRC-251) exactly.
create function app.enforce_vendor_rate_version_vendor_identity()
returns trigger
language plpgsql
as $$
declare
  v_master app.master_records;
begin
  if new.vendor_master_id is null then
    return new;
  end if;
  select * into v_master from app.master_records where id = new.vendor_master_id;
  if not found then
    raise exception 'vendor_master_record_not_found: no master record %', new.vendor_master_id using errcode = 'foreign_key_violation';
  end if;
  if v_master.master_type_code <> 'vendor' then
    raise exception 'invalid_vendor_identity: master record % is master_type_code %, expected vendor', new.vendor_master_id, v_master.master_type_code
      using errcode = 'check_violation';
  end if;
  if v_master.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_vendor_identity: master record % belongs to tenant %, not %', new.vendor_master_id, v_master.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger vendor_rate_versions_enforce_vendor_identity
  before insert or update of vendor_master_id, tenant_id on app.vendor_rate_versions
  for each row
  execute function app.enforce_vendor_rate_version_vendor_identity();

-- Overlap-detection generated columns + EXCLUDE constraint (design notes 4, 5).
alter table app.vendor_rate_versions add column scope_key text generated always as (
  coalesce(vendor_master_id::text, 'legacy:' || master_record_id::text) || '|' || tenant_id::text || '|' ||
  service_type || '|' || coalesce(mode, '') || '|' || origin_lane || '|' || destination_lane || '|' || coalesce(equipment_type, '')
) stored;

alter table app.vendor_rate_versions add column validity_range tstzrange generated always as (
  tstzrange(effective_from, effective_to, '[)')
) stored;

alter table app.vendor_rate_versions
  add constraint vendor_rate_versions_no_ambiguous_overlap
  exclude using gist (scope_key with =, validity_range with &&)
  where (approval_status = 'approved');

comment on constraint vendor_rate_versions_no_ambiguous_overlap on app.vendor_rate_versions is 'PRC-255 design note 4: a real, DB-enforced, concurrency-safe guard against two APPROVED rate versions existing at the identical (vendor identity, tenant, service_type, mode, origin_lane, destination_lane, equipment_type) scope with an overlapping [effective_from, effective_to) validity window. app.approve_rate_version translates the raw exclusion_violation into a clear ambiguous_overlap error.';

-- ===========================================================================
-- 2. app.vendor_rate_tiers (design notes 2, 3, 14) + the PRC:View cost masking
--    gate ADR-0020 directs this checkpoint to reuse for its own NEW sensitive-field
--    class. `app.has_prc_view_cost` ALREADY EXISTS -- PRC-252 (Vendor Assessment,
--    `20260730590000_create_procurement_vendor_assessment.sql`) created it first,
--    the exact same shape this checkpoint would otherwise duplicate (confirmed by
--    direct repository inspection before writing this section -- never redefined
--    here). The pre-existing COM-149 columns (base_amount, currency,
--    minimum_amount, surcharge_components, and the two new trailing columns living
--    on that SAME table/view, lead_time_days/capacity_terms) keep the UNCHANGED
--    `app.has_view_cost` (COM:View cost) gate -- extending that existing
--    mechanism, never building a second one, per requirement 6's own explicit
--    instruction. `app.vendor_rate_tiers` is a wholly new table/sensitive-field
--    class this checkpoint introduces, so it reuses PRC-252's own
--    `app.has_prc_view_cost` from the start, exactly as ADR-0020 directs
--    ("Prompt 255 reuses the already-seeded, already-protected PRC:View cost").
-- ===========================================================================

create table app.vendor_rate_tiers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rate_version_id uuid not null references app.vendor_rate_versions (id),
  tier_order integer not null,
  weight_min numeric(14, 3) not null default 0,
  weight_max numeric(14, 3),
  volume_min numeric(14, 3) not null default 0,
  volume_max numeric(14, 3),
  amount numeric(14, 2) not null,
  minimum_charge numeric(14, 2),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_rate_tiers_tier_order_check check (tier_order > 0),
  constraint vendor_rate_tiers_weight_nonneg_check check (weight_min >= 0),
  constraint vendor_rate_tiers_volume_nonneg_check check (volume_min >= 0),
  constraint vendor_rate_tiers_weight_range_check check (weight_max is null or weight_max > weight_min),
  constraint vendor_rate_tiers_volume_range_check check (volume_max is null or volume_max > volume_min),
  constraint vendor_rate_tiers_amount_check check (amount >= 0),
  constraint vendor_rate_tiers_minimum_charge_check check (minimum_charge is null or minimum_charge >= 0),
  constraint vendor_rate_tiers_unique_order unique (rate_version_id, tier_order)
);

comment on table app.vendor_rate_tiers is 'PRC-255: an ordered, [min,max)-half-open weight/volume pricing tier belonging to one app.vendor_rate_versions row. May only be created/removed while the parent is pending_approval (mirrors PRC-252/253''s own "child rows only while parent is editable" convention). Zero tiers is a fully valid rate (the parent''s own flat cargo_weight_min/max + base_amount is the single-tier/no-tier default, unchanged from COM-149). Contiguity/non-overlap is validated once, at app.approve_rate_version time -- see this migration''s own header design note 3 for the exact boundary rule.';

create index vendor_rate_tiers_rate_version_idx on app.vendor_rate_tiers (rate_version_id, tier_order);
create unique index vendor_rate_tiers_idempotency_key_unique on app.vendor_rate_tiers (tenant_id, idempotency_key) where idempotency_key is not null;

create view app.vendor_rate_tiers_directory
as
select
  t.id,
  t.tenant_id,
  t.rate_version_id,
  t.tier_order,
  t.weight_min,
  t.weight_max,
  t.volume_min,
  t.volume_max,
  case when app.has_prc_view_cost(t.tenant_id) then t.amount else null end as amount,
  case when app.has_prc_view_cost(t.tenant_id) then t.minimum_charge else null end as minimum_charge,
  not app.has_prc_view_cost(t.tenant_id) as cost_masked,
  t.record_version,
  t.created_by,
  t.created_at,
  t.updated_at
from app.vendor_rate_tiers t
where (app.has_active_tenant_membership(t.tenant_id) and not app.actor_holds_customer_user_layer(t.tenant_id)) or app.is_supreme_admin();

comment on view app.vendor_rate_tiers_directory is 'PRC-255: field-masked projection of app.vendor_rate_tiers -- amount/minimum_charge nulled (cost_masked=true) for a caller lacking PRC:View cost (ADR-0020''s own directed gate for this checkpoint''s new sensitive-field class -- see design note above app.has_prc_view_cost). Row-visibility uses the hardened pattern-5 predicate from creation (a customer_user-layer principal gets zero rows, not merely masked ones).';

-- ===========================================================================
-- 3. Tier editable-precondition helper + private insert helper + public RPCs
--    (design notes 2, 3, 11, 13).
-- ===========================================================================

create function app.assert_vendor_rate_version_tier_editable(p_rate_version_id uuid, p_actor_auth_user_id uuid, out v_rate app.vendor_rate_versions)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id for update;
  if not found then
    raise exception 'vendor_rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rate.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'vendor_rate_version_not_editable: rate version % is % -- tiers may only be added/removed while pending_approval', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;
end;
$$;

-- Private, ungated "insert a validated tier row" primitive (no grant to
-- authenticated/service_role -- PRC-254's own established private-helper
-- convention). Shared by app.add_vendor_rate_tier (actor-gated) and
-- app.commit_vendor_rate_import_job (already fully authorized by its own two gates,
-- design note 11) so neither duplicates the validation/idempotency logic nor forces
-- an import actor to separately hold PRC:Edit.
create function app._insert_vendor_rate_tier(
  p_rate app.vendor_rate_versions,
  p_tier_order integer,
  p_weight_min numeric,
  p_weight_max numeric,
  p_volume_min numeric,
  p_volume_max numeric,
  p_amount numeric,
  p_minimum_charge numeric,
  p_idempotency_key text,
  p_actor_label text
)
returns app.vendor_rate_tiers
language plpgsql
as $$
declare
  v_existing app.vendor_rate_tiers;
  v_tier app.vendor_rate_tiers;
  v_constraint_name text;
  v_weight_min numeric := coalesce(p_weight_min, 0);
  v_volume_min numeric := coalesce(p_volume_min, 0);
begin
  if p_rate.approval_status <> 'pending_approval' then
    raise exception 'vendor_rate_version_not_editable: rate version % is % -- tiers may only be added while pending_approval', p_rate.id, p_rate.approval_status
      using errcode = 'check_violation';
  end if;
  if p_tier_order is null or p_tier_order <= 0 then
    raise exception 'invalid_tier_order: tier_order must be a positive integer' using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'invalid_tier_amount: amount must be a non-negative value' using errcode = 'check_violation';
  end if;
  if v_weight_min < 0 or v_volume_min < 0 then
    raise exception 'invalid_tier_range: weight_min/volume_min must be non-negative' using errcode = 'check_violation';
  end if;
  if p_weight_max is not null and p_weight_max <= v_weight_min then
    raise exception 'invalid_tier_weight_range: weight_max must exceed weight_min' using errcode = 'check_violation';
  end if;
  if p_volume_max is not null and p_volume_max <= v_volume_min then
    raise exception 'invalid_tier_volume_range: volume_max must exceed volume_min' using errcode = 'check_violation';
  end if;
  if p_minimum_charge is not null and p_minimum_charge < 0 then
    raise exception 'invalid_tier_minimum_charge: minimum_charge must be non-negative' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_rate_tiers where tenant_id = p_rate.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.rate_version_id is distinct from p_rate.id or v_existing.tier_order is distinct from p_tier_order
        or v_existing.weight_min is distinct from v_weight_min or v_existing.weight_max is distinct from p_weight_max
        or v_existing.volume_min is distinct from v_volume_min or v_existing.volume_max is distinct from p_volume_max
        or v_existing.amount is distinct from p_amount or v_existing.minimum_charge is distinct from p_minimum_charge
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different tier proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_rate_tiers (
      tenant_id, rate_version_id, tier_order, weight_min, weight_max, volume_min, volume_max, amount, minimum_charge, idempotency_key, created_by
    ) values (
      p_rate.tenant_id, p_rate.id, p_tier_order, v_weight_min, p_weight_max, v_volume_min, p_volume_max, p_amount, p_minimum_charge, p_idempotency_key, p_actor_label
    )
    returning * into v_tier;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_rate_tiers_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_rate_tiers where tenant_id = p_rate.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.rate_version_id is distinct from p_rate.id or v_existing.tier_order is distinct from p_tier_order
            or v_existing.weight_min is distinct from v_weight_min or v_existing.weight_max is distinct from p_weight_max
            or v_existing.volume_min is distinct from v_volume_min or v_existing.volume_max is distinct from p_volume_max
            or v_existing.amount is distinct from p_amount or v_existing.minimum_charge is distinct from p_minimum_charge
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different tier proposal', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise exception 'duplicate_tier_order: rate version % already has a tier at tier_order %', p_rate.id, p_tier_order
        using errcode = 'unique_violation';
  end;

  return v_tier;
end;
$$;

create function app.add_vendor_rate_tier(
  p_rate_version_id uuid,
  p_tier_order integer,
  p_weight_min numeric,
  p_weight_max numeric,
  p_volume_min numeric,
  p_volume_max numeric,
  p_amount numeric,
  p_minimum_charge numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_tiers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_tier app.vendor_rate_tiers;
begin
  v_rate := app.assert_vendor_rate_version_tier_editable(p_rate_version_id, p_actor_auth_user_id);

  v_tier := app._insert_vendor_rate_tier(v_rate, p_tier_order, p_weight_min, p_weight_max, p_volume_min, p_volume_max, p_amount, p_minimum_charge, p_idempotency_key, p_actor_label);

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_rate_tier',
    'app.vendor_rate_tiers', v_tier.id, 'success', null, null, to_jsonb(v_tier)
  );

  return v_tier;
end;
$$;

comment on function app.add_vendor_rate_tier is 'PRC-255: PRC:Edit-gated (mirrors PRC-254''s own "child CRUD = Edit" mapping). Only while the parent rate version is pending_approval. Idempotency-key replay compares every load-bearing field (rate_version_id, tier_order, weight_min/max, volume_min/max, amount, minimum_charge).';

create function app.remove_vendor_rate_tier(
  p_tier_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_tier app.vendor_rate_tiers;
  v_rate app.vendor_rate_versions;
begin
  select * into v_tier from app.vendor_rate_tiers where id = p_tier_id for update;
  if not found then
    raise exception 'vendor_rate_tier_not_found: %', p_tier_id using errcode = 'no_data_found';
  end if;

  v_rate := app.assert_vendor_rate_version_tier_editable(v_tier.rate_version_id, p_actor_auth_user_id);

  if v_tier.record_version <> p_expected_version then
    raise exception 'stale_version: vendor rate tier % expected version % but found %', p_tier_id, p_expected_version, v_tier.record_version
      using errcode = 'serialization_failure';
  end if;

  delete from app.vendor_rate_tiers where id = p_tier_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor rate tier % target row was concurrently modified (expected version %)', p_tier_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_rate_tier',
    'app.vendor_rate_tiers', p_tier_id, 'success', null, to_jsonb(v_tier), null
  );
end;
$$;

-- Tier contiguity/non-overlap validator (design note 3). Called only at
-- app.approve_rate_version time. Zero or one tier is trivially valid.
create function app._validate_vendor_rate_tiers_contiguous(p_rate_version_id uuid)
returns void
language plpgsql
as $$
declare
  v_tier record;
  v_prev_max numeric;
  v_first boolean;
  v_distinct_weight_ranges integer;
  v_distinct_volume_ranges integer;
begin
  -- live bug fix (found running this migration's own db-test suite): the ORIGINAL
  -- version of this function unconditionally validated BOTH dimensions against
  -- EVERY tier, which made the common, intended "tiers vary by weight only" shape
  -- unrepresentable -- every tier sharing the same default [0, null) volume range
  -- was flagged as an ambiguous "unbounded tier must be last" volume violation,
  -- even though no tier ever actually varies by volume. A dimension is only
  -- validated for contiguity/overlap when the tier set's own values for that
  -- dimension are not all identical (count(distinct (min,max)) > 1) -- a dimension
  -- every tier shares the same range on is, by definition, not the one this rate's
  -- tiers vary by, and is correctly exempt from the "ordered non-overlapping"
  -- requirement (Prompt 255 §13/§25) for that dimension.
  select count(distinct (weight_min, weight_max)) into v_distinct_weight_ranges from app.vendor_rate_tiers where rate_version_id = p_rate_version_id;
  select count(distinct (volume_min, volume_max)) into v_distinct_volume_ranges from app.vendor_rate_tiers where rate_version_id = p_rate_version_id;

  if v_distinct_weight_ranges > 1 then
    v_first := true;
    for v_tier in select weight_min, weight_max from app.vendor_rate_tiers where rate_version_id = p_rate_version_id order by weight_min, tier_order loop
      if not v_first then
        if v_prev_max is null then
          raise exception 'tier_overlap: an unbounded (null weight_max) tier must be the last tier by weight -- another tier starts at % after it', v_tier.weight_min
            using errcode = 'check_violation';
        elsif v_tier.weight_min < v_prev_max then
          raise exception 'tier_overlap: tier weight ranges overlap at % (previous tier''s weight_max is %)', v_tier.weight_min, v_prev_max
            using errcode = 'check_violation';
        elsif v_tier.weight_min > v_prev_max then
          raise exception 'tier_gap: a gap exists in weight coverage between % and % -- tiers must be contiguous ([min,max) half-open, touching boundaries)', v_prev_max, v_tier.weight_min
            using errcode = 'check_violation';
        end if;
      end if;
      v_prev_max := v_tier.weight_max;
      v_first := false;
    end loop;
  end if;

  if v_distinct_volume_ranges > 1 then
    v_first := true;
    v_prev_max := null;
    for v_tier in select volume_min, volume_max from app.vendor_rate_tiers where rate_version_id = p_rate_version_id order by volume_min, tier_order loop
      if not v_first then
        if v_prev_max is null then
          raise exception 'tier_overlap: an unbounded (null volume_max) tier must be the last tier by volume -- another tier starts at % after it', v_tier.volume_min
            using errcode = 'check_violation';
        elsif v_tier.volume_min < v_prev_max then
          raise exception 'tier_overlap: tier volume ranges overlap at % (previous tier''s volume_max is %)', v_tier.volume_min, v_prev_max
            using errcode = 'check_violation';
        elsif v_tier.volume_min > v_prev_max then
          raise exception 'tier_gap: a gap exists in volume coverage between % and % -- tiers must be contiguous ([min,max) half-open, touching boundaries)', v_prev_max, v_tier.volume_min
            using errcode = 'check_violation';
        end if;
      end if;
      v_prev_max := v_tier.volume_max;
      v_first := false;
    end loop;
  end if;
end;
$$;

-- ===========================================================================
-- 4. app.create_rate_version widened (design note 1) -- four new trailing optional
--    parameters. PostgreSQL identifies a function by its full parameter TYPE list,
--    so adding parameters (even DEFAULTed ones) via a bare CREATE OR REPLACE would
--    create a SECOND, overloaded function rather than truly replacing the original
--    -- an existing 21-positional-argument caller would keep resolving to the OLD,
--    un-widened function, silently defeating this migration's own purpose. The
--    explicit DROP FUNCTION below (old, exact 21-argument signature) first removes
--    that function entirely, so exactly one app.create_rate_version exists
--    afterward, callable with 21 (all-defaults) through 25 (fully explicit)
--    positional arguments -- genuinely backward compatible, not merely coexisting.
-- ===========================================================================

drop function if exists app.create_rate_version(uuid, text, text, text, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, numeric, jsonb, timestamptz, timestamptz, uuid, uuid, text);

create function app.create_rate_version(
  p_tenant_id uuid,
  p_vendor_code text,
  p_vendor_name text,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_equipment_type text,
  p_cargo_weight_min numeric,
  p_cargo_weight_max numeric,
  p_cargo_volume_min numeric,
  p_cargo_volume_max numeric,
  p_currency text,
  p_base_amount numeric,
  p_minimum_amount numeric,
  p_surcharge_components jsonb,
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_vendor_master_id uuid default null,
  p_lead_time_days integer default null,
  p_capacity_terms text default null,
  p_source_import_staging_row_id uuid default null
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_master_record_id uuid;
  v_prior app.vendor_rate_versions;
  v_new app.vendor_rate_versions;
  v_vendor_master_id uuid;
  v_vendor_master app.master_records;
begin
  -- ATW-032 (ISS-2026-032) regression guard: this function gates ONLY on
  -- app.is_support_grant_authority, which validates the CLAIMED actor and never
  -- the caller -- 20260730510000_harden_actor_identity_unchecked_authority_
  -- surface.sql already patched COM-149's original app.create_rate_version with
  -- this exact line; a bare `create or replace` here would silently DROP that
  -- patch (the function body is fully replaced, not merged) and reintroduce
  -- ISS-2026-032 for this function -- found live running this repository's own
  -- rbac-enforcement.sql db-test suite, preserved here rather than reintroduced.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- PRC-255 (ADR-0020): explicit, clearer-message check ahead of the structural
  -- trigger (defense in depth, this repository's own standing convention).
  if p_vendor_master_id is not null then
    select * into v_vendor_master from app.master_records where id = p_vendor_master_id;
    if not found then
      raise exception 'vendor_master_record_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
    end if;
    if v_vendor_master.master_type_code <> 'vendor' then
      raise exception 'invalid_vendor_identity: master record % is master_type_code %, expected vendor', p_vendor_master_id, v_vendor_master.master_type_code
        using errcode = 'check_violation';
    end if;
    if v_vendor_master.tenant_id <> p_tenant_id then
      raise exception 'tenant_mismatch: vendor master record % does not belong to tenant %', p_vendor_master_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_supersedes_version_id is not null then
    -- BUG FIX (post-review, HIGH): `for update` -- the ORIGINAL was a plain,
    -- unlocked SELECT, and the terminal supersede-marking UPDATE below carried
    -- no record_version compare and no post-UPDATE "if not found" re-check (the
    -- exact two safeguards app.approve_rate_version's own terminal UPDATE
    -- correctly applies). Two concurrent create_rate_version calls both
    -- supersede-ing the same source row would both pass this status check and
    -- both blindly apply the terminal UPDATE, breaking the "one supersede
    -- replaces one prior" invariant (two sibling pending_approval revisions both
    -- claiming supersedes_version_id = the same source). Locking here serializes
    -- a second concurrent caller behind the first: once unblocked, it re-reads
    -- the POST-COMMIT row (already approval_status='superseded') and correctly
    -- falls into the invalid_transition branch below instead of racing ahead.
    select * into v_prior from app.vendor_rate_versions where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'rate_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_prior.tenant_id <> p_tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_supersedes_version_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
    if v_prior.approval_status not in ('pending_approval', 'approved') then
      raise exception 'invalid_transition: rate version % is % and cannot be superseded', p_supersedes_version_id, v_prior.approval_status
        using errcode = 'check_violation';
    end if;
    v_master_record_id := v_prior.master_record_id;
    v_vendor_master_id := coalesce(p_vendor_master_id, v_prior.vendor_master_id);
  else
    select id into v_master_record_id from app.create_master_record(
      'vendor_rate', p_tenant_id, p_vendor_code, p_vendor_name, '[]'::jsonb, '{}'::jsonb, p_actor_auth_user_id, p_actor_label
    );
    v_vendor_master_id := p_vendor_master_id;
  end if;

  insert into app.vendor_rate_versions (
    tenant_id, master_record_id, vendor_master_id, service_type, mode, origin_lane, destination_lane, equipment_type,
    cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
    currency, base_amount, minimum_amount, surcharge_components,
    lead_time_days, capacity_terms, source_import_staging_row_id,
    effective_from, effective_to, supersedes_version_id, created_by
  ) values (
    p_tenant_id, v_master_record_id, v_vendor_master_id, p_service_type, p_mode, p_origin_lane, p_destination_lane, p_equipment_type,
    p_cargo_weight_min, p_cargo_weight_max, p_cargo_volume_min, p_cargo_volume_max,
    p_currency, p_base_amount, p_minimum_amount, coalesce(p_surcharge_components, '[]'::jsonb),
    p_lead_time_days, p_capacity_terms, p_source_import_staging_row_id,
    coalesce(p_effective_from, now()), p_effective_to, p_supersedes_version_id, p_actor_label
  )
  returning * into v_new;

  if p_supersedes_version_id is not null then
    -- Defense in depth (belt-and-suspenders): the `for update` lock taken above
    -- already makes this UPDATE race-free within this function (no other
    -- transaction can have changed v_prior's status between the lock and here),
    -- but the explicit status-scoped WHERE + post-UPDATE "if not found" re-check
    -- mirrors this repository's own standing convention (matches
    -- app.approve_rate_version's terminal UPDATE a few dozen lines below) rather
    -- than relying solely on the lock.
    update app.vendor_rate_versions
    set approval_status = 'superseded', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id and approval_status = v_prior.approval_status;
    if not found then
      raise exception 'stale_version: rate version % was concurrently modified and could not be marked superseded', p_supersedes_version_id
        using errcode = 'serialization_failure';
    end if;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_rate_version',
    'app.vendor_rate_versions', v_new.id, 'success', null, null, to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.create_rate_version is 'COM-149, widened PRC-255 (ADR-0020): four new optional trailing parameters (p_vendor_master_id, p_lead_time_days, p_capacity_terms, p_source_import_staging_row_id) -- every existing caller that omits them is unaffected. p_vendor_master_id must reference a same-tenant master_type_code=''vendor'' row when supplied; on a supersede call an unsupplied value defaults to the source''s own vendor_master_id (identity continuity), never auto-inherited for any other business field. Authority (app.is_support_grant_authority) is UNCHANGED from COM-149 -- ADR-0020 does not widen this function''s authority model, only its data shape.';

-- ===========================================================================
-- 5. app.approve_rate_version widened (design notes 4, 12, 13).
-- ===========================================================================

create or replace function app.approve_rate_version(
  p_rate_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_vendor_status text;
begin
  -- ATW-032 (ISS-2026-032) regression guard: same reasoning as app.create_rate_
  -- version above -- 20260730510000 already patched COM-149's original app.
  -- approve_rate_version with this exact line; preserved here, not reintroduced
  -- as a gap.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- PRC-255 addition (design note 13): `for update` -- serializes this approval
  -- against a concurrent app.add_vendor_rate_tier/app.remove_vendor_rate_tier call
  -- on the SAME parent row (both lock this exact row before touching a tier).
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id for update;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be approved', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  -- PRC-255 addition (design note 12): a rate linked to a real vendor identity
  -- cannot go live for a non-active vendor.
  if v_rate.vendor_master_id is not null then
    select lifecycle_status into v_vendor_status from app.vendor_profiles where master_record_id = v_rate.vendor_master_id;
    if v_vendor_status is distinct from 'active' then
      raise exception 'vendor_not_active: linked vendor % is % -- a rate cannot be approved for a non-active vendor', v_rate.vendor_master_id, coalesce(v_vendor_status, 'unregistered')
        using errcode = 'check_violation';
    end if;
  end if;

  -- PRC-255 addition (design note 3): ordered non-overlapping tier validation,
  -- validated at publish time only.
  perform app._validate_vendor_rate_tiers_contiguous(p_rate_version_id);

  begin
    update app.vendor_rate_versions
    set approval_status = 'approved', approved_by = p_actor_label, approved_at = now(), updated_at = now(), record_version = record_version + 1
    where id = p_rate_version_id and record_version = p_expected_version
    returning * into v_rate;
  exception
    -- PRC-255 addition (design note 4): translate the raw EXCLUDE-constraint
    -- violation into the same clear, named error class every other validation
    -- failure in this repository raises.
    when exclusion_violation then
      raise exception 'ambiguous_overlap: an approved, currently-effective rate version already exists for the identical vendor/service/mode/lane/equipment scope with an overlapping validity window'
        using errcode = 'check_violation';
    -- BUG FIX (post-review, MEDIUM): a GiST EXCLUDE constraint under real
    -- concurrent contention can surface as a raw Postgres deadlock (sqlstate
    -- 40P01), not only exclusion_violation (23P01) -- a well-known
    -- characteristic of GiST index insertion under contention, live-reproduced
    -- across repeated concurrent-approval trials. Without this branch, roughly
    -- half of genuinely-conflicting concurrent approvals would leak an
    -- untranslated "deadlock detected" error instead of the documented
    -- ambiguous_overlap class this migration's own design note 4 promises for
    -- EVERY such conflict -- both sqlstates arise from the identical business
    -- conflict (two approvals racing for the same scope) and must translate
    -- identically.
    when deadlock_detected then
      raise exception 'ambiguous_overlap: a concurrent approval at the identical vendor/service/mode/lane/equipment scope could not be serialized -- retry the approval'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: rate version % target row was concurrently modified (expected version %)', p_rate_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', null, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$$;

comment on function app.approve_rate_version is 'COM-149, widened PRC-255: unchanged signature. Adds (in order) a for-update lock, a linked-vendor lifecycle_status=active check, tier-contiguity validation, and translation of the EXCLUDE-constraint ambiguous-overlap violation into a named error. Authority (app.is_support_grant_authority) is unchanged.';

-- ===========================================================================
-- 6. Exact calculate/lookup API (design note 7).
-- ===========================================================================

-- Private, ungated pure-computation helper -- no grant, callable only from within
-- another function owned by the same role (PRC-254's own convention).
create function app._compute_vendor_rate_amount(
  p_rate app.vendor_rate_versions,
  p_weight numeric,
  p_volume numeric,
  p_quantity numeric
)
returns table (
  matched_tier_id uuid,
  base_component numeric,
  tier_component numeric,
  surcharge_component numeric,
  subtotal_amount numeric,
  minimum_amount_applied boolean,
  computed_amount numeric,
  rounding_mode text,
  rounding_precision integer,
  uom_basis jsonb,
  component_breakdown jsonb
)
language plpgsql
as $$
declare
  v_tier app.vendor_rate_tiers;
  v_quantity numeric := coalesce(p_quantity, 1);
  v_base numeric;
  v_tier_amount numeric;
  v_surcharge_total numeric := 0;
  v_component jsonb;
  v_subtotal numeric;
  v_minimum_applied boolean := false;
  v_final numeric;
begin
  if v_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be a positive number' using errcode = 'check_violation';
  end if;

  if p_weight is not null or p_volume is not null then
    select * into v_tier
    from app.vendor_rate_tiers t
    where t.rate_version_id = p_rate.id
      and (p_weight is null or (p_weight >= t.weight_min and (t.weight_max is null or p_weight < t.weight_max)))
      and (p_volume is null or (p_volume >= t.volume_min and (t.volume_max is null or p_volume < t.volume_max)))
    order by t.tier_order
    limit 1;
  end if;

  if v_tier.id is not null then
    v_tier_amount := v_tier.amount;
    v_base := v_tier.amount * v_quantity;
  else
    v_tier_amount := null;
    v_base := p_rate.base_amount * v_quantity;
  end if;

  for v_component in select * from jsonb_array_elements(coalesce(p_rate.surcharge_components, '[]'::jsonb)) loop
    v_surcharge_total := v_surcharge_total + coalesce((v_component ->> 'amount')::numeric, 0);
  end loop;

  v_subtotal := v_base + v_surcharge_total;

  if v_tier.id is not null and v_tier.minimum_charge is not null and v_subtotal < v_tier.minimum_charge then
    v_subtotal := v_tier.minimum_charge;
    v_minimum_applied := true;
  elsif v_tier.id is null and p_rate.minimum_amount is not null and v_subtotal < p_rate.minimum_amount then
    v_subtotal := p_rate.minimum_amount;
    v_minimum_applied := true;
  end if;

  v_final := app.apply_finance_rounding(v_subtotal, 2, 'round_half_up');

  return query select
    v_tier.id,
    p_rate.base_amount * v_quantity,
    case when v_tier_amount is not null then v_tier_amount * v_quantity else null end,
    v_surcharge_total,
    v_subtotal,
    v_minimum_applied,
    v_final,
    'round_half_up'::text,
    2,
    jsonb_build_object('weight_uom', 'kg', 'volume_uom', 'cbm', 'quantity_uom', 'unit'),
    jsonb_build_object(
      'rate_version_id', p_rate.id,
      'base_amount', p_rate.base_amount,
      'matched_tier_id', v_tier.id,
      'matched_tier_amount', v_tier.amount,
      'weight_input', p_weight,
      'volume_input', p_volume,
      'quantity', v_quantity,
      'surcharge_components', p_rate.surcharge_components,
      'lead_time_days', p_rate.lead_time_days,
      'capacity_terms', p_rate.capacity_terms,
      'currency', p_rate.currency
    );
end;
$$;

comment on function app._compute_vendor_rate_amount is 'PRC-255 design note 7: the ONE real calculation (match a tier by [min,max) half-open weight/volume, sum surcharge_components, apply the matched minimum, round via app.apply_finance_rounding -- FIN-194, never reimplemented). Private, no grant -- shared by app.calculate_vendor_rate (public read preview) and app.select_vendor_rate (snapshot persistence), so both entry points are provably identical.';

create function app.calculate_vendor_rate(
  p_rate_version_id uuid,
  p_weight numeric,
  p_volume numeric,
  p_quantity numeric,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  matched_tier_id uuid,
  currency text,
  base_component numeric,
  tier_component numeric,
  surcharge_component numeric,
  subtotal_amount numeric,
  minimum_amount_applied boolean,
  computed_amount numeric,
  rounding_mode text,
  rounding_precision integer,
  uom_basis jsonb,
  component_breakdown jsonb,
  computed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_decision app.rbac_decision;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  -- ADR-0020's own directed gate: the entire return shape of this function is cost
  -- data (there is no non-cost-masked variant of "the computed amount"), so
  -- PRC:View cost alone -- not PRC:View + the unrelated COM:View cost -- is the
  -- single, correct authority gate (design note above app.has_prc_view_cost).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rate.tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select p_rate_version_id, c.matched_tier_id, v_rate.currency, c.base_component, c.tier_component, c.surcharge_component,
    c.subtotal_amount, c.minimum_amount_applied, c.computed_amount, c.rounding_mode, c.rounding_precision, c.uom_basis, c.component_breakdown, now()
  from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity) c;
end;
$$;

comment on function app.calculate_vendor_rate is 'PRC-255 (RPD-040, Prompt 255 §18): read-only, no side effect. Gated on PRC:View cost alone (ADR-0020''s own directed reuse -- the entire return shape is cost data, so there is no separate non-cost "View" tier to also require). Returns the exact computed amount plus the full snapshot inputs/components/rounding needed to reproduce the calculation independently later.';

-- ===========================================================================
-- 7. app.select_vendor_rate widened (design note 7) -- three new optional trailing
--    parameters. Same DROP-then-CREATE reasoning as section 4 above (a bare CREATE
--    OR REPLACE with a longer parameter type list would create a second, coexisting
--    overload rather than truly replacing the original 8-argument function).
-- ===========================================================================

drop function if exists app.select_vendor_rate(uuid, uuid, boolean, text, numeric, text, uuid, text);

create function app.select_vendor_rate(
  p_costing_request_id uuid,
  p_rate_version_id uuid,
  p_is_adhoc boolean,
  p_adhoc_currency text,
  p_adhoc_amount numeric,
  p_override_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_weight numeric default null,
  p_volume numeric default null,
  p_quantity numeric default null
)
returns app.rate_selections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_decision_prc_cost app.rbac_decision;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_calc record;
  v_amount numeric;
  v_snapshot jsonb;
begin
  select * into v_request from app.costing_requests where id = p_costing_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_costing_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot accept a rate selection', p_costing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to select a rate', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_costing_request_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_is_adhoc then
    if p_override_reason is null or length(trim(p_override_reason)) = 0 then
      raise exception 'reason_required: an ad-hoc rate selection requires a non-empty override reason'
        using errcode = 'not_null_violation';
    end if;
    if p_adhoc_currency is null or p_adhoc_currency !~ '^[A-Z]{3}$' or p_adhoc_amount is null or p_adhoc_amount < 0 then
      raise exception 'invalid_adhoc_rate: an ad-hoc selection requires a valid 3-letter currency and a non-negative amount'
        using errcode = 'check_violation';
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, null, true, p_adhoc_currency, p_adhoc_amount,
      jsonb_build_object('is_adhoc', true, 'currency', p_adhoc_currency, 'amount', p_adhoc_amount, 'override_reason', p_override_reason),
      p_override_reason, p_actor_label
    )
    returning * into v_selection;
  else
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
    if not found then
      raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
    end if;
    if v_rate.tenant_id <> v_request.tenant_id then
      raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_rate_version_id, v_request.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_rate.approval_status <> 'approved' and (p_override_reason is null or length(trim(p_override_reason)) = 0) then
      raise exception 'reason_required: selecting a % (not approved) rate version requires a non-empty override reason', v_rate.approval_status
        using errcode = 'not_null_violation';
    end if;

    -- PRC-255 addition: when tier-matching inputs are supplied, snapshot the exact
    -- tier-matched calculation (RPD-040) via the SAME private helper app.calculate_
    -- vendor_rate itself calls -- omitting them (every pre-PRC-255 caller)
    -- reproduces COM-149's original flat base_amount behavior unchanged.
    --
    -- SECURITY FIX (post-review): computing a tier-matched amount embeds the
    -- SAME sensitive tier cost breakdown (matched_tier_id, matched_tier_amount,
    -- tier_component, ...) that app.calculate_vendor_rate/app.vendor_rate_tiers_
    -- directory correctly gate behind PRC:View cost (design note 2/ADR-0020's own
    -- directed reuse of that gate for this checkpoint's new sensitive-field
    -- class). The pre-existing COM:Edit + COM:View cost gate above is COM-149's
    -- own unchanged authority for the flat-base_amount case, but it is NOT
    -- sufficient authority for the tier-derived case -- a Commercial-side actor
    -- holding only COM:View cost (no PRC permissions at all) could otherwise
    -- supply p_weight/p_volume/p_quantity and receive the full negotiated
    -- vendor-tier cost structure in the returned snapshot, bypassing the separate
    -- PRC:View cost boundary this migration's own design intends. So: PRC:View
    -- cost is required IN ADDITION to the unchanged COM gates, but ONLY on this
    -- branch (tier inputs supplied) -- every pre-PRC-255 caller (all three null)
    -- never reaches this check and is completely unaffected.
    if p_weight is not null or p_volume is not null or p_quantity is not null then
      v_decision_prc_cost := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'View cost');
      if not v_decision_prc_cost.allowed then
        raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) required to compute/snapshot a tier-matched rate amount', p_actor_auth_user_id, v_decision_prc_cost.reason
          using errcode = 'insufficient_privilege';
      end if;
      select * into v_calc from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity);
      v_amount := v_calc.computed_amount;
      v_snapshot := to_jsonb(v_rate) || jsonb_build_object('calculation', to_jsonb(v_calc));
    else
      v_amount := v_rate.base_amount;
      v_snapshot := to_jsonb(v_rate);
    end if;

    insert into app.rate_selections (tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
    values (
      v_request.tenant_id, p_costing_request_id, v_rate.id, false, v_rate.currency, v_amount, v_snapshot, p_override_reason, p_actor_label
    )
    returning * into v_selection;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'select_vendor_rate',
    'app.rate_selections', v_selection.id, 'success', null, null,
    jsonb_build_object('costing_request_id', p_costing_request_id, 'is_adhoc', v_selection.is_adhoc, 'rate_version_id', v_selection.rate_version_id)
  );

  return v_selection;
end;
$$;

comment on function app.select_vendor_rate is 'COM-149, widened PRC-255: three new optional trailing parameters (p_weight, p_volume, p_quantity). Every pre-PRC-255 caller (all null) reproduces the original flat base_amount snapshot unchanged and needs only the unchanged COM:Edit + COM:View cost gate; supplying any of them additionally REQUIRES PRC:View cost (post-review security fix -- computing/snapshotting a tier-matched amount exposes the same sensitive tier cost breakdown app.calculate_vendor_rate/app.vendor_rate_tiers_directory correctly gate on PRC:View cost, and COM:View cost alone must never be sufficient to read it).';

-- ===========================================================================
-- 8. Import adapter (design notes 8-11).
-- ===========================================================================

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('vendor_rate_import', 'Vendor Rate Import', 'PRC', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:vendor_rate_import', 'Vendor Rate Import', 'PRC', 'system')
on conflict (code) do nothing;

comment on table app.import_export_schemas is 'PLT-131, first real registration PRC-255: registry of import/export schema kinds, now including ''vendor_rate_import'' (design note 9 documents its full column list). Each tenant still separately publishes its own import_export:<code> column definition via the existing Configuration Engine before creating a job against a given schema code.';

-- Domain-specific row validator (design note 10). Calls app.validate_staging_row
-- UNCHANGED first (structural pass, never reimplemented), then applies the
-- formula-injection/currency-format/vendor_master_code cross-table checks the
-- generic validator cannot perform.
create function app.validate_vendor_rate_import_row(
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
  v_text_fields text[] := array['vendor_code', 'vendor_name', 'vendor_master_code', 'service_type', 'mode', 'origin_lane', 'destination_lane', 'equipment_type', 'currency', 'capacity_terms'];
  v_tier_idx integer;
  v_weight_min numeric;
  v_weight_max numeric;
  v_volume_min numeric;
  v_volume_max numeric;
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

  if coalesce(v_payload ->> 'currency', '') !~ '^[A-Z]{3}$' then
    v_errors := v_errors || ('currency: ' || coalesce(v_payload ->> 'currency', '(missing)') || ' is not a valid 3-letter uppercase ISO currency code');
  end if;

  if coalesce(v_payload ->> 'vendor_master_code', '') <> '' then
    if not exists (
      select 1 from app.master_records
      where tenant_id = v_job.tenant_id and master_type_code = 'vendor' and code = (v_payload ->> 'vendor_master_code')
    ) then
      v_errors := v_errors || ('vendor_master_code: ' || (v_payload ->> 'vendor_master_code') || ' does not resolve to a registered vendor in this tenant');
    end if;
  end if;

  for v_tier_idx in 1..3 loop
    v_weight_min := nullif(v_payload ->> ('tier' || v_tier_idx || '_weight_min'), '')::numeric;
    v_weight_max := nullif(v_payload ->> ('tier' || v_tier_idx || '_weight_max'), '')::numeric;
    v_volume_min := nullif(v_payload ->> ('tier' || v_tier_idx || '_volume_min'), '')::numeric;
    v_volume_max := nullif(v_payload ->> ('tier' || v_tier_idx || '_volume_max'), '')::numeric;
    if v_weight_max is not null and v_weight_max <= coalesce(v_weight_min, 0) then
      v_errors := v_errors || ('tier' || v_tier_idx || ': weight_max must exceed weight_min');
    end if;
    if v_volume_max is not null and v_volume_max <= coalesce(v_volume_min, 0) then
      v_errors := v_errors || ('tier' || v_tier_idx || ': volume_max must exceed volume_min');
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

comment on function app.validate_vendor_rate_import_row is 'PRC-255 design note 10: calls app.validate_staging_row (PLT-131, unchanged) first, then rejects (never silently strips) any of ten text-shaped columns beginning with =, +, -, @, tab, or carriage return, plus a currency-format and vendor_master_code cross-table check. Downgrades an already-valid row to invalid with a clear, named reason -- never a generic parse failure.';

-- The commit adapter (design note 11). SECURITY DEFINER so its nested calls to the
-- private app._insert_vendor_rate_tier helper (no grant) succeed; granted to
-- service_role only (PLT-131's own "server-mediated for every write" convention --
-- never granted to authenticated directly).
create function app.commit_vendor_rate_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
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
  v_vendor_master_id uuid;
  v_vendor_master app.master_records;
  v_new_rate app.vendor_rate_versions;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_tier_idx integer;
  v_tier_prefix text;
  v_tier_amount numeric;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'vendor_rate_import' then
    raise exception 'import_export_wrong_schema: job % is not a vendor_rate_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- PRC-255 addition (design note 11): BOTH the unchanged create_rate_version
  -- authority AND the new PRC:Import action -- see this migration's own header for
  -- why PRC:Import alone must never be sufficient.
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'PRC', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
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

  -- Job-scoped advisory lock (pattern 3) -- resolved and taken before any staging
  -- row is read, serializing any concurrent/replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.vendor_rate_versions where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_vendor_master_id := null;
    if coalesce(v_payload ->> 'vendor_master_code', '') <> '' then
      select * into v_vendor_master from app.master_records
      where tenant_id = v_job.tenant_id and master_type_code = 'vendor' and code = (v_payload ->> 'vendor_master_code');
      if not found then
        raise exception 'import_vendor_master_not_found: staging row % references vendor_master_code % which does not resolve to a registered vendor in tenant %', v_row.row_number, v_payload ->> 'vendor_master_code', v_job.tenant_id
          using errcode = 'check_violation';
      end if;
      v_vendor_master_id := v_vendor_master.id;
    end if;

    begin
      select * into v_new_rate from app.create_rate_version(
        v_job.tenant_id,
        v_payload ->> 'vendor_code',
        v_payload ->> 'vendor_name',
        v_payload ->> 'service_type',
        nullif(v_payload ->> 'mode', ''),
        v_payload ->> 'origin_lane',
        v_payload ->> 'destination_lane',
        nullif(v_payload ->> 'equipment_type', ''),
        null, null, null, null,
        v_payload ->> 'currency',
        (v_payload ->> 'base_amount')::numeric,
        nullif(v_payload ->> 'minimum_amount', '')::numeric,
        '[]'::jsonb,
        now(), null, null,
        p_actor_auth_user_id, p_actor_label,
        v_vendor_master_id,
        nullif(v_payload ->> 'lead_time_days', '')::integer,
        nullif(v_payload ->> 'capacity_terms', ''),
        v_row.id
      );
    exception
      when unique_violation then
        -- Race-recovery (pattern 4): a concurrent/replayed call already committed
        -- this exact staging row between the exists-check above and this INSERT.
        -- BUG FIX (post-review, CRITICAL): the ORIGINAL handler caught ANY
        -- unique_violation unconditionally, which also silently swallowed a
        -- GENUINE vendor_code collision -- app.create_rate_version ->
        -- app.create_master_record has its own unlocked check-then-insert on
        -- master_records_tenant_code_unique and re-raises a real collision as
        -- master_record_already_exists, ALSO sqlstate unique_violation. Treating
        -- that as "safe replay, skip" silently dropped the row: the job still
        -- reported status=completed/valid_row_count as if the rate version had
        -- been created, but no row was ever written, with no error and no
        -- recoverable retry path (a completed job can never be recommitted).
        -- Only a violation of THIS adapter's own idempotency guard
        -- (vendor_rate_versions_source_import_row_unique) means "already
        -- committed, safe to skip" -- any other unique_violation is a REAL
        -- failure and must abort the whole commit (the surrounding transaction
        -- rolls back, so the job is never marked completed with a silently
        -- dropped row).
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'vendor_rate_versions_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;

    for v_tier_idx in 1..3 loop
      v_tier_prefix := 'tier' || v_tier_idx || '_';
      v_tier_amount := nullif(v_payload ->> (v_tier_prefix || 'amount'), '')::numeric;
      if v_tier_amount is not null then
        perform app._insert_vendor_rate_tier(
          v_new_rate,
          v_tier_idx,
          nullif(v_payload ->> (v_tier_prefix || 'weight_min'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'weight_max'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'volume_min'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'volume_max'), '')::numeric,
          v_tier_amount,
          nullif(v_payload ->> (v_tier_prefix || 'minimum_charge'), '')::numeric,
          null,
          p_actor_label
        );
      end if;
    end loop;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_vendor_rate_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object('status', v_updated.status, 'rate_versions_created', v_created_count, 'rows_already_committed_skipped', v_skipped_count)
  );

  return v_updated;
end;
$$;

comment on function app.commit_vendor_rate_import_job is 'PRC-255 design note 11: the first real domain-write adapter for PLT-131 (ISS-2026-013). Requires BOTH app.is_support_grant_authority AND PRC:Import. Idempotent-safe: a staged row can produce at most one rate version ever (unique source_import_staging_row_id), defended by a pre-check, a nested unique_violation handler, and a job-scoped advisory lock. Never calls the generic app.commit_import_job -- replicates its own exact pending/invalid-row gate so domain writes happen strictly BEFORE the job is marked completed (a failed domain write rolls back the whole transaction, including the job status change -- no "completed" job that silently wrote nothing).';

-- ===========================================================================
-- 9. Masking view extension (design note 14) -- pure additive/hardening change,
--    app.v_active_vendor_rates (select * ...) inherits both automatically.
-- ===========================================================================

create or replace view app.vendor_rate_versions_directory
as
select
  v.id as rate_version_id,
  v.tenant_id,
  v.master_record_id,
  m.code as vendor_code,
  m.name as vendor_name,
  v.service_type,
  v.mode,
  v.origin_lane,
  v.destination_lane,
  v.equipment_type,
  v.cargo_weight_min,
  v.cargo_weight_max,
  v.cargo_volume_min,
  v.cargo_volume_max,
  case when app.has_view_cost(v.tenant_id) then v.currency else null end as currency,
  case when app.has_view_cost(v.tenant_id) then v.base_amount else null end as base_amount,
  case when app.has_view_cost(v.tenant_id) then v.minimum_amount else null end as minimum_amount,
  case when app.has_view_cost(v.tenant_id) then v.surcharge_components else null end as surcharge_components,
  not app.has_view_cost(v.tenant_id) as cost_masked,
  v.approval_status,
  v.effective_from,
  v.effective_to,
  v.supersedes_version_id,
  v.approved_by,
  v.approved_at,
  v.rejected_reason,
  v.withdrawn_reason,
  v.record_version,
  v.created_by,
  v.created_at,
  v.updated_at,
  v.vendor_master_id,
  case when app.has_view_cost(v.tenant_id) then v.lead_time_days else null end as lead_time_days,
  case when app.has_view_cost(v.tenant_id) then v.capacity_terms else null end as capacity_terms
from app.vendor_rate_versions v
join app.master_records m on m.id = v.master_record_id
where (app.has_active_tenant_membership(v.tenant_id) and not app.actor_holds_customer_user_layer(v.tenant_id)) or app.is_supreme_admin();

comment on view app.vendor_rate_versions_directory is 'COM-149, extended PRC-255 design note 14: three new trailing columns (vendor_master_id, lead_time_days, capacity_terms -- the latter two cost-masked identically to base_amount). Row filter hardened to exclude a customer_user-layer principal entirely (zero rows, stronger than cost-masking alone), the same pattern-5 predicate every Phase 6 table uses. app.v_active_vendor_rates (select * from this view ...) inherits both changes automatically.';

-- app.search_vendor_rates (COM-149) is declared `returns setof app.vendor_rate_
-- versions_directory` -- its own body's fixed, explicit column list must be widened
-- in lockstep with that view's now-34-column shape, or every call raises "structure
-- of query does not match function result type" (found live, running COM-149's own
-- unchanged db-test suite against this migration, exactly the kind of regression
-- requirement 5/7's own "confirm zero regression" discipline exists to catch).
-- Signature is unchanged (no new parameters), so a plain CREATE OR REPLACE
-- genuinely replaces the original -- no DROP needed, unlike sections 4/7 above.
create or replace function app.search_vendor_rates(
  p_tenant_id uuid,
  p_service_type text,
  p_origin_lane text,
  p_destination_lane text,
  p_mode text,
  p_actor_auth_user_id uuid,
  p_limit integer default 20
)
returns setof app.vendor_rate_versions_directory
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at,
    v.vendor_master_id,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end as lead_time_days,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end as capacity_terms
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.tenant_id = p_tenant_id
    and v.approval_status = 'approved'
    and v.effective_from <= now()
    and (v.effective_to is null or v.effective_to > now())
    and (p_service_type is null or v.service_type = p_service_type)
    and (p_origin_lane is null or v.origin_lane = p_origin_lane)
    and (p_destination_lane is null or v.destination_lane = p_destination_lane)
    and (p_mode is null or v.mode = p_mode)
  order by base_amount nulls last, vendor_code, rate_version_id
  limit least(coalesce(p_limit, 20), 200);
end;
$$;

comment on function app.search_vendor_rates is 'COM-149, widened PRC-255: unchanged signature and behavior, body extended to match app.vendor_rate_versions_directory''s three new trailing columns (its own declared return type). Requires COM:View, unchanged.';

-- ===========================================================================
-- 10. RLS + grants.
-- ===========================================================================

alter table app.vendor_rate_tiers enable row level security;

create policy vendor_rate_tiers_select_scoped on app.vendor_rate_tiers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

-- Column-restricted grant (mirrors app.vendor_rate_versions' own proven technique)
-- -- amount/minimum_charge withheld from authenticated, only reachable through
-- app.vendor_rate_tiers_directory's own has_prc_view_cost mask.
grant select (
  id, tenant_id, rate_version_id, tier_order, weight_min, weight_max, volume_min, volume_max,
  record_version, created_by, created_at, updated_at
) on app.vendor_rate_tiers to authenticated;
grant select on app.vendor_rate_tiers to service_role;

grant select on app.vendor_rate_tiers_directory to authenticated, service_role;
grant select on app.vendor_rate_versions_directory to authenticated, service_role;
grant select on app.v_active_vendor_rates to authenticated, service_role;

-- app.has_prc_view_cost is already granted to authenticated, service_role by
-- PRC-252's own migration (20260730590000) -- not re-granted here.

grant execute on function app.create_rate_version(uuid, text, text, text, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, numeric, jsonb, timestamptz, timestamptz, uuid, uuid, text, uuid, integer, text, uuid) to authenticated, service_role;
grant execute on function app.approve_rate_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.select_vendor_rate(uuid, uuid, boolean, text, numeric, text, uuid, text, numeric, numeric, numeric) to authenticated, service_role;

grant execute on function app.add_vendor_rate_tier(uuid, integer, numeric, numeric, numeric, numeric, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_rate_tier(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.calculate_vendor_rate(uuid, numeric, numeric, numeric, uuid) to authenticated, service_role;

grant execute on function app.validate_vendor_rate_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_vendor_rate_import_job(uuid, boolean, uuid, text) to service_role;
