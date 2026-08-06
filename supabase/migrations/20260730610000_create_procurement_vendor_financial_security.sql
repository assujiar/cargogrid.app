-- Procurement capability PRC-254 (Vendor Banking and Tax Security, CG-S11-PRC-005).
-- This repository's FIRST at-rest confidentiality mechanism -- every prior "sensitive
-- field" (Commercial's selling price/margin/COM-149, Finance's cost/margin, PRC-252/253's
-- own personal-data-tagged fields) uses VISIBILITY masking only: the raw value sits in
-- the table in plaintext and only READ access is gated behind a permission check. Bank
-- account numbers and tax identifiers additionally require genuine at-rest
-- confidentiality (Sec.16 "encryption/key handling"; Sec.13 "encrypted/masked bank-account
-- versions... tax identity hashes/versions"). Extends app.vendor_profiles (PRC-251,
-- master_type_code='vendor' via ADR-0020) -- every bank account/tax identity/payment-term
-- proposal ultimately traces to app.vendor_profiles.master_record_id. Never mutates
-- app.vendor_profiles.lifecycle_status; never writes to any app.finance_* table; never
-- executes or simulates settlement/payment/cash movement (Sec.24, RPD-038).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Encryption mechanism (Sec.16).** `pgcrypto` is already enabled repository-wide
--    (`create extension if not exists pgcrypto;`, `20260716075355_create_tenants.sql`) --
--    NOT re-declared here. The true sensitive value (full bank account number, full tax
--    ID) is stored ONLY as `pgp_sym_encrypt(plaintext, app.vendor_financial_encryption_
--    key())` in a `bytea` column -- never as a second plaintext column, never in jsonb,
--    never in an audit before/after payload. `app.vendor_financial_encryption_key()`
--    reads `current_setting('app.vendor_financial_encryption_key', true)` and RAISES
--    `encryption_key_not_configured` (fails closed) if that GUC is unset or empty --
--    encryption never silently proceeds with an empty/default key. This function is the
--    ONE config value this capability needs from the infra-layer secret manager ADR-0010
--    already selected; production key provisioning/rotation/custody is an infrastructure
--    concern this migration does NOT solve -- a genuine, disclosed residual limitation,
--    not a defect hidden from the reviewer. This capability's own db-tests set the GUC to
--    a fixed test value (`set_config('app.vendor_financial_encryption_key',
--    'test-only-key-not-for-production', false)`) at the top of the fixture.
-- 2. **Deterministic hash for duplicate detection WITHOUT decryption (Sec.16/17).**
--    `account_number_hash`/`tax_id_hash` (`encode(digest(plaintext, 'sha256'), 'hex')`)
--    are separate, indexed, deterministic columns -- the ONLY thing ever compared or
--    indexed for equality; the encrypted column itself is never indexed or queried for
--    equality. `get_vendor_bank_account_masked`/`get_vendor_tax_identity_masked` surface
--    a live-computed `is_duplicate_candidate` boolean (another row, same tenant, same
--    hash, different vendor, status in active/pending_approval) -- a real fraud signal
--    that needs zero decryption to compute.
-- 3. **Last-4 masked display (Sec.13/24 "masked bank-account versions").**
--    `account_number_last4`/`tax_id_last4` are plain, unencrypted text -- the
--    industry-standard masked-display convention (a last-4 reveal is not the secret).
--    This is what every `PRC:View`-only caller gets by default from every read RPC and
--    from every list/export/search projection (Sec.13/24's own "never in generic export,
--    search, logs" rule) -- the encrypted/hashed columns are NEVER included in any
--    masked/list/search projection, only in the two narrow, privileged, audited reveal
--    RPCs (design note 6).
-- 4. **`app.vendor_financial_encryption_key()`/`app._encrypt_vendor_financial_value()`/
--    `app._decrypt_vendor_financial_value()`/`app._hash_vendor_financial_value()`/
--    `app._last4_vendor_financial_value()` are private helpers** -- no grant to
--    `authenticated`/`service_role`/`anon`, callable only from within another
--    `SECURITY DEFINER` function owned by the same role, the identical shape
--    `app._compute_vendor_assessment_score` (PRC-252) already established.
-- 5. **Versioning mirrors PRC-253's exact `requirement_family_id` shape, one layer
--    down.** `account_family_id`/`tax_family_id` are minted fresh (`default
--    gen_random_uuid()`) on every draft creation and are carried forward onto a newly
--    APPROVED row only when the checker supplies `p_supersedes_account_id`/
--    `p_supersedes_tax_identity_id` at DECISION time (never at draft-create time) --
--    the exact "a draft has no borrowed identity until it is actually confirmed as a
--    continuation" discipline `app.publish_vendor_compliance_requirement` established. A
--    partial unique index (`..._active_family_unique` on the family id where
--    `status='active'`) guarantees at most one live active version per family. A second,
--    defensive scope-tuple partial unique index (`..._active_scope_unique` on
--    `(vendor_master_record_id, purpose, currency)` / `(vendor_master_record_id,
--    tax_id_type)` where `status='active'`) closes the same "two independent families
--    targeting the identical practical scope" ambiguity PRC-253's design note 3 already
--    disclosed and closed the same way.
-- 6. **The reveal RPCs are the ONLY way to get the real decrypted value back
--    (Sec.16 "purpose-bound reveal").** `app.reveal_vendor_bank_account_number`/
--    `app.reveal_vendor_tax_identity_number` are gated on the already-seeded
--    `app.has_prc_view_personal_data` (PRC-251, reused verbatim -- never duplicated),
--    additionally require a non-empty `p_reveal_reason` (purpose-bound, Sec.16) AND a
--    fresh `p_reauth_confirmed_at` (a genuine strengthening beyond the letter of "MFA for
--    approvers" -- revealing plaintext banking/tax data is at least as privileged as
--    approving a change, disclosed here as a deliberate choice, not an oversight), and
--    call `app.capture_audit_event` unconditionally on every successful reveal (mirrors
--    `app.file_access_logs`'s own PLT-128 "every access... " discipline, applied here to
--    a genuinely different resource) -- a caller can never silently decrypt with no
--    record of who revealed it and when. The audit row NEVER carries the plaintext or
--    the ciphertext -- only `account_number_last4`/`tax_id_last4` plus the reveal reason
--    (design note 9's own "never plaintext/ciphertext in audit" rule, applied here too).
-- 7. **Maker-checker + MFA, reusing exactly two proven precedents, never a new
--    mechanism.** Self-approval block: the exact `self_approval_not_allowed`
--    inline pattern `app.approve_warehouse_billing_event` established (ATW-020),
--    reproduced byte-for-byte in every `decide_*` RPC in this migration, PLUS a
--    defensive, redundant table-level CHECK (`..._no_self_approval_check`), the same
--    belt-and-suspenders PRC-253 applied to waiver decisions. MFA freshness: the EXACT
--    `p_reauth_confirmed_at`/`reauth_required`/`insufficient_privilege`/5-minute-window
--    shape `app.start_support_session` (PLT-115) and
--    `app.decide_credit_profile_approval_step`/`app.create_credit_override` (COM-157)
--    established, reproduced verbatim in every `decide_*` RPC and in both reveal RPCs
--    (design note 6). This is NOT a real MFA provider integration -- it verifies
--    freshness of a caller-supplied timestamp real client-side re-authentication is
--    assumed to have produced, the identical disclosed limitation both precedents carry.
-- 8. **Evidence-file re-validation on every `p_evidence_file_id` parameter accepted**
--    (the exact gap PRC-252's AND PRC-253's own adversarial reviews independently found
--    and fixed as a CONFIRMED HIGH finding -- applied proactively here, a third time,
--    rather than re-discovering it): every RPC that accepts an evidence file id re-fetches
--    `app.files` and rejects on tenant mismatch, wrong `record_type`/`record_id`
--    (`record_type='vendor_financial_verification'`, `record_id=`the vendor's own
--    `master_record_id`), or a non-`clean` `malware_scan_status`. A genuine reviewer also
--    needs a gated, AUDITED path to actually view that evidence (PRC-253's own separate
--    HIGH finding, "reviewers verified evidence blind") -- `app.access_vendor_bank_
--    account_evidence`/`app.access_vendor_tax_identity_evidence` compose `PRC:Download`
--    with PLT-128's own `app.authorize_file_access` (malware-scan + record/sensitivity
--    gate, RPD-032), applied proactively rather than left for a fix-pass to discover.
-- 9. **Audit rows for these two tables NEVER call `to_jsonb(row)`** -- a plain
--    `to_jsonb()` on a row carrying a `bytea` column would serialize the CIPHERTEXT
--    bytes into the audit trail's `before_value`/`after_value` jsonb, directly violating
--    Sec.16/24's "no plaintext export/log/cache" and this task's own explicit "never in
--    an audit before/after payload" instruction (ciphertext is still the secret's own
--    encrypted form -- disclosing it defeats key rotation's own forward-secrecy value and
--    is explicitly forbidden by the task brief). Every `capture_audit_event` call
--    touching `app.vendor_bank_accounts`/`app.vendor_tax_identities` hand-builds a
--    narrow `jsonb_build_object(...)` containing only `*_last4`, `status`,
--    `currency`/`tax_id_type`, and reason/decision fields -- never the encrypted or
--    decrypted value, never a raw `to_jsonb`. One real interaction found and fixed
--    while authoring this migration's own db-test: `app.capture_audit_event` already
--    applies `app.redact_audit_payload` (PLT-116) unconditionally, whose key-NAME regex
--    (`secret|password|token|key|authorization|cookie|ssn|npwp|bank|account_number|
--    salary|payroll`) matches the literal substrings "bank" and "account_number" --
--    meaning a jsonb key literally named `bank_name`/`account_number_last4` gets
--    silently redacted to `"[REDACTED]"` even though the underlying VALUE (a bank's
--    display name; a deliberately-safe last-4 digit reveal) is not itself sensitive.
--    This migration's own audit payload key names are chosen to avoid tripping that
--    pre-existing, correctly-conservative, key-name-based (not value-aware) platform
--    regex -- `institution_name`/`account_last4`, never `bank_name`/`account_number_
--    last4` as JSONB KEYS (the underlying table COLUMN names are unaffected, only the
--    audit-payload key literals) -- so the reveal RPC's own audited last4 actually
--    persists instead of being redacted into meaninglessness. `tax_id_last4`/
--    `tax_id_type` do not collide with the regex and needed no renaming.
-- 10. **Payment-term change is a versioned proposal/approval PAIR over the existing
--     `app.vendor_profiles.payment_term_days` plain integer column (PRC-251) -- NOT a
--     new master table** (this task's own explicit instruction: Prompt 255's own ADR-0020
--     reconciliation leaves a real payment-terms master table decision open, not this
--     task's to make; this repository's own precedent, ADR-0018/0019, consistently
--     prefers flat typed columns over a generic changeset shape). `app.vendor_payment_
--     term_proposals` snapshots `vendor_profile_expected_version` (the vendor profile's
--     OWN `record_version` at proposal time) so `app.decide_vendor_payment_term_change_
--     proposal`'s own approval branch can optimistically-concurrency-guard the UPDATE to
--     `app.vendor_profiles.payment_term_days` itself, never blindly overwriting a
--     profile that changed in some unrelated way between proposal and decision.
-- 11. **Downstream composition (Sec.13/33): `app.get_vendor_financial_verification_
--     status`** is the one real, tested READ RPC a future Finance/Sourcing/PO/
--     invoice-matching capability composes against -- "verified bank account exists:
--     yes/no, verified tax identity exists: yes/no, on hold: yes/no", nothing more. It
--     never writes to any Finance table, never mutates `app.vendor_profiles.lifecycle_
--     status`, and never executes/simulates settlement (RPD-038, Sec.24). Mirrors
--     `app.get_vendor_compliance_eligibility`'s own downstream-composable read shape
--     (PRC-253) one layer down.
-- 12. **RLS row-policy AND column-level GRANT are two different layers, both required.**
--     The default-deny row policy alone is NOT sufficient for these two tables -- even an
--     ordinary same-tenant `PRC:View` holder must never see the encrypted/hashed columns
--     via a raw `SELECT`. Mirrors `app.vendor_rate_versions`' own column-restricted GRANT
--     (COM-149): the table-level GRANT is revoked entirely and re-granted on an explicit
--     column list that OMITS `account_number_encrypted`/`account_number_hash`/
--     `tax_id_encrypted`/`tax_id_hash` for `authenticated` (only `service_role` -- used
--     exclusively by this migration's own `SECURITY DEFINER` functions internally --
--     gets the full, unrestricted table grant).
-- 13. **RBAC reuses exactly the 12 already-seeded PRC actions**
--     (View/Create/Edit/Delete/Approve/Reject/Export/Override/Download/Import/View
--     cost/View personal data). No new `app.permissions` row is seeded by this
--     migration. Mapping: `Create` = draft a bank account/tax identity, propose a
--     payment-term change; `Edit` = update a draft, submit a draft for approval; `Approve`/
--     `Reject` = decide a bank account/tax identity/payment-term proposal (case-mapped,
--     mirrors `app.decide_vendor_compliance_document`); `Override` = hold/reactivate/
--     deactivate a bank account or tax identity (administrative, not ordinary editing);
--     `View` = every masked read RPC and the downstream verification-status read;
--     `View personal data` = the two reveal RPCs (design note 6, the genuine fit this
--     already-seeded, protected=true action exists for); `Download` = the two evidence-
--     access RPCs (design note 8). `Delete`/`Export`/`Import`/`View cost` have no
--     distinct fit in this capability's own schema -- left unused, a disclosed
--     simplification, not a silently invented gap.
-- 14. **`record_version` optimistic concurrency, idempotency-key replay with full
--     load-bearing-field comparison, `for update` locks, nested `unique_violation`
--     race-recovery, and a per-family `pg_advisory_xact_lock`** are applied on EVERY
--     mutating RPC, hardened patterns copied byte-for-byte from `20260730600000`
--     (the most recently proven-correct migration in this repository). The advisory
--     lock specifically closes a race this capability's own two-row-per-family shape
--     creates that PRC-253's single-row-per-decision shape did not: approving a NEW
--     draft row (which deactivates the OLD active row of the same family, design note 5)
--     races a bystander `hold`/`deactivate`/`reactivate` call acting DIRECTLY on that
--     same OLD active row -- two DIFFERENT rows in the same family, so a plain per-row
--     `for update` lock does not serialize them by itself. Every decide/hold/reactivate/
--     deactivate RPC takes `pg_advisory_xact_lock(hashtextextended(vendor_master_record_
--     id::text || ':' || family_id::text, <capability-local salt>))` BEFORE its own row
--     lock, fully serializing every concurrent state transition within one family
--     regardless of which specific row each call targets -- the identical technique/
--     rationale as `app._recalculate_vendor_compliance_status_family`'s own advisory
--     lock (PRC-253 design note 7) and `app.reconcile_shipment_tracking_health`'s
--     sibling fix (CG-S10-ATW-024), applied proactively rather than discovered by a
--     live three-session race reproduction this migration's own review round would
--     otherwise have to find. Idempotency-key replay comparisons include
--     `account_number_hash`/`tax_id_hash`/`currency`/`purpose`/`tax_id_type` --
--     PRC-253's own adversarial review found TWO separate under-compared idempotency
--     instances (omitting `expiry_date`, then separately `reminder_offsets`); this
--     migration compares every field that distinguishes two logically different
--     proposals from the start.
-- 15. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants, the
--     standing per-migration convention since `PLT-118`.
-- 16. **True multi-session concurrent-race reproduction has no matching sequential
--     db-test proof** (no `dblink`/`pg_background` exists in this test suite) -- the
--     same standing, already-disclosed limitation every prior Phase 6 checkpoint's own
--     build log records. Verified instead by direct conformance to this repository's
--     own established locking pattern plus the full sequential suite passing unchanged.

-- ===========================================================================
-- 1. Encryption/hash/last4 helpers (design notes 1-4). No grant to
--    authenticated/service_role/anon -- callable only from within another
--    SECURITY DEFINER function owned by the same role.
-- ===========================================================================

create function app.vendor_financial_encryption_key()
returns text
language plpgsql
stable
as $$
declare
  v_key text;
begin
  v_key := current_setting('app.vendor_financial_encryption_key', true);
  if v_key is null or length(v_key) = 0 then
    raise exception 'encryption_key_not_configured: app.vendor_financial_encryption_key is not set for this session -- vendor banking/tax encryption cannot proceed without a configured key (see migration header design note 1 for the disclosed key-custody boundary; ADR-0010 selected the production secret-manager product, this function is the one config value this capability reads from it)'
      using errcode = 'config_file_error';
  end if;
  return v_key;
end;
$$;

comment on function app.vendor_financial_encryption_key is 'PRC-254 design note 1: fail-closed GUC read for the symmetric encryption key. Never silently encrypts with an empty/default key. Production key provisioning/rotation/custody is a disclosed, out-of-scope infrastructure concern (ADR-0010); db-tests set this GUC to a fixed test-only value at fixture setup.';

create function app._encrypt_vendor_financial_value(p_plaintext text)
returns bytea
language sql
set search_path = app, public, pg_temp
as $$
  select pgp_sym_encrypt(p_plaintext, app.vendor_financial_encryption_key());
$$;

create function app._decrypt_vendor_financial_value(p_ciphertext bytea)
returns text
language sql
set search_path = app, public, pg_temp
as $$
  select pgp_sym_decrypt(p_ciphertext, app.vendor_financial_encryption_key());
$$;

create function app._hash_vendor_financial_value(p_plaintext text)
returns text
language sql
set search_path = app, public, pg_temp
as $$
  select encode(digest(p_plaintext, 'sha256'), 'hex');
$$;

comment on function app._hash_vendor_financial_value is 'PRC-254 design note 2: deterministic sha256 hash for duplicate-detection WITHOUT decryption -- the ONLY column ever indexed/compared for equality. The encrypted column itself is never indexed or queried for equality.';

create function app._last4_vendor_financial_value(p_plaintext text)
returns text
language sql
as $$
  select right(regexp_replace(coalesce(p_plaintext, ''), '\s', '', 'g'), 4);
$$;

comment on function app._last4_vendor_financial_value is 'PRC-254 design note 3: plain, unencrypted last-4 masked-display convention -- what every PRC:View-only caller sees by default. Whitespace stripped first so a formatted account number ("1234 5678 9012") still yields the true last 4 significant characters.';

-- ===========================================================================
-- 2. app.vendor_bank_accounts (design notes 5, 6, 12).
-- ===========================================================================

create table app.vendor_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  account_family_id uuid not null default gen_random_uuid(),
  account_holder_name text not null,
  bank_name text not null,
  account_number_encrypted bytea not null,
  account_number_hash text not null,
  account_number_last4 text not null,
  currency text not null,
  purpose text not null default 'primary',
  status text not null default 'draft',
  effective_from date,
  evidence_file_id uuid references app.files (id),
  supersedes_account_id uuid references app.vendor_bank_accounts (id),
  proposed_by text,
  proposed_by_auth_user_id uuid not null,
  approved_by text,
  approved_by_auth_user_id uuid,
  reauth_confirmed_at timestamptz,
  rejection_reason text,
  hold_reason text,
  hold_by_auth_user_id uuid,
  deactivation_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_bank_accounts_holder_name_check check (length(trim(account_holder_name)) > 0),
  constraint vendor_bank_accounts_bank_name_check check (length(trim(bank_name)) > 0),
  constraint vendor_bank_accounts_last4_check check (length(account_number_last4) between 0 and 4),
  constraint vendor_bank_accounts_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint vendor_bank_accounts_purpose_check check (purpose in ('primary', 'settlement', 'other')),
  constraint vendor_bank_accounts_status_check check (status in ('draft', 'pending_approval', 'active', 'rejected', 'hold', 'deactivated')),
  constraint vendor_bank_accounts_not_self_supersede check (supersedes_account_id is null or supersedes_account_id <> id),
  constraint vendor_bank_accounts_decision_shape_check check (
    (status in ('draft', 'pending_approval')) or
    (status in ('active', 'rejected', 'hold', 'deactivated') and approved_by is not null and approved_by_auth_user_id is not null and reauth_confirmed_at is not null)
  ),
  -- Defense in depth alongside the RPC-level self_approval_not_allowed block (design
  -- note 7) -- holds even against a hypothetical future direct-table write path.
  constraint vendor_bank_accounts_no_self_approval_check check (approved_by_auth_user_id is null or approved_by_auth_user_id <> proposed_by_auth_user_id),
  constraint vendor_bank_accounts_rejection_reason_check check (status <> 'rejected' or (rejection_reason is not null and length(trim(rejection_reason)) > 0)),
  constraint vendor_bank_accounts_hold_reason_check check (status <> 'hold' or (hold_reason is not null and length(trim(hold_reason)) > 0)),
  constraint vendor_bank_accounts_deactivation_reason_check check (status <> 'deactivated' or (deactivation_reason is not null and length(trim(deactivation_reason)) > 0))
);

comment on table app.vendor_bank_accounts is 'PRC-254: a versioned, maker-checker-gated vendor bank account (draft -> pending_approval -> active/rejected, plus hold/deactivated reachable from active). account_number_encrypted is the ONLY place the true value lives (pgp_sym_encrypt, design note 1); account_number_hash is a deterministic sha256 digest for duplicate detection without decryption (design note 2); account_number_last4 is the plain masked-display value every PRC:View caller sees by default (design note 3). account_family_id survives a decide-time supersede (design note 5), mirroring app.vendor_compliance_requirements.requirement_family_id one layer down.';

create index vendor_bank_accounts_tenant_vendor_idx on app.vendor_bank_accounts (tenant_id, vendor_master_record_id);
create index vendor_bank_accounts_hash_idx on app.vendor_bank_accounts (tenant_id, account_number_hash);
create index vendor_bank_accounts_tenant_status_idx on app.vendor_bank_accounts (tenant_id, status);
create index vendor_bank_accounts_family_idx on app.vendor_bank_accounts (account_family_id);
create unique index vendor_bank_accounts_active_family_unique on app.vendor_bank_accounts (account_family_id) where status = 'active';
create unique index vendor_bank_accounts_active_scope_unique on app.vendor_bank_accounts (vendor_master_record_id, purpose, currency) where status = 'active';
create unique index vendor_bank_accounts_idempotency_key_unique on app.vendor_bank_accounts (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 3. app.vendor_tax_identities (design notes 5, 6, 12) -- mirrors
--    app.vendor_bank_accounts' exact shape one field-set down.
-- ===========================================================================

create table app.vendor_tax_identities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  tax_family_id uuid not null default gen_random_uuid(),
  tax_id_type text not null,
  tax_id_encrypted bytea not null,
  tax_id_hash text not null,
  tax_id_last4 text not null,
  legal_name_on_file text not null,
  status text not null default 'draft',
  effective_from date,
  evidence_file_id uuid references app.files (id),
  supersedes_tax_identity_id uuid references app.vendor_tax_identities (id),
  proposed_by text,
  proposed_by_auth_user_id uuid not null,
  approved_by text,
  approved_by_auth_user_id uuid,
  reauth_confirmed_at timestamptz,
  rejection_reason text,
  hold_reason text,
  hold_by_auth_user_id uuid,
  deactivation_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_tax_identities_type_check check (length(trim(tax_id_type)) > 0),
  constraint vendor_tax_identities_legal_name_check check (length(trim(legal_name_on_file)) > 0),
  constraint vendor_tax_identities_last4_check check (length(tax_id_last4) between 0 and 4),
  constraint vendor_tax_identities_status_check check (status in ('draft', 'pending_approval', 'active', 'rejected', 'hold', 'deactivated')),
  constraint vendor_tax_identities_not_self_supersede check (supersedes_tax_identity_id is null or supersedes_tax_identity_id <> id),
  constraint vendor_tax_identities_decision_shape_check check (
    (status in ('draft', 'pending_approval')) or
    (status in ('active', 'rejected', 'hold', 'deactivated') and approved_by is not null and approved_by_auth_user_id is not null and reauth_confirmed_at is not null)
  ),
  constraint vendor_tax_identities_no_self_approval_check check (approved_by_auth_user_id is null or approved_by_auth_user_id <> proposed_by_auth_user_id),
  constraint vendor_tax_identities_rejection_reason_check check (status <> 'rejected' or (rejection_reason is not null and length(trim(rejection_reason)) > 0)),
  constraint vendor_tax_identities_hold_reason_check check (status <> 'hold' or (hold_reason is not null and length(trim(hold_reason)) > 0)),
  constraint vendor_tax_identities_deactivation_reason_check check (status <> 'deactivated' or (deactivation_reason is not null and length(trim(deactivation_reason)) > 0))
);

comment on table app.vendor_tax_identities is 'PRC-254: mirrors app.vendor_bank_accounts'' exact lifecycle/versioning/encryption shape one field-set down. tax_id_type is free text (RPD-016 forbids guessing statutory tax formats -- no NPWP checksum/format validator is hardcoded here, exactly like FIN-195''s own is_example_fixture convention for tax rules).';

create index vendor_tax_identities_tenant_vendor_idx on app.vendor_tax_identities (tenant_id, vendor_master_record_id);
create index vendor_tax_identities_hash_idx on app.vendor_tax_identities (tenant_id, tax_id_hash);
create index vendor_tax_identities_tenant_status_idx on app.vendor_tax_identities (tenant_id, status);
create index vendor_tax_identities_family_idx on app.vendor_tax_identities (tax_family_id);
create unique index vendor_tax_identities_active_family_unique on app.vendor_tax_identities (tax_family_id) where status = 'active';
create unique index vendor_tax_identities_active_scope_unique on app.vendor_tax_identities (vendor_master_record_id, tax_id_type) where status = 'active';
create unique index vendor_tax_identities_idempotency_key_unique on app.vendor_tax_identities (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 4. app.vendor_payment_term_proposals (design note 10) -- a change-proposal/
--    approval pair over app.vendor_profiles.payment_term_days, never a new
--    master table.
-- ===========================================================================

create table app.vendor_payment_term_proposals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  current_payment_term_days integer,
  proposed_payment_term_days integer not null,
  vendor_profile_expected_version integer not null,
  reason text not null,
  status text not null default 'pending_approval',
  proposed_by text,
  proposed_by_auth_user_id uuid not null,
  approved_by text,
  approved_by_auth_user_id uuid,
  reauth_confirmed_at timestamptz,
  decision_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_payment_term_proposals_reason_check check (length(trim(reason)) > 0),
  constraint vendor_payment_term_proposals_days_check check (proposed_payment_term_days >= 0),
  constraint vendor_payment_term_proposals_status_check check (status in ('pending_approval', 'approved', 'rejected')),
  constraint vendor_payment_term_proposals_no_self_approval_check check (approved_by_auth_user_id is null or approved_by_auth_user_id <> proposed_by_auth_user_id),
  constraint vendor_payment_term_proposals_decision_reason_check check (status <> 'rejected' or (decision_reason is not null and length(trim(decision_reason)) > 0))
);

comment on table app.vendor_payment_term_proposals is 'PRC-254 design note 10: a proposal/approval pair over the plain app.vendor_profiles.payment_term_days integer column PRC-251 already created -- never a new payment-terms master (Prompt 255''s own ADR-0020 reconciliation owns that open decision). vendor_profile_expected_version snapshots the vendor profile''s own record_version at proposal time, guarding the approval-time UPDATE against an unrelated concurrent profile change.';

create index vendor_payment_term_proposals_tenant_vendor_idx on app.vendor_payment_term_proposals (tenant_id, vendor_master_record_id);
create unique index vendor_payment_term_proposals_pending_unique on app.vendor_payment_term_proposals (vendor_master_record_id) where status = 'pending_approval';
create unique index vendor_payment_term_proposals_idempotency_key_unique on app.vendor_payment_term_proposals (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 5. Editable-precondition helpers (mirrors app.assert_vendor_compliance_
--    requirement_editable exactly, design note 14's own `for update` discipline).
-- ===========================================================================

create function app.assert_vendor_bank_account_editable(p_account_id uuid, p_actor_auth_user_id uuid, out v_account app.vendor_bank_accounts)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'vendor_bank_account_not_draft: bank account % is % -- it may only be edited while draft', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;
end;
$$;

create function app.assert_vendor_tax_identity_editable(p_tax_identity_id uuid, p_actor_auth_user_id uuid, out v_tax_identity app.vendor_tax_identities)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.status <> 'draft' then
    raise exception 'vendor_tax_identity_not_draft: tax identity % is % -- it may only be edited while draft', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;
end;
$$;

-- ===========================================================================
-- 6. Bank account lifecycle RPCs.
-- ===========================================================================

create function app.create_vendor_bank_account_draft(
  p_vendor_master_record_id uuid,
  p_account_holder_name text,
  p_bank_name text,
  p_account_number text,
  p_currency text,
  p_purpose text,
  p_effective_from date,
  p_evidence_file_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_file app.files;
  v_existing app.vendor_bank_accounts;
  v_account app.vendor_bank_accounts;
  v_hash text;
  v_last4 text;
  v_encrypted bytea;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_account_holder_name is null or length(trim(p_account_holder_name)) = 0 then
    raise exception 'invalid_account_holder_name: account_holder_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_bank_name is null or length(trim(p_bank_name)) = 0 then
    raise exception 'invalid_bank_name: bank_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_account_number is null or length(regexp_replace(p_account_number, '\s', '', 'g')) < 4 then
    raise exception 'invalid_account_number: account_number must have at least 4 significant characters' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;
  if coalesce(p_purpose, 'primary') not in ('primary', 'settlement', 'other') then
    raise exception 'invalid_purpose: % is not primary, settlement, or other', p_purpose using errcode = 'check_violation';
  end if;

  -- Evidence re-validation (design note 8, mandatory pattern): re-fetch and reject on
  -- tenant mismatch, wrong record scope, or a non-clean malware scan.
  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_vendor.tenant_id or v_file.record_type <> 'vendor_financial_verification' or v_file.record_id <> p_vendor_master_record_id then
      raise exception 'financial_evidence_file_mismatch: file % was not uploaded for vendor %''s own financial verification purpose in tenant %', p_evidence_file_id, p_vendor_master_record_id, v_vendor.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'financial_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be attached', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Encrypt/hash/last4 (design notes 1-3) -- computed once, never re-derived from a
  -- decrypt in this function.
  v_hash := app._hash_vendor_financial_value(p_account_number);
  v_last4 := app._last4_vendor_financial_value(p_account_number);
  v_encrypted := app._encrypt_vendor_financial_value(p_account_number);

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_bank_accounts where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.account_holder_name is distinct from p_account_holder_name
        or v_existing.bank_name is distinct from p_bank_name or v_existing.account_number_hash is distinct from v_hash
        or v_existing.currency is distinct from p_currency or v_existing.purpose is distinct from coalesce(p_purpose, 'primary')
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different bank account proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_bank_accounts (
      tenant_id, vendor_master_record_id, account_holder_name, bank_name, account_number_encrypted, account_number_hash,
      account_number_last4, currency, purpose, effective_from, evidence_file_id, proposed_by, proposed_by_auth_user_id,
      idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_account_holder_name, p_bank_name, v_encrypted, v_hash,
      v_last4, p_currency, coalesce(p_purpose, 'primary'), p_effective_from, p_evidence_file_id, p_actor_label, p_actor_auth_user_id,
      p_idempotency_key, p_actor_label
    )
    returning * into v_account;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_bank_accounts where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.account_holder_name is distinct from p_account_holder_name
        or v_existing.bank_name is distinct from p_bank_name or v_existing.account_number_hash is distinct from v_hash
        or v_existing.currency is distinct from p_currency or v_existing.purpose is distinct from coalesce(p_purpose, 'primary')
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different bank account proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  -- Design note 9: never to_jsonb(row) -- would serialize account_number_encrypted.
  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_bank_account_draft',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null,
    jsonb_build_object('account_holder_name', v_account.account_holder_name, 'institution_name', v_account.bank_name, 'account_last4', v_account.account_number_last4, 'currency', v_account.currency, 'purpose', v_account.purpose, 'status', v_account.status)
  );

  return v_account;
end;
$$;

create function app.update_vendor_bank_account_draft(
  p_account_id uuid,
  p_expected_version integer,
  p_account_holder_name text,
  p_bank_name text,
  p_account_number text,
  p_currency text,
  p_purpose text,
  p_effective_from date,
  p_evidence_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_account app.vendor_bank_accounts;
  v_file app.files;
  v_hash text;
  v_last4 text;
  v_encrypted bytea;
begin
  v_account := app.assert_vendor_bank_account_editable(p_account_id, p_actor_auth_user_id);

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_account_holder_name is null or length(trim(p_account_holder_name)) = 0 then
    raise exception 'invalid_account_holder_name: account_holder_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_bank_name is null or length(trim(p_bank_name)) = 0 then
    raise exception 'invalid_bank_name: bank_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_account_number is null or length(regexp_replace(p_account_number, '\s', '', 'g')) < 4 then
    raise exception 'invalid_account_number: account_number must have at least 4 significant characters' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;
  if coalesce(p_purpose, 'primary') not in ('primary', 'settlement', 'other') then
    raise exception 'invalid_purpose: % is not primary, settlement, or other', p_purpose using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_account.tenant_id or v_file.record_type <> 'vendor_financial_verification' or v_file.record_id <> v_account.vendor_master_record_id then
      raise exception 'financial_evidence_file_mismatch: file % was not uploaded for vendor %''s own financial verification purpose in tenant %', p_evidence_file_id, v_account.vendor_master_record_id, v_account.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'financial_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be attached', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  v_hash := app._hash_vendor_financial_value(p_account_number);
  v_last4 := app._last4_vendor_financial_value(p_account_number);
  v_encrypted := app._encrypt_vendor_financial_value(p_account_number);

  update app.vendor_bank_accounts
  set account_holder_name = p_account_holder_name, bank_name = p_bank_name, account_number_encrypted = v_encrypted,
      account_number_hash = v_hash, account_number_last4 = v_last4, currency = p_currency, purpose = coalesce(p_purpose, 'primary'),
      effective_from = p_effective_from, evidence_file_id = p_evidence_file_id, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_bank_account_draft',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null,
    jsonb_build_object('account_holder_name', v_account.account_holder_name, 'institution_name', v_account.bank_name, 'account_last4', v_account.account_number_last4, 'currency', v_account.currency, 'purpose', v_account.purpose, 'status', v_account.status)
  );

  return v_account;
end;
$$;

create function app.submit_vendor_bank_account_for_approval(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'draft' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be submitted', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_bank_accounts
  set status = 'pending_approval', updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_bank_account_for_approval',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

-- The privileged checker decision (design notes 5-7: maker-checker + MFA). Self-
-- approval blocked (app.approve_warehouse_billing_event's own exact pattern), a fresh
-- p_reauth_confirmed_at required (app.start_support_session/app.decide_credit_profile_
-- approval_step's own exact pattern), an advisory family lock (design note 14) taken
-- before superseding a prior active row of the same family.
create function app.decide_vendor_bank_account_approval(
  p_account_id uuid,
  p_expected_version integer,
  p_decision text,
  p_supersedes_account_id uuid,
  p_rejection_reason text,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
  v_superseded app.vendor_bank_accounts;
  v_gate text;
  v_family_id uuid;
  v_lock_family_id uuid;
  v_constraint_name text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_rejection_reason is null or length(trim(p_rejection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a bank account proposal' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  -- Maker-checker (design note 7): the same identity that proposed may not decide.
  if v_account.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed bank account % and may not also decide it', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be decided', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  -- Advisory family lock (design note 14) -- serializes this decision against a
  -- bystander hold/reactivate/deactivate acting on a DIFFERENT row (the currently
  -- active one) in the SAME family. Correctness-concurrency fix: when this decision
  -- supersedes a prior active row, the actual contention point is THAT row's family
  -- (v_superseded.account_family_id), never this pending_approval draft's own,
  -- freshly-minted, never-contended account_family_id -- locking on the draft's own
  -- family (the original bug) was dead code for exactly the race this mechanism
  -- exists to close, since no bystander hold/reactivate/deactivate call ever targets
  -- a brand-new draft row. Look up the superseded row's family BEFORE taking the
  -- lock, then re-fetch that row `for update` AFTER the lock is held below (a
  -- concurrent mutation could otherwise change it in the gap between the two reads).
  if p_decision = 'approved' and p_supersedes_account_id is not null then
    select account_family_id into v_lock_family_id from app.vendor_bank_accounts where id = p_supersedes_account_id;
    if v_lock_family_id is null then
      raise exception 'superseded_account_not_found: %', p_supersedes_account_id using errcode = 'no_data_found';
    end if;
  else
    v_lock_family_id := v_account.account_family_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_lock_family_id::text, 101));

  v_family_id := v_account.account_family_id;

  if p_decision = 'approved' and p_supersedes_account_id is not null then
    select * into v_superseded from app.vendor_bank_accounts where id = p_supersedes_account_id for update;
    if not found then
      raise exception 'superseded_account_not_found: %', p_supersedes_account_id using errcode = 'no_data_found';
    end if;
    -- Security-rls Finding 2 fix: the active-scope tuple this supersede mechanism
    -- services is THREE columns (vendor_master_record_id, purpose, currency) --
    -- exactly what vendor_bank_accounts_active_scope_unique enforces. Comparing only
    -- vendor+purpose let an approver supply an unrelated, different-currency active
    -- account as p_supersedes_account_id and silently deactivate it.
    if v_superseded.vendor_master_record_id <> v_account.vendor_master_record_id or v_superseded.purpose <> v_account.purpose or v_superseded.currency <> v_account.currency then
      raise exception 'invalid_supersede: superseded bank account must share the same vendor, purpose and currency' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'active' then
      raise exception 'invalid_supersede: superseded bank account % is % (must be active)', p_supersedes_account_id, v_superseded.status using errcode = 'check_violation';
    end if;

    v_family_id := v_superseded.account_family_id;

    update app.vendor_bank_accounts
    set status = 'deactivated', deactivation_reason = 'superseded_by_approved_change', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_account_id and record_version = v_superseded.record_version and status = 'active';
    if not found then
      raise exception 'stale_version: superseded vendor bank account % was concurrently modified (expected version %)', p_supersedes_account_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_bank_accounts
    set status = case when p_decision = 'approved' then 'active' else 'rejected' end,
        account_family_id = case when p_decision = 'approved' then v_family_id else account_family_id end,
        rejection_reason = case when p_decision = 'rejected' then p_rejection_reason else null end,
        effective_from = case when p_decision = 'approved' then coalesce(effective_from, current_date) else effective_from end,
        approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at,
        updated_at = now(), record_version = record_version + 1
    where id = p_account_id and record_version = p_expected_version
    returning * into v_account;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_bank_accounts_active_scope_unique' then
        raise exception 'active_account_exists: an active bank account already exists for vendor %, purpose %, currency % -- supply p_supersedes_account_id to replace it', v_account.vendor_master_record_id, v_account.purpose, v_account.currency
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_bank_account_approval',
    'app.vendor_bank_accounts', v_account.id, 'success', p_rejection_reason, null,
    jsonb_build_object('decision', p_decision, 'account_last4', v_account.account_number_last4, 'status', v_account.status, 'supersedes_account_id', p_supersedes_account_id)
  );

  return v_account;
end;
$$;

comment on function app.decide_vendor_bank_account_approval is 'PRC-254: PRC:Approve/Reject-gated (case-mapped). Mandatory maker-checker (self_approval_not_allowed) and MFA reauth freshness (design notes 6-7). Approving with p_supersedes_account_id deactivates the prior active row of the same purpose/vendor and carries its account_family_id forward (design note 5), mirroring app.publish_vendor_compliance_requirement''s own supersede-on-decision shape.';

-- spec-compliance Finding 2 fix: hold/reactivate/deactivate now require the same
-- MFA reauth freshness proof as decide/reveal (Sec.24 "No bank change becomes
-- effective without ... privileged current authentication" -- these RPCs mutate the
-- record's own effective, downstream-consumed verification status, exactly the
-- thing Sec.24 protects). reactivate additionally requires a DIFFERENT actor than
-- whoever placed the hold (hold_by_auth_user_id, mirroring self_approval_not_allowed
-- one layer down) -- a single PRC:Override holder must not be able to place a hold
-- and immediately, unilaterally undo it.
create function app.hold_vendor_bank_account(p_account_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to place a bank account on hold' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'active' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be placed on hold', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_account.account_family_id::text, 101));

  update app.vendor_bank_accounts
  set status = 'hold', hold_reason = p_reason, hold_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_vendor_bank_account',
    'app.vendor_bank_accounts', v_account.id, 'success', p_reason, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

create function app.reactivate_vendor_bank_account(p_account_id uuid, p_expected_version integer, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Maker-checker separation: whoever placed this hold may not be the one to lift it.
  if v_account.hold_by_auth_user_id is not null and v_account.hold_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_reactivation_not_allowed: identity % placed bank account % on hold and may not also reactivate it', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status <> 'hold' then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be reactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_account.account_family_id::text, 101));

  update app.vendor_bank_accounts
  set status = 'active', hold_reason = null, hold_by_auth_user_id = null, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_bank_account',
    'app.vendor_bank_accounts', v_account.id, 'success', null, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

create function app.deactivate_vendor_bank_account(p_account_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_bank_accounts
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to deactivate a bank account' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id for update;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: vendor bank account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_account.status not in ('active', 'hold') then
    raise exception 'invalid_transition: vendor bank account % is % and cannot be deactivated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_account.vendor_master_record_id::text || ':' || v_account.account_family_id::text, 101));

  update app.vendor_bank_accounts
  set status = 'deactivated', deactivation_reason = p_reason, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  if not found then
    raise exception 'stale_version: vendor bank account % target row was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_vendor_bank_account',
    'app.vendor_bank_accounts', v_account.id, 'success', p_reason, null, jsonb_build_object('status', v_account.status)
  );

  return v_account;
end;
$$;

-- ===========================================================================
-- 7. Bank account read RPCs (masked default, gated reveal, gated evidence
--    access -- design notes 2, 3, 6, 8).
-- ===========================================================================

create function app.get_vendor_bank_account_masked(p_account_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, account_family_id uuid, account_holder_name text, bank_name text,
  account_number_last4 text, currency text, purpose text, status text, effective_from date, evidence_file_id uuid,
  is_duplicate_candidate boolean, proposed_by text, approved_by text, hold_reason text, rejection_reason text,
  deactivation_reason text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
begin
  -- Table-qualified (not bare `id`) -- this RPC's own RETURNS TABLE declares a
  -- same-named `id` OUT parameter, which Postgres implicitly turns into a plpgsql
  -- variable; an unqualified `where id = ...` here is ambiguous (the exact class of
  -- bug PRC-251's own build log records finding and fixing three times).
  select * into v_account from app.vendor_bank_accounts where app.vendor_bank_accounts.id = p_account_id;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select a.id, a.tenant_id, a.vendor_master_record_id, a.account_family_id, a.account_holder_name, a.bank_name,
    a.account_number_last4, a.currency, a.purpose, a.status, a.effective_from, a.evidence_file_id,
    exists (
      select 1 from app.vendor_bank_accounts d
      where d.tenant_id = a.tenant_id and d.account_number_hash = a.account_number_hash and d.id <> a.id
        and d.vendor_master_record_id <> a.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    a.proposed_by, a.approved_by, a.hold_reason, a.rejection_reason, a.deactivation_reason, a.record_version, a.created_at, a.updated_at
  from app.vendor_bank_accounts a
  where a.id = p_account_id;
end;
$$;

comment on function app.get_vendor_bank_account_masked is 'PRC-254: the default PRC:View read -- last4/status/currency/purpose plus a live hash-based duplicate-candidate flag (design note 2). NEVER selects account_number_encrypted/account_number_hash into the result set.';

create function app.list_vendor_bank_accounts_masked(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100, p_after_id uuid default null
)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, account_family_id uuid, account_holder_name text, bank_name text,
  account_number_last4 text, currency text, purpose text, status text, effective_from date, evidence_file_id uuid,
  is_duplicate_candidate boolean, proposed_by text, approved_by text, hold_reason text, rejection_reason text,
  deactivation_reason text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'pending_approval', 'active', 'rejected', 'hold', 'deactivated') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select a.id, a.tenant_id, a.vendor_master_record_id, a.account_family_id, a.account_holder_name, a.bank_name,
    a.account_number_last4, a.currency, a.purpose, a.status, a.effective_from, a.evidence_file_id,
    exists (
      select 1 from app.vendor_bank_accounts d
      where d.tenant_id = a.tenant_id and d.account_number_hash = a.account_number_hash and d.id <> a.id
        and d.vendor_master_record_id <> a.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    a.proposed_by, a.approved_by, a.hold_reason, a.rejection_reason, a.deactivation_reason, a.record_version, a.created_at, a.updated_at
  from app.vendor_bank_accounts a
  where a.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or a.status = p_status_filter)
    and (p_after_id is null or a.id > p_after_id)
  order by a.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

-- The privileged, purpose-bound, MFA-gated, unconditionally-audited reveal (design
-- note 6). This is the ONLY RPC that ever returns a decrypted bank account number.
create function app.reveal_vendor_bank_account_number(
  p_account_id uuid, p_reveal_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (account_number text, account_holder_name text, bank_name text, currency text, purpose text, status text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_account app.vendor_bank_accounts;
  v_plaintext text;
begin
  if p_reveal_reason is null or length(trim(p_reveal_reason)) = 0 then
    raise exception 'reveal_reason_required: a non-empty, purpose-bound reason is required to reveal a bank account number' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if not app.has_prc_view_personal_data(v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View personal data for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_plaintext := app._decrypt_vendor_financial_value(v_account.account_number_encrypted);

  -- Design notes 6, 9: the audit row NEVER carries the plaintext or the ciphertext --
  -- only the fact of the reveal, the reveal reason, and the already-public last4 form.
  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'reveal_vendor_bank_account_number',
    'app.vendor_bank_accounts', v_account.id, 'success', p_reveal_reason, null,
    jsonb_build_object('account_last4', v_account.account_number_last4, 'reveal_reason', p_reveal_reason),
    p_correlation_id
  );

  return query select v_plaintext, v_account.account_holder_name, v_account.bank_name, v_account.currency, v_account.purpose, v_account.status;
end;
$$;

comment on function app.reveal_vendor_bank_account_number is 'PRC-254 design note 6: the ONLY path that ever decrypts app.vendor_bank_accounts.account_number_encrypted. Gated on app.has_prc_view_personal_data (reused from PRC-251, never duplicated), a non-empty purpose-bound reveal reason, and MFA reauth freshness. Every successful call is unconditionally audited -- never a silent decrypt.';

-- Evidence/version viewer (design note 8, applied proactively -- PRC-253's own
-- adversarial review found "reviewers verified evidence blind" as a CONFIRMED HIGH
-- finding; not repeated here). Mirrors app.access_vendor_compliance_document_evidence
-- exactly one layer down.
create function app.access_vendor_bank_account_evidence(p_account_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
  v_file app.files;
  v_log app.file_access_logs;
begin
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  -- Security-rls Finding 1 fix: the authority gate MUST run before the
  -- evidence_file_id-is-null check. Checking evidence existence first let any
  -- authenticated caller of ANY tenant -- zero PRC grant required -- distinguish
  -- `no_evidence_attached` from `insufficient_authority` for a bank account UUID
  -- they can merely guess/obtain, an unaudited cross-tenant existence oracle.
  -- Denied here, the caller now gets an identical, audited `denied` result
  -- regardless of whether evidence is attached -- file_id is deliberately nulled
  -- out below so a denied response never itself reveals record state.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    perform app.capture_audit_event(
      v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_bank_account_evidence',
      'app.vendor_bank_accounts', v_account.id, 'failure', v_decision.reason, null,
      jsonb_build_object('access_type', p_access_type, 'result', 'denied', 'gate', 'insufficient_authority'),
      p_correlation_id
    );
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, 'denied'::text, ('insufficient_authority: ' || coalesce(v_decision.reason, ''))::text;
    return;
  end if;

  if v_account.evidence_file_id is null then
    raise exception 'no_evidence_attached: bank account % has no evidence file attached', p_account_id using errcode = 'no_data_found';
  end if;

  v_log := app.authorize_file_access(v_account.evidence_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_bank_account_evidence',
    'app.vendor_bank_accounts', v_account.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select v_account.evidence_file_id, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_account.evidence_file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;

-- ===========================================================================
-- 8. Tax identity lifecycle RPCs -- mirrors section 6 exactly one field-set
--    down.
-- ===========================================================================

create function app.create_vendor_tax_identity_draft(
  p_vendor_master_record_id uuid,
  p_tax_id_type text,
  p_tax_id text,
  p_legal_name_on_file text,
  p_effective_from date,
  p_evidence_file_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_file app.files;
  v_existing app.vendor_tax_identities;
  v_tax_identity app.vendor_tax_identities;
  v_hash text;
  v_last4 text;
  v_encrypted bytea;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_tax_id_type is null or length(trim(p_tax_id_type)) = 0 then
    raise exception 'invalid_tax_id_type: tax_id_type must not be empty' using errcode = 'check_violation';
  end if;
  if p_legal_name_on_file is null or length(trim(p_legal_name_on_file)) = 0 then
    raise exception 'invalid_legal_name: legal_name_on_file must not be empty' using errcode = 'check_violation';
  end if;
  if p_tax_id is null or length(regexp_replace(p_tax_id, '\s', '', 'g')) < 4 then
    raise exception 'invalid_tax_id: tax_id must have at least 4 significant characters' using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_vendor.tenant_id or v_file.record_type <> 'vendor_financial_verification' or v_file.record_id <> p_vendor_master_record_id then
      raise exception 'financial_evidence_file_mismatch: file % was not uploaded for vendor %''s own financial verification purpose in tenant %', p_evidence_file_id, p_vendor_master_record_id, v_vendor.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'financial_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be attached', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  v_hash := app._hash_vendor_financial_value(p_tax_id);
  v_last4 := app._last4_vendor_financial_value(p_tax_id);
  v_encrypted := app._encrypt_vendor_financial_value(p_tax_id);

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_tax_identities where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.tax_id_type is distinct from p_tax_id_type
        or v_existing.tax_id_hash is distinct from v_hash or v_existing.legal_name_on_file is distinct from p_legal_name_on_file
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different tax identity proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_tax_identities (
      tenant_id, vendor_master_record_id, tax_id_type, tax_id_encrypted, tax_id_hash, tax_id_last4, legal_name_on_file,
      effective_from, evidence_file_id, proposed_by, proposed_by_auth_user_id, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_tax_id_type, v_encrypted, v_hash, v_last4, p_legal_name_on_file,
      p_effective_from, p_evidence_file_id, p_actor_label, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_tax_identity;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_tax_identities where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.tax_id_type is distinct from p_tax_id_type
        or v_existing.tax_id_hash is distinct from v_hash or v_existing.legal_name_on_file is distinct from p_legal_name_on_file
        or v_existing.effective_from is distinct from p_effective_from or v_existing.evidence_file_id is distinct from p_evidence_file_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different tax identity proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_tax_identity_draft',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null,
    jsonb_build_object('tax_id_type', v_tax_identity.tax_id_type, 'tax_id_last4', v_tax_identity.tax_id_last4, 'legal_name_on_file', v_tax_identity.legal_name_on_file, 'status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create function app.update_vendor_tax_identity_draft(
  p_tax_identity_id uuid,
  p_expected_version integer,
  p_tax_id_type text,
  p_tax_id text,
  p_legal_name_on_file text,
  p_effective_from date,
  p_evidence_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_tax_identity app.vendor_tax_identities;
  v_file app.files;
  v_hash text;
  v_last4 text;
  v_encrypted bytea;
begin
  v_tax_identity := app.assert_vendor_tax_identity_editable(p_tax_identity_id, p_actor_auth_user_id);

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_tax_id_type is null or length(trim(p_tax_id_type)) = 0 then
    raise exception 'invalid_tax_id_type: tax_id_type must not be empty' using errcode = 'check_violation';
  end if;
  if p_legal_name_on_file is null or length(trim(p_legal_name_on_file)) = 0 then
    raise exception 'invalid_legal_name: legal_name_on_file must not be empty' using errcode = 'check_violation';
  end if;
  if p_tax_id is null or length(regexp_replace(p_tax_id, '\s', '', 'g')) < 4 then
    raise exception 'invalid_tax_id: tax_id must have at least 4 significant characters' using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_tax_identity.tenant_id or v_file.record_type <> 'vendor_financial_verification' or v_file.record_id <> v_tax_identity.vendor_master_record_id then
      raise exception 'financial_evidence_file_mismatch: file % was not uploaded for vendor %''s own financial verification purpose in tenant %', p_evidence_file_id, v_tax_identity.vendor_master_record_id, v_tax_identity.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'financial_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be attached', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  v_hash := app._hash_vendor_financial_value(p_tax_id);
  v_last4 := app._last4_vendor_financial_value(p_tax_id);
  v_encrypted := app._encrypt_vendor_financial_value(p_tax_id);

  update app.vendor_tax_identities
  set tax_id_type = p_tax_id_type, tax_id_encrypted = v_encrypted, tax_id_hash = v_hash, tax_id_last4 = v_last4,
      legal_name_on_file = p_legal_name_on_file, effective_from = p_effective_from, evidence_file_id = p_evidence_file_id,
      updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_tax_identity_draft',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null,
    jsonb_build_object('tax_id_type', v_tax_identity.tax_id_type, 'tax_id_last4', v_tax_identity.tax_id_last4, 'legal_name_on_file', v_tax_identity.legal_name_on_file, 'status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create function app.submit_vendor_tax_identity_for_approval(p_tax_identity_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'draft' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be submitted', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_tax_identities
  set status = 'pending_approval', updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_tax_identity_for_approval',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create function app.decide_vendor_tax_identity_approval(
  p_tax_identity_id uuid,
  p_expected_version integer,
  p_decision text,
  p_supersedes_tax_identity_id uuid,
  p_rejection_reason text,
  p_reauth_confirmed_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
  v_superseded app.vendor_tax_identities;
  v_gate text;
  v_family_id uuid;
  v_lock_family_id uuid;
  v_constraint_name text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_rejection_reason is null or length(trim(p_rejection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a tax identity proposal' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  if v_tax_identity.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed tax identity % and may not also decide it', p_actor_auth_user_id, p_tax_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be decided', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  -- Correctness-concurrency fix (mirrors the bank-account decide RPC's own fix
  -- immediately above): lock on the SUPERSEDED row's family when superseding, never
  -- this pending_approval draft's own freshly-minted family.
  if p_decision = 'approved' and p_supersedes_tax_identity_id is not null then
    select tax_family_id into v_lock_family_id from app.vendor_tax_identities where id = p_supersedes_tax_identity_id;
    if v_lock_family_id is null then
      raise exception 'superseded_tax_identity_not_found: %', p_supersedes_tax_identity_id using errcode = 'no_data_found';
    end if;
  else
    v_lock_family_id := v_tax_identity.tax_family_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_lock_family_id::text, 102));

  v_family_id := v_tax_identity.tax_family_id;

  if p_decision = 'approved' and p_supersedes_tax_identity_id is not null then
    select * into v_superseded from app.vendor_tax_identities where id = p_supersedes_tax_identity_id for update;
    if not found then
      raise exception 'superseded_tax_identity_not_found: %', p_supersedes_tax_identity_id using errcode = 'no_data_found';
    end if;
    if v_superseded.vendor_master_record_id <> v_tax_identity.vendor_master_record_id or v_superseded.tax_id_type <> v_tax_identity.tax_id_type then
      raise exception 'invalid_supersede: superseded tax identity must share the same vendor and tax_id_type' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'active' then
      raise exception 'invalid_supersede: superseded tax identity % is % (must be active)', p_supersedes_tax_identity_id, v_superseded.status using errcode = 'check_violation';
    end if;

    v_family_id := v_superseded.tax_family_id;

    update app.vendor_tax_identities
    set status = 'deactivated', deactivation_reason = 'superseded_by_approved_change', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_tax_identity_id and record_version = v_superseded.record_version and status = 'active';
    if not found then
      raise exception 'stale_version: superseded vendor tax identity % was concurrently modified (expected version %)', p_supersedes_tax_identity_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_tax_identities
    set status = case when p_decision = 'approved' then 'active' else 'rejected' end,
        tax_family_id = case when p_decision = 'approved' then v_family_id else tax_family_id end,
        rejection_reason = case when p_decision = 'rejected' then p_rejection_reason else null end,
        effective_from = case when p_decision = 'approved' then coalesce(effective_from, current_date) else effective_from end,
        approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at,
        updated_at = now(), record_version = record_version + 1
    where id = p_tax_identity_id and record_version = p_expected_version
    returning * into v_tax_identity;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_tax_identities_active_scope_unique' then
        raise exception 'active_tax_identity_exists: an active tax identity already exists for vendor %, type % -- supply p_supersedes_tax_identity_id to replace it', v_tax_identity.vendor_master_record_id, v_tax_identity.tax_id_type
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_tax_identity_approval',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_rejection_reason, null,
    jsonb_build_object('decision', p_decision, 'tax_id_last4', v_tax_identity.tax_id_last4, 'status', v_tax_identity.status, 'supersedes_tax_identity_id', p_supersedes_tax_identity_id)
  );

  return v_tax_identity;
end;
$$;

-- spec-compliance Finding 2 fix, mirrored one field-set down (see the bank-account
-- trio's own comment immediately above for the full rationale).
create function app.hold_vendor_tax_identity(p_tax_identity_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to place a tax identity on hold' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'active' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be placed on hold', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_tax_identity.tax_family_id::text, 102));

  update app.vendor_tax_identities
  set status = 'hold', hold_reason = p_reason, hold_by_auth_user_id = p_actor_auth_user_id, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_vendor_tax_identity',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_reason, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create function app.reactivate_vendor_tax_identity(p_tax_identity_id uuid, p_expected_version integer, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.hold_by_auth_user_id is not null and v_tax_identity.hold_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_reactivation_not_allowed: identity % placed tax identity % on hold and may not also reactivate it', p_actor_auth_user_id, p_tax_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status <> 'hold' then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be reactivated', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_tax_identity.tax_family_id::text, 102));

  update app.vendor_tax_identities
  set status = 'active', hold_reason = null, hold_by_auth_user_id = null, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_tax_identity',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', null, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

create function app.deactivate_vendor_tax_identity(p_tax_identity_id uuid, p_expected_version integer, p_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_tax_identities
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to deactivate a tax identity' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id for update;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_tax_identity.record_version <> p_expected_version then
    raise exception 'stale_version: vendor tax identity % expected version % but found %', p_tax_identity_id, p_expected_version, v_tax_identity.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_tax_identity.status not in ('active', 'hold') then
    raise exception 'invalid_transition: vendor tax identity % is % and cannot be deactivated', p_tax_identity_id, v_tax_identity.status
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tax_identity.vendor_master_record_id::text || ':' || v_tax_identity.tax_family_id::text, 102));

  update app.vendor_tax_identities
  set status = 'deactivated', deactivation_reason = p_reason, reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_tax_identity_id and record_version = p_expected_version
  returning * into v_tax_identity;
  if not found then
    raise exception 'stale_version: vendor tax identity % target row was concurrently modified (expected version %)', p_tax_identity_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_vendor_tax_identity',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_reason, null, jsonb_build_object('status', v_tax_identity.status)
  );

  return v_tax_identity;
end;
$$;

-- ===========================================================================
-- 9. Tax identity read RPCs -- mirrors section 7 exactly.
-- ===========================================================================

create function app.get_vendor_tax_identity_masked(p_tax_identity_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, tax_family_id uuid, tax_id_type text, tax_id_last4 text,
  legal_name_on_file text, status text, effective_from date, evidence_file_id uuid, is_duplicate_candidate boolean,
  proposed_by text, approved_by text, hold_reason text, rejection_reason text, deactivation_reason text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
begin
  -- Table-qualified -- see the identical comment on app.get_vendor_bank_account_masked.
  select * into v_tax_identity from app.vendor_tax_identities where app.vendor_tax_identities.id = p_tax_identity_id;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select t.id, t.tenant_id, t.vendor_master_record_id, t.tax_family_id, t.tax_id_type, t.tax_id_last4, t.legal_name_on_file,
    t.status, t.effective_from, t.evidence_file_id,
    exists (
      select 1 from app.vendor_tax_identities d
      where d.tenant_id = t.tenant_id and d.tax_id_hash = t.tax_id_hash and d.id <> t.id
        and d.vendor_master_record_id <> t.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    t.proposed_by, t.approved_by, t.hold_reason, t.rejection_reason, t.deactivation_reason, t.record_version, t.created_at, t.updated_at
  from app.vendor_tax_identities t
  where t.id = p_tax_identity_id;
end;
$$;

create function app.list_vendor_tax_identities_masked(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100, p_after_id uuid default null
)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, tax_family_id uuid, tax_id_type text, tax_id_last4 text,
  legal_name_on_file text, status text, effective_from date, evidence_file_id uuid, is_duplicate_candidate boolean,
  proposed_by text, approved_by text, hold_reason text, rejection_reason text, deactivation_reason text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'pending_approval', 'active', 'rejected', 'hold', 'deactivated') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select t.id, t.tenant_id, t.vendor_master_record_id, t.tax_family_id, t.tax_id_type, t.tax_id_last4, t.legal_name_on_file,
    t.status, t.effective_from, t.evidence_file_id,
    exists (
      select 1 from app.vendor_tax_identities d
      where d.tenant_id = t.tenant_id and d.tax_id_hash = t.tax_id_hash and d.id <> t.id
        and d.vendor_master_record_id <> t.vendor_master_record_id and d.status in ('active', 'pending_approval')
    ) as is_duplicate_candidate,
    t.proposed_by, t.approved_by, t.hold_reason, t.rejection_reason, t.deactivation_reason, t.record_version, t.created_at, t.updated_at
  from app.vendor_tax_identities t
  where t.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or t.status = p_status_filter)
    and (p_after_id is null or t.id > p_after_id)
  order by t.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

create function app.reveal_vendor_tax_identity_number(
  p_tax_identity_id uuid, p_reveal_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (tax_id text, tax_id_type text, legal_name_on_file text, status text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_tax_identity app.vendor_tax_identities;
  v_plaintext text;
begin
  if p_reveal_reason is null or length(trim(p_reveal_reason)) = 0 then
    raise exception 'reveal_reason_required: a non-empty, purpose-bound reason is required to reveal a tax identity' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  if not app.has_prc_view_personal_data(v_tax_identity.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:View personal data for tenant %', p_actor_auth_user_id, v_tax_identity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_plaintext := app._decrypt_vendor_financial_value(v_tax_identity.tax_id_encrypted);

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reveal_vendor_tax_identity_number',
    'app.vendor_tax_identities', v_tax_identity.id, 'success', p_reveal_reason, null,
    jsonb_build_object('tax_id_last4', v_tax_identity.tax_id_last4, 'reveal_reason', p_reveal_reason),
    p_correlation_id
  );

  return query select v_plaintext, v_tax_identity.tax_id_type, v_tax_identity.legal_name_on_file, v_tax_identity.status;
end;
$$;

create function app.access_vendor_tax_identity_evidence(p_tax_identity_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
  v_file app.files;
  v_log app.file_access_logs;
begin
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  -- Security-rls Finding 1 fix (mirrors the bank-account evidence RPC's own fix
  -- immediately above): authority gate before the evidence_file_id-is-null oracle,
  -- audited-and-nulled-out denial instead of an un-audited raise.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    perform app.capture_audit_event(
      v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_tax_identity_evidence',
      'app.vendor_tax_identities', v_tax_identity.id, 'failure', v_decision.reason, null,
      jsonb_build_object('access_type', p_access_type, 'result', 'denied', 'gate', 'insufficient_authority'),
      p_correlation_id
    );
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, 'denied'::text, ('insufficient_authority: ' || coalesce(v_decision.reason, ''))::text;
    return;
  end if;

  if v_tax_identity.evidence_file_id is null then
    raise exception 'no_evidence_attached: tax identity % has no evidence file attached', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_log := app.authorize_file_access(v_tax_identity.evidence_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_tax_identity_evidence',
    'app.vendor_tax_identities', v_tax_identity.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select v_tax_identity.evidence_file_id, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_tax_identity.evidence_file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;

-- ===========================================================================
-- 10. Payment-term change proposal/approval (design note 10).
-- ===========================================================================

create function app.propose_vendor_payment_term_change(
  p_vendor_master_record_id uuid, p_proposed_payment_term_days integer, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_payment_term_proposals;
  v_proposal app.vendor_payment_term_proposals;
  v_constraint_name text;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_proposed_payment_term_days is null or p_proposed_payment_term_days < 0 then
    raise exception 'invalid_payment_term_days: proposed_payment_term_days must be >= 0' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to propose a payment-term change' using errcode = 'check_violation';
  end if;
  if p_proposed_payment_term_days = v_vendor.payment_term_days then
    raise exception 'no_op_proposal: proposed_payment_term_days % matches the vendor''s current payment_term_days', p_proposed_payment_term_days using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_payment_term_proposals where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.proposed_payment_term_days is distinct from p_proposed_payment_term_days then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different payment-term proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_payment_term_proposals (
      tenant_id, vendor_master_record_id, current_payment_term_days, proposed_payment_term_days, vendor_profile_expected_version,
      reason, proposed_by, proposed_by_auth_user_id, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, v_vendor.payment_term_days, p_proposed_payment_term_days, v_vendor.record_version,
      p_reason, p_actor_label, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_proposal;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_payment_term_proposals_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_payment_term_proposals where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.proposed_payment_term_days is distinct from p_proposed_payment_term_days then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different payment-term proposal', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_payment_term_proposals_pending_unique' then
        raise exception 'pending_proposal_exists: vendor % already has a pending payment-term proposal -- decide it before proposing another', p_vendor_master_record_id
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_vendor_payment_term_change',
    'app.vendor_payment_term_proposals', v_proposal.id, 'success', p_reason, null, to_jsonb(v_proposal)
  );

  return v_proposal;
end;
$$;

create function app.decide_vendor_payment_term_change_proposal(
  p_proposal_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_reauth_confirmed_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_proposal app.vendor_payment_term_proposals;
  v_vendor app.vendor_profiles;
  v_gate text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a payment-term proposal' using errcode = 'check_violation';
  end if;
  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_proposal from app.vendor_payment_term_proposals where id = p_proposal_id for update;
  if not found then
    raise exception 'vendor_payment_term_proposal_not_found: %', p_proposal_id using errcode = 'no_data_found';
  end if;

  if v_proposal.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed payment-term change % and may not also decide it', p_actor_auth_user_id, p_proposal_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_proposal.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_proposal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_proposal.record_version <> p_expected_version then
    raise exception 'stale_version: payment-term proposal % expected version % but found %', p_proposal_id, p_expected_version, v_proposal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_proposal.status <> 'pending_approval' then
    raise exception 'invalid_transition: payment-term proposal % is % and cannot be decided', p_proposal_id, v_proposal.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    select * into v_vendor from app.vendor_profiles where master_record_id = v_proposal.vendor_master_record_id for update;
    if v_vendor.record_version <> v_proposal.vendor_profile_expected_version then
      raise exception 'vendor_profile_changed_since_proposal: vendor % profile changed since this proposal was made (expected version %, found %) -- reject and re-propose', v_proposal.vendor_master_record_id, v_proposal.vendor_profile_expected_version, v_vendor.record_version
        using errcode = 'serialization_failure';
    end if;

    update app.vendor_profiles
    set payment_term_days = v_proposal.proposed_payment_term_days, updated_at = now(), record_version = record_version + 1
    where master_record_id = v_proposal.vendor_master_record_id and record_version = v_proposal.vendor_profile_expected_version;
    if not found then
      raise exception 'stale_version: vendor profile % was concurrently modified (expected version %)', v_proposal.vendor_master_record_id, v_proposal.vendor_profile_expected_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  update app.vendor_payment_term_proposals
  set status = case when p_decision = 'approved' then 'approved' else 'rejected' end,
      decision_reason = p_decision_reason, approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id,
      reauth_confirmed_at = p_reauth_confirmed_at, updated_at = now(), record_version = record_version + 1
  where id = p_proposal_id and record_version = p_expected_version
  returning * into v_proposal;
  if not found then
    raise exception 'stale_version: payment-term proposal % target row was concurrently modified (expected version %)', p_proposal_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_proposal.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_payment_term_change_proposal',
    'app.vendor_payment_term_proposals', v_proposal.id, 'success', p_decision_reason, null, to_jsonb(v_proposal)
  );

  return v_proposal;
end;
$$;

comment on function app.decide_vendor_payment_term_change_proposal is 'PRC-254 design note 10: PRC:Approve/Reject-gated, mandatory maker-checker + MFA reauth (design notes 6-7, applied uniformly here too). Approving guards the app.vendor_profiles.payment_term_days UPDATE with the vendor profile''s own record_version, snapshotted at proposal time -- an unrelated concurrent profile change surfaces vendor_profile_changed_since_proposal rather than silently overwriting it.';

create function app.get_vendor_payment_term_proposal(p_proposal_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_proposal app.vendor_payment_term_proposals;
begin
  select * into v_proposal from app.vendor_payment_term_proposals where id = p_proposal_id;
  if not found then
    raise exception 'vendor_payment_term_proposal_not_found: %', p_proposal_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_proposal.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_proposal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_proposal;
end;
$$;

create function app.list_vendor_payment_term_proposals(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 100, p_after_id uuid default null
)
returns setof app.vendor_payment_term_proposals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('pending_approval', 'approved', 'rejected') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select p.* from app.vendor_payment_term_proposals p
  where p.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or p.status = p_status_filter)
    and (p_after_id is null or p.id > p_after_id)
  order by p.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

-- ===========================================================================
-- 11. Downstream read (design note 11) -- the single real, tested composition
--     point Prompts 256+/Finance/Sourcing/PO/invoice-matching read against.
-- ===========================================================================

create function app.get_vendor_financial_verification_status(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (vendor_master_record_id uuid, has_verified_bank_account boolean, has_verified_tax_identity boolean, on_hold boolean, computed_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    p_vendor_master_record_id,
    exists (select 1 from app.vendor_bank_accounts a where a.vendor_master_record_id = p_vendor_master_record_id and a.status = 'active'),
    exists (select 1 from app.vendor_tax_identities t where t.vendor_master_record_id = p_vendor_master_record_id and t.status = 'active'),
    exists (select 1 from app.vendor_bank_accounts a where a.vendor_master_record_id = p_vendor_master_record_id and a.status = 'hold')
      or exists (select 1 from app.vendor_tax_identities t where t.vendor_master_record_id = p_vendor_master_record_id and t.status = 'hold'),
    now();
end;
$$;

comment on function app.get_vendor_financial_verification_status is 'PRC-254 design note 11: the ONE downstream-composable read this capability exposes -- verified bank account exists / verified tax identity exists / on hold, nothing more. Never writes to any app.finance_* table, never mutates app.vendor_profiles.lifecycle_status, never executes or simulates settlement (RPD-038, Sec.24).';

-- ===========================================================================
-- 12. RLS -- default-deny row policy (design note 12's own "two layers" note --
--     see grants below for the column-level layer).
-- ===========================================================================

alter table app.vendor_bank_accounts enable row level security;
alter table app.vendor_tax_identities enable row level security;
alter table app.vendor_payment_term_proposals enable row level security;

create policy vendor_bank_accounts_select_scoped on app.vendor_bank_accounts
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_tax_identities_select_scoped on app.vendor_tax_identities
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_payment_term_proposals_select_scoped on app.vendor_payment_term_proposals
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 13. Grants (design notes 12, 15, ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

-- Column-restricted grants (design note 12) -- the database guarantee (COM-149's own
-- proven technique): a bare column-level REVOKE cannot carve an exception out of a
-- broader table-level GRANT, so the table-level grant is never issued to authenticated
-- at all -- only this explicit column list, which OMITS account_number_encrypted/
-- account_number_hash/tax_id_encrypted/tax_id_hash. service_role (used exclusively by
-- this migration's own SECURITY DEFINER functions internally) gets the full grant.
grant select (
  id, tenant_id, vendor_master_record_id, account_family_id, account_holder_name, bank_name,
  account_number_last4, currency, purpose, status, effective_from, evidence_file_id, supersedes_account_id,
  proposed_by, proposed_by_auth_user_id, approved_by, approved_by_auth_user_id, reauth_confirmed_at,
  rejection_reason, hold_reason, hold_by_auth_user_id, deactivation_reason, idempotency_key, record_version, created_by, created_at, updated_at
) on app.vendor_bank_accounts to authenticated;
grant select on app.vendor_bank_accounts to service_role;

grant select (
  id, tenant_id, vendor_master_record_id, tax_family_id, tax_id_type, tax_id_last4, legal_name_on_file,
  status, effective_from, evidence_file_id, supersedes_tax_identity_id, proposed_by, proposed_by_auth_user_id,
  approved_by, approved_by_auth_user_id, reauth_confirmed_at, rejection_reason, hold_reason, hold_by_auth_user_id, deactivation_reason,
  idempotency_key, record_version, created_by, created_at, updated_at
) on app.vendor_tax_identities to authenticated;
grant select on app.vendor_tax_identities to service_role;

grant select on app.vendor_payment_term_proposals to authenticated, service_role;

grant execute on function app.create_vendor_bank_account_draft(uuid, text, text, text, text, text, date, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_bank_account_draft(uuid, integer, text, text, text, text, text, date, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.submit_vendor_bank_account_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_bank_account_approval(uuid, integer, text, uuid, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.hold_vendor_bank_account(uuid, integer, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.reactivate_vendor_bank_account(uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.deactivate_vendor_bank_account(uuid, integer, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_bank_account_masked(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_bank_accounts_masked(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.reveal_vendor_bank_account_number(uuid, text, timestamptz, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.access_vendor_bank_account_evidence(uuid, text, uuid, text, uuid) to authenticated, service_role;

grant execute on function app.create_vendor_tax_identity_draft(uuid, text, text, text, date, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_tax_identity_draft(uuid, integer, text, text, text, date, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.submit_vendor_tax_identity_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_tax_identity_approval(uuid, integer, text, uuid, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.hold_vendor_tax_identity(uuid, integer, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.reactivate_vendor_tax_identity(uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.deactivate_vendor_tax_identity(uuid, integer, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_tax_identity_masked(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_tax_identities_masked(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.reveal_vendor_tax_identity_number(uuid, text, timestamptz, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.access_vendor_tax_identity_evidence(uuid, text, uuid, text, uuid) to authenticated, service_role;

grant execute on function app.propose_vendor_payment_term_change(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_payment_term_change_proposal(uuid, integer, text, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_payment_term_proposal(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_payment_term_proposals(uuid, uuid, text, integer, uuid) to authenticated, service_role;

grant execute on function app.get_vendor_financial_verification_status(uuid, uuid) to authenticated, service_role;
