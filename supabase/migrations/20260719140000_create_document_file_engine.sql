-- Platform Core capability PLT-128 (Document and File Engine, CG-S6-PLT-025)
-- Private, tenant/record-aware file metadata and lifecycle primitives with mandatory
-- malware scanning before availability (RPD-032, PKG-NFR-FILE-001), signed short-lived
-- delivery, retention/legal hold. docs/architecture/01_MODULE_DEPENDENCY_MAP.md:101
-- ("Document engine is the only path to Supabase Storage") and
-- 05_DATABASE_SCHEMA_WORKSTREAM.md's "File metadata/quarantine" section are the
-- sourced design basis; no ADR-CAND-ARCH candidate exists for storage/malware-scan
-- vendor selection (confirmed absent from docs/adr/), so the ratifying source cited
-- here is the architecture document directly, not an accepted ADR -- disclosed, not
-- silently assumed resolved.
--
-- Scope and design decisions, disclosed rather than left implicit (this session's
-- standing discipline):
--
-- * **No real storage/malware-scan provider is ever called.** No live Supabase project
--   exists in this sandbox (the same constraint PLT-107/118 already recorded). Actual
--   object bytes never move anywhere; `app.files.storage_path` is a real, unguessable,
--   server-generated key (tenant_id + document_type_code + a fresh random uuid --
--   deliberately never derived from the client-supplied filename, which structurally
--   rules out path traversal via that vector). `app.record_file_scan_result()` is the
--   real, tested, bounded adapter interface a future scan-provider webhook/job would
--   call -- the same "bounded adapter, no fabricated send" pattern PLT-127's
--   `record_notification_delivery_attempt()` established. A scan-complete notification
--   to the uploader is a plausible future integration point (this is why PLT-127 is an
--   upstream dependency per the execution index) but is deliberately NOT wired here:
--   no domain notification type is registered yet (PLT-127's own disclosure), and
--   fabricating one purely to satisfy this migration would manufacture content this
--   repository does not actually need yet.
-- * **A document *type* is not a new registry mechanism.** `app.register_document_type()`
--   mints a dedicated `document:<code>` config_type via PLT-121's own
--   `app.register_config_type()` -- the identical per-instance registry composition
--   PLT-124 (status), PLT-125 (numbering), PLT-126 (form), PLT-127 (notification) all
--   already established, for the identical structural reason (`config_objects_scope_shape_check`
--   forces `scope_id` null at `scope_level='tenant'`, so a single shared type can host
--   at most one tenant-scoped object). Unlike those four, no generic `'document'`
--   config_type was ever seeded by PLT-121 in the first place (its own 10-type Module
--   Adoption Map list has no `document` entry) -- there is no unused placeholder to
--   disclose here, only fresh per-type registrations. Each tenant then drafts/publishes
--   its OWN definition (allowed MIME types, max size, retention class, default
--   classification, legal-hold eligibility) under that type via the config engine's
--   existing draft/publish mechanism -- a document type's *rules* are tenant-configurable,
--   its *kind* is platform-registered, mirroring the Status Engine's set/presentation split.
-- * **This entire capability is server-mediated only** -- every mutating function
--   (`initiate_file_upload`, `record_file_scan_result`, `authorize_file_access`,
--   `create_file_version`, `request_file_deletion`, `set_file_legal_hold`,
--   `register_document_type`, `publish_document_type_definition`) is granted to
--   `service_role` only, never `authenticated`. Real signed-URL issuance inherently
--   requires storage credentials only server code holds, so there is no legitimate
--   direct-client RPC surface here the way PLT-127 had genuine self-service actions
--   (mark-read, set-own-preference). Consequently none of this migration's functions
--   needs `SECURITY DEFINER`: `service_role` already holds direct table grants on
--   every table these functions touch, so plain `SECURITY INVOKER` (the default)
--   resolves correctly when the caller is `service_role`. Read access for
--   `authenticated` is direct-table RLS (below), not a resolver function -- matching
--   PLT-113/114/120's "shared business data" precedent rather than PLT-127's
--   "personal inbox" precedent, since a file is inherently shared record-scoped data.
-- * **`classification` is wired to `scripts/data-classification/registry.ts`'s
--   `SENSITIVITY_LEVELS` scale** (`docs/standards/DATA_CLASSIFICATION_STANDARDS.md` §2,
--   §8's named gap: "files.classification column values wired to this registry -- No
--   files table exists yet"). The wiring is a literal CHECK-constraint match against
--   `('public','internal','confidential','restricted','credential')`, not a static
--   `ClassificationEntry` -- a file's classification is a dynamic per-row value chosen
--   at upload time, not a fixed schema-field sensitivity the `ClassificationEntry`
--   model classifies once at author time; forcing it into that model would misrepresent
--   what the registry actually tracks. `app.classification_level_rank()` mirrors
--   `registry.ts`'s `LEVEL_ORDER` exactly (both scales cannot literally share code
--   across the SQL/TypeScript boundary) so a file's classification can never be set
--   weaker than its document type's configured default -- the same "strongest-or-equal"
--   rule `registry.ts`'s own `validateRegistry()` enforces for static entries.
--   `docs/standards/DATA_CLASSIFICATION_STANDARDS.md` §8's row is updated to reflect
--   this resolution in the same checkpoint.
-- * **Scope boundary**: only `app.files` and `app.file_access_logs` are created here.
--   `05_DATABASE_SCHEMA_WORKSTREAM.md` §6 groups `notifications, files, audit_logs,
--   event_logs, api_logs, file_access_logs, support_access_logs` into one "Platform
--   notification/document/audit core" wave, but `notifications` (PLT-127),
--   `audit_logs` (PLT-116), and `support_access_events` (PLT-115's own name for that
--   row) already shipped: `event_logs`/`api_logs` are generic platform event/webhook
--   infrastructure with no file-specific reason to build here and are left to their own
--   future owning prompt (the Job/API/Webhook platform primitive), consistent with
--   this prompt's own "Allowed files/folders... 5-15 files" sizing discipline.
-- * **Versioning never overwrites**: `app.create_file_version()` always inserts a new
--   row (`version_group_id` links the lineage, `version_number` increments,
--   `is_latest_version` is exclusive via a partial unique index) and flips the prior
--   row to `lifecycle_status='superseded'` -- it is never deleted or mutated in place,
--   matching every prior versioning capability this session built.
-- * **Legal hold overrides deletion, never the reverse**: `app.request_file_deletion()`
--   refuses outright while `legal_hold=true`; `app.set_file_legal_hold()` is restricted
--   to support/Supreme authority (a privileged action, not any active tenant member).
-- * **The malware-scan gate and the record/sensitivity-access gate are independent**,
--   composed together only inside `app.authorize_file_access()` (`06_RLS_RBAC_WORKSTREAM.md`'s
--   own "two independent gates" framing, quoted in this checkpoint's own research) --
--   RLS on `app.files` intentionally does NOT reference `malware_scan_status` at all,
--   since metadata/status visibility ("pending scan is visible with safe status",
--   prompt §22) is a separate concern from content-delivery authorization.
--   `05_DATABASE_SCHEMA_WORKSTREAM.md`'s own line is honored literally: a signed URL
--   is withheld from anyone other than the uploader while scan status is not `clean`;
--   an `infected` result blocks even the uploader (quarantine, not merely "someone
--   else can't see it yet").
-- * **Additive grant**: `app.is_support_grant_authority()` (PLT-115) was granted to
--   `service_role` only, since it had no RLS-policy consumer yet. This migration adds
--   `grant execute ... to authenticated` so the RLS policy on `app.files` below can
--   actually evaluate it as the calling role -- its first real RLS consumer.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

-- The document-type registry (kind, not rules) -- mirrors app.notification_types /
-- app.status_sets exactly.
create table app.document_types (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.document_types is
  'PLT-128: registry of document/file kinds (e.g. contract, invoice, epod). owner_primitive_code names the owning Platform primitive (DOC). Each tenant configures its own rules (allowed MIME types, max size, retention class, default classification, legal-hold eligibility) for a given code via a dedicated document:<code> config_type minted through app.register_config_type().';

create function app.register_document_type(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.document_types
language plpgsql
as $$
declare
  v_existing app.document_types;
  v_type app.document_types;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a document type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.document_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.document_types (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_type;

  perform app.register_config_type('document:' || p_code, p_name, p_owner_primitive_code, p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_document_type',
    'app.document_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

-- Publish-time structural gate over a 'document:<code>'-typed config_version's items.
-- Expects 'allowed_mime_types' (non-empty jsonb array, every entry in a bounded
-- platform allowlist -- deliberately excludes anything executable/script-like),
-- 'max_size_bytes' (0 < n <= 104857600, a disclosed 100 MB structural ceiling),
-- 'retention_class' (one of scripts/data-classification/registry.ts's RetentionClass
-- values, plus 'none' for docs with no defined retention -- disclosed addition, RPD-025
-- does not itemize an "undefined" case), 'default_classification' (one of
-- SENSITIVITY_LEVELS), 'legal_hold_eligible' (boolean).
create function app.validate_document_type_definition(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_allowed_mime jsonb;
  v_mime text;
  v_max_size_raw jsonb;
  v_max_size bigint;
  v_retention_class text;
  v_default_classification text;
  v_legal_hold_eligible_raw jsonb;
  v_allowed_mime_types text[] := array[
    'application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'text/plain', 'text/csv',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/zip'
  ];
  v_allowed_retention_classes text[] := array['finance_tax_10y', 'audit_security_7y', 'operational_contract_plus_90d', 'none'];
  v_allowed_sensitivity_levels text[] := array['public', 'internal', 'confidential', 'restricted', 'credential'];
begin
  select value into v_allowed_mime from app.config_items where config_version_id = p_version_id and key = 'allowed_mime_types';
  select value into v_max_size_raw from app.config_items where config_version_id = p_version_id and key = 'max_size_bytes';
  select value #>> '{}' into v_retention_class from app.config_items where config_version_id = p_version_id and key = 'retention_class';
  select value #>> '{}' into v_default_classification from app.config_items where config_version_id = p_version_id and key = 'default_classification';
  select value into v_legal_hold_eligible_raw from app.config_items where config_version_id = p_version_id and key = 'legal_hold_eligible';

  if v_allowed_mime is null or jsonb_typeof(v_allowed_mime) <> 'array' or jsonb_array_length(v_allowed_mime) = 0 then
    raise exception 'document_missing_mime_types: version % has no ''allowed_mime_types'' item, or it is not a non-empty array', p_version_id
      using errcode = 'check_violation';
  end if;
  for v_mime in select * from jsonb_array_elements_text(v_allowed_mime) loop
    if not (v_mime = any (v_allowed_mime_types)) then
      raise exception 'document_invalid_mime_type: % is not in the platform allowlist', v_mime
        using errcode = 'check_violation';
    end if;
  end loop;

  if v_max_size_raw is null or jsonb_typeof(v_max_size_raw) <> 'number' then
    raise exception 'document_missing_max_size: version % has no numeric ''max_size_bytes'' item', p_version_id
      using errcode = 'check_violation';
  end if;
  v_max_size := (v_max_size_raw #>> '{}')::bigint;
  if v_max_size <= 0 or v_max_size > 104857600 then
    raise exception 'document_invalid_max_size: max_size_bytes % must be > 0 and <= 104857600 (100 MB)', v_max_size
      using errcode = 'check_violation';
  end if;

  if v_retention_class is null or not (v_retention_class = any (v_allowed_retention_classes)) then
    raise exception 'document_invalid_retention_class: % is not one of finance_tax_10y/audit_security_7y/operational_contract_plus_90d/none', v_retention_class
      using errcode = 'check_violation';
  end if;

  if v_default_classification is null or not (v_default_classification = any (v_allowed_sensitivity_levels)) then
    raise exception 'document_invalid_default_classification: % is not a recognized sensitivity level', v_default_classification
      using errcode = 'check_violation';
  end if;

  if v_legal_hold_eligible_raw is null or jsonb_typeof(v_legal_hold_eligible_raw) <> 'boolean' then
    raise exception 'document_missing_legal_hold_eligible: version % has no boolean ''legal_hold_eligible'' item', p_version_id
      using errcode = 'check_violation';
  end if;

  return true;
end;
$$;

create function app.publish_document_type_definition(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_document_type_definition(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Mirrors scripts/data-classification/registry.ts's LEVEL_ORDER exactly (disclosed in
-- this migration's header -- the SQL and TypeScript scales cannot literally share code).
create function app.classification_level_rank(p_level text)
returns integer
language sql
immutable
as $$
  select case p_level
    when 'public' then 0
    when 'internal' then 1
    when 'confidential' then 2
    when 'restricted' then 3
    when 'credential' then 4
    else null
  end;
$$;

create function app.check_file_action_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- Resolves a tenant's currently published definition for a document type code, raising
-- if the tenant has never published one -- 'never silently invent limits' (matches
-- PLT-121's own resolver discipline: an unconfigured config_type resolves to zero rows,
-- never a fabricated universal default).
create function app.resolve_document_type_definition(p_tenant_id uuid, p_document_type_code text)
returns table (
  config_version_id uuid,
  allowed_mime_types jsonb,
  max_size_bytes bigint,
  retention_class text,
  default_classification text,
  legal_hold_eligible boolean
)
language plpgsql
stable
as $$
declare
  v_version_id uuid;
begin
  select cv.id into v_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'document:' || p_document_type_code
    and co.tenant_id = p_tenant_id
    and co.scope_level = 'tenant'
    and cv.status = 'published'
  order by cv.version_number desc
  limit 1;

  if v_version_id is null then
    raise exception 'document_type_not_configured: tenant % has not published a definition for document type %', p_tenant_id, p_document_type_code
      using errcode = 'check_violation';
  end if;

  return query
  select
    v_version_id,
    (select ci.value from app.config_items ci where ci.config_version_id = v_version_id and ci.key = 'allowed_mime_types'),
    (select (ci.value #>> '{}')::bigint from app.config_items ci where ci.config_version_id = v_version_id and ci.key = 'max_size_bytes'),
    (select ci.value #>> '{}' from app.config_items ci where ci.config_version_id = v_version_id and ci.key = 'retention_class'),
    (select ci.value #>> '{}' from app.config_items ci where ci.config_version_id = v_version_id and ci.key = 'default_classification'),
    (select (ci.value #>> '{}')::boolean from app.config_items ci where ci.config_version_id = v_version_id and ci.key = 'legal_hold_eligible');
end;
$$;

-- The file metadata record. record_type/record_id are a generic polymorphic reference
-- (no live FK -- no business-domain table exists yet in Phase 1 Platform Core, the same
-- disclosed "entity_type/entity_id" pattern PLT-126's app.custom_field_values already
-- established, proven here by synthetic db-test values). storage_path is fully
-- server-generated (tenant_id + document_type_code + a fresh random uuid) and never
-- derived from original_filename -- the structural reason path traversal via filename
-- is impossible regardless of the filename's own contents.
create table app.files (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  document_type_code text not null references app.document_types (code),
  config_version_id uuid not null references app.config_versions (id),
  record_type text not null,
  record_id uuid not null,
  classification text not null,
  original_filename text not null,
  mime_type text not null,
  size_bytes bigint not null,
  storage_path text not null,
  malware_scan_status text not null default 'pending',
  malware_scan_completed_at timestamptz,
  malware_scan_provider_ref text,
  version_group_id uuid not null,
  version_number integer not null default 1,
  is_latest_version boolean not null default true,
  lifecycle_status text not null default 'active',
  legal_hold boolean not null default false,
  legal_hold_reason text,
  deleted_at timestamptz,
  uploaded_by_auth_user_id uuid not null,
  shared_org_unit_ids uuid[] not null default '{}',
  customer_account_ref text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint files_classification_check check (classification in ('public', 'internal', 'confidential', 'restricted', 'credential')),
  constraint files_malware_scan_status_check check (malware_scan_status in ('pending', 'clean', 'infected', 'error')),
  constraint files_lifecycle_status_check check (lifecycle_status in ('active', 'superseded', 'deleted')),
  constraint files_size_bytes_check check (size_bytes > 0),
  constraint files_version_number_check check (version_number > 0),
  constraint files_legal_hold_reason_check check (legal_hold = false or legal_hold_reason is not null),
  constraint files_filename_safe_check check (
    length(original_filename) between 1 and 255
    and position('/' in original_filename) = 0
    and position('\' in original_filename) = 0
    and position('..' in original_filename) = 0
  ),
  constraint files_storage_path_unique unique (tenant_id, storage_path),
  constraint files_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.files is
  'PLT-128: private file/document metadata. Content bytes are never stored in this database -- storage_path is the object key a real Supabase Storage integration would use (disclosed NOT_RUN, no live project in this sandbox). malware_scan_status must be clean before app.authorize_file_access() grants a signed download to anyone but the uploader (RPD-032). classification drives an additional access gate for restricted/credential files, wired to scripts/data-classification/registry.ts''s SENSITIVITY_LEVELS scale.';

create unique index files_one_latest_version_idx on app.files (version_group_id) where is_latest_version;
create index files_tenant_record_idx on app.files (tenant_id, record_type, record_id);
create index files_tenant_uploader_idx on app.files (tenant_id, uploaded_by_auth_user_id);
create index files_version_group_idx on app.files (version_group_id, version_number);

create function app.touch_files_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger files_touch_row
  before update on app.files
  for each row
  execute function app.touch_files_row();

-- Append-only file-access evidence, distinct from app.audit_logs (05_DATABASE_SCHEMA_
-- WORKSTREAM.md §6's five-table split: audit_logs is compliance who-changed-what,
-- file_access_logs is specifically content-access evidence). No authenticated policy
-- at all -- service_role only, matching app.notification_delivery_attempts' precedent.
create table app.file_access_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  file_id uuid not null references app.files (id),
  accessed_by_auth_user_id uuid not null,
  access_type text not null,
  result text not null,
  reason text,
  correlation_id uuid,
  accessed_at timestamptz not null default now(),
  constraint file_access_logs_access_type_check check (access_type in ('signed_url_issued', 'download', 'metadata_view')),
  constraint file_access_logs_result_check check (result in ('granted', 'denied'))
);

comment on table app.file_access_logs is
  'PLT-128: append-only evidence of every app.authorize_file_access() decision, granted/denied with a machine-readable reason. Never mutated after insert.';

create index file_access_logs_file_idx on app.file_access_logs (file_id, accessed_at desc);
create index file_access_logs_tenant_idx on app.file_access_logs (tenant_id, accessed_at desc);

-- Two-phase upload/complete collapses to one metadata-creation call: no live storage
-- integration exists in this sandbox to actually complete an upload against, so the
-- "initiate" step is the entire provable surface (disclosed simplification, matching
-- PLT-121's own precedent of condensing an externally-motivated multi-step lifecycle
-- onto what this repository can actually prove today).
create function app.initiate_file_upload(
  p_tenant_id uuid,
  p_document_type_code text,
  p_record_type text,
  p_record_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_classification text,
  p_legal_hold boolean,
  p_legal_hold_reason text,
  p_shared_org_unit_ids uuid[],
  p_customer_account_ref text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.files
language plpgsql
as $$
declare
  v_existing app.files;
  v_def record;
  v_effective_classification text;
  v_new_id uuid := gen_random_uuid();
  v_file app.files;
begin
  if not app.check_file_action_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'file_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.files where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if p_original_filename is null or length(p_original_filename) = 0 or length(p_original_filename) > 255
     or position('/' in p_original_filename) > 0
     or position('\' in p_original_filename) > 0
     or position('..' in p_original_filename) > 0
  then
    raise exception 'document_unsafe_filename: filename is missing, empty, too long, or contains a path separator/traversal sequence'
      using errcode = 'check_violation';
  end if;

  select * into v_def from app.resolve_document_type_definition(p_tenant_id, p_document_type_code);

  if not exists (
    select 1 from jsonb_array_elements_text(v_def.allowed_mime_types) as t(mime) where t.mime = p_mime_type
  ) then
    raise exception 'document_mime_type_not_allowed: % is not an allowed MIME type for document type %', p_mime_type, p_document_type_code
      using errcode = 'check_violation';
  end if;

  if p_size_bytes <= 0 or p_size_bytes > v_def.max_size_bytes then
    raise exception 'document_file_too_large: % bytes exceeds the % byte limit for document type % (or is not positive)', p_size_bytes, v_def.max_size_bytes, p_document_type_code
      using errcode = 'check_violation';
  end if;

  v_effective_classification := coalesce(p_classification, v_def.default_classification);
  if app.classification_level_rank(v_effective_classification) is null then
    raise exception 'document_invalid_classification: % is not a recognized sensitivity level', v_effective_classification
      using errcode = 'check_violation';
  end if;
  if app.classification_level_rank(v_effective_classification) < app.classification_level_rank(v_def.default_classification) then
    raise exception 'document_classification_too_weak: % is weaker than document type %''s default classification %', v_effective_classification, p_document_type_code, v_def.default_classification
      using errcode = 'check_violation';
  end if;

  if coalesce(p_legal_hold, false) then
    if not v_def.legal_hold_eligible then
      raise exception 'document_type_not_legal_hold_eligible: document type % may not be placed under legal hold', p_document_type_code
        using errcode = 'check_violation';
    end if;
    if p_legal_hold_reason is null or length(trim(p_legal_hold_reason)) = 0 then
      raise exception 'document_legal_hold_reason_required: legal_hold_reason is required when legal_hold is true'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.files (
    id, tenant_id, document_type_code, config_version_id, record_type, record_id,
    classification, original_filename, mime_type, size_bytes,
    storage_path, malware_scan_status, version_group_id, version_number, is_latest_version,
    lifecycle_status, legal_hold, legal_hold_reason, uploaded_by_auth_user_id,
    shared_org_unit_ids, customer_account_ref, idempotency_key
  ) values (
    v_new_id, p_tenant_id, p_document_type_code, v_def.config_version_id, p_record_type, p_record_id,
    v_effective_classification, p_original_filename, p_mime_type, p_size_bytes,
    'tenant/' || p_tenant_id::text || '/' || p_document_type_code || '/' || v_new_id::text,
    'pending', v_new_id, 1, true,
    'active', coalesce(p_legal_hold, false), p_legal_hold_reason, p_actor_auth_user_id,
    coalesce(p_shared_org_unit_ids, array[]::uuid[]), p_customer_account_ref, p_idempotency_key
  )
  returning * into v_file;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'initiate_file_upload',
    'app.files', v_file.id, 'success', null, null, to_jsonb(v_file)
  );

  return v_file;
end;
$$;

-- The malware-scan adapter interface (bounded, real, tested) -- never calls a live
-- scanner (disclosed NOT_RUN, this migration's own header). Idempotent-safe: re-calling
-- with the already-resolved status is a no-op return, not an error.
create function app.record_file_scan_result(
  p_file_id uuid,
  p_status text,
  p_provider_ref text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.files
language plpgsql
as $$
declare
  v_file app.files;
  v_updated app.files;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_file_action_authority(v_file.tenant_id, p_actor_auth_user_id) then
    raise exception 'file_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_file.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_status = any (array['clean', 'infected', 'error'])) then
    raise exception 'document_scan_status_invalid: % is not one of clean/infected/error', p_status
      using errcode = 'check_violation';
  end if;

  if v_file.malware_scan_status <> 'pending' then
    if v_file.malware_scan_status = p_status then
      return v_file;
    end if;
    raise exception 'document_scan_already_resolved: file % already resolved to scan status %, cannot re-resolve to %', p_file_id, v_file.malware_scan_status, p_status
      using errcode = 'check_violation';
  end if;

  update app.files
  set malware_scan_status = p_status,
      malware_scan_completed_at = now(),
      malware_scan_provider_ref = p_provider_ref
  where id = p_file_id
  returning * into v_updated;

  -- app.audit_logs.result CHECK only allows ('success','failure') -- learned the hard
  -- way at PLT-127, applied proactively here rather than re-discovering it via a
  -- failing test.
  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_file_scan_result',
    'app.files', v_updated.id,
    case when p_status = 'clean' then 'success' else 'failure' end,
    case when p_status <> 'clean' then p_status else null end,
    to_jsonb(v_file), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- The single gate a real signed-URL-issuing server action calls before generating one.
-- Composes two independent checks (06_RLS_RBAC_WORKSTREAM.md's own framing): the
-- malware-scan gate (infected blocks everyone; not-yet-clean blocks everyone but the
-- uploader) and the record/sensitivity access gate (app.can_access_record() plus a
-- stricter check for restricted/credential classification). A genuinely unauthorized
-- actor (no tenant standing at all) is refused outright with an exception and no log
-- row, the same "fails safely, never even logs" treatment PLT-127 gave a wrong-tenant
-- notification recipient; a tenant member who is merely denied by scope/sensitivity
-- gets a real, returned, logged denial instead, so a caller can show a generic
-- "access denied" response.
create function app.authorize_file_access(
  p_file_id uuid,
  p_access_type text,
  p_actor_auth_user_id uuid,
  p_correlation_id uuid default null
)
returns app.file_access_logs
language plpgsql
as $$
declare
  v_file app.files;
  v_result text;
  v_reason text;
  v_log app.file_access_logs;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_file_action_authority(v_file.tenant_id, p_actor_auth_user_id) then
    raise exception 'file_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_file.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_access_type = any (array['signed_url_issued', 'download', 'metadata_view'])) then
    raise exception 'document_access_type_invalid: % is not one of signed_url_issued/download/metadata_view', p_access_type
      using errcode = 'check_violation';
  end if;

  v_result := 'granted';
  v_reason := null;

  if p_access_type <> 'metadata_view' then
    if v_file.deleted_at is not null and not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
      v_result := 'denied';
      v_reason := 'document_deleted';
    elsif v_file.malware_scan_status = 'infected' then
      v_result := 'denied';
      v_reason := 'document_infected_quarantined';
    elsif v_file.malware_scan_status <> 'clean' and v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id then
      v_result := 'denied';
      v_reason := 'document_not_yet_scanned';
    end if;
  end if;

  if v_result = 'granted' and v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id then
    if not (
      app.is_supreme_admin(p_actor_auth_user_id)
      or app.can_access_record(p_actor_auth_user_id, v_file.tenant_id, v_file.uploaded_by_auth_user_id, v_file.shared_org_unit_ids, v_file.customer_account_ref)
      or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)
    ) then
      v_result := 'denied';
      v_reason := 'document_record_access_denied';
    end if;
  end if;

  if v_result = 'granted' and v_file.classification in ('restricted', 'credential') and v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id then
    if not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
      v_result := 'denied';
      v_reason := 'document_classification_access_denied';
    end if;
  end if;

  insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
  values (v_file.tenant_id, v_file.id, p_actor_auth_user_id, p_access_type, v_result, v_reason, p_correlation_id)
  returning * into v_log;

  return v_log;
end;
$$;

-- Always inserts a new row (never overwrites) -- version_group_id links the lineage,
-- version_number increments, is_latest_version is kept exclusive by flipping the prior
-- row BEFORE inserting the new one (the partial unique index is checked immediately,
-- not deferred).
create function app.create_file_version(
  p_previous_file_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_classification text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.files
language plpgsql
as $$
declare
  v_prev app.files;
  v_def record;
  v_effective_classification text;
  v_new_id uuid := gen_random_uuid();
  v_file app.files;
begin
  select * into v_prev from app.files where id = p_previous_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_previous_file_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_file_action_authority(v_prev.tenant_id, p_actor_auth_user_id) then
    raise exception 'file_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prev.uploaded_by_auth_user_id <> p_actor_auth_user_id
     and not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_prev.tenant_id)) then
    raise exception 'document_version_unauthorized: only the original uploader or a support/supreme authority may add a new version of file %', p_previous_file_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prev.deleted_at is not null then
    raise exception 'document_version_of_deleted_file: file % has been deleted, cannot add a new version', p_previous_file_id
      using errcode = 'check_violation';
  end if;

  if not v_prev.is_latest_version then
    raise exception 'document_version_not_latest: file % is not the latest version of its group, versioning must start from the latest', p_previous_file_id
      using errcode = 'check_violation';
  end if;

  if p_original_filename is null or length(p_original_filename) = 0 or length(p_original_filename) > 255
     or position('/' in p_original_filename) > 0
     or position('\' in p_original_filename) > 0
     or position('..' in p_original_filename) > 0
  then
    raise exception 'document_unsafe_filename: filename is missing, empty, too long, or contains a path separator/traversal sequence'
      using errcode = 'check_violation';
  end if;

  select * into v_def from app.resolve_document_type_definition(v_prev.tenant_id, v_prev.document_type_code);

  if not exists (
    select 1 from jsonb_array_elements_text(v_def.allowed_mime_types) as t(mime) where t.mime = p_mime_type
  ) then
    raise exception 'document_mime_type_not_allowed: % is not an allowed MIME type for document type %', p_mime_type, v_prev.document_type_code
      using errcode = 'check_violation';
  end if;

  if p_size_bytes <= 0 or p_size_bytes > v_def.max_size_bytes then
    raise exception 'document_file_too_large: % bytes exceeds the % byte limit for document type % (or is not positive)', p_size_bytes, v_def.max_size_bytes, v_prev.document_type_code
      using errcode = 'check_violation';
  end if;

  v_effective_classification := coalesce(p_classification, v_prev.classification);
  if app.classification_level_rank(v_effective_classification) is null then
    raise exception 'document_invalid_classification: % is not a recognized sensitivity level', v_effective_classification
      using errcode = 'check_violation';
  end if;
  if app.classification_level_rank(v_effective_classification) < app.classification_level_rank(v_def.default_classification) then
    raise exception 'document_classification_too_weak: % is weaker than document type %''s default classification %', v_effective_classification, v_prev.document_type_code, v_def.default_classification
      using errcode = 'check_violation';
  end if;

  update app.files
  set is_latest_version = false, lifecycle_status = 'superseded'
  where id = v_prev.id;

  insert into app.files (
    id, tenant_id, document_type_code, config_version_id, record_type, record_id,
    classification, original_filename, mime_type, size_bytes,
    storage_path, malware_scan_status, version_group_id, version_number, is_latest_version,
    lifecycle_status, legal_hold, legal_hold_reason, uploaded_by_auth_user_id,
    shared_org_unit_ids, customer_account_ref
  ) values (
    v_new_id, v_prev.tenant_id, v_prev.document_type_code, v_def.config_version_id, v_prev.record_type, v_prev.record_id,
    v_effective_classification, p_original_filename, p_mime_type, p_size_bytes,
    'tenant/' || v_prev.tenant_id::text || '/' || v_prev.document_type_code || '/' || v_new_id::text,
    'pending', v_prev.version_group_id, v_prev.version_number + 1, true,
    'active', false, null, p_actor_auth_user_id,
    v_prev.shared_org_unit_ids, v_prev.customer_account_ref
  )
  returning * into v_file;

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_file_version',
    'app.files', v_file.id, 'success', null, to_jsonb(v_prev), to_jsonb(v_file)
  );

  return v_file;
end;
$$;

-- Soft delete only -- deleted_at, never a physical delete (05_DATABASE_SCHEMA_
-- WORKSTREAM.md §4's standing "deleted_at is the only sanctioned removal path"
-- convention). Idempotent (a second call against an already-deleted file returns it
-- unchanged rather than erroring). legal_hold overrides deletion unconditionally.
create function app.request_file_deletion(
  p_file_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.files
language plpgsql
as $$
declare
  v_file app.files;
  v_updated app.files;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  if v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id
     and not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
    raise exception 'document_deletion_unauthorized: only the original uploader or a support/supreme authority may request deletion of file %', p_file_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_file.deleted_at is not null then
    return v_file;
  end if;

  if v_file.legal_hold then
    raise exception 'document_legal_hold_blocks_deletion: file % is under legal hold (%), it cannot be deleted', p_file_id, v_file.legal_hold_reason
      using errcode = 'check_violation';
  end if;

  update app.files
  set deleted_at = now(), lifecycle_status = 'deleted'
  where id = p_file_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_file_deletion',
    'app.files', v_updated.id, 'success', p_reason, to_jsonb(v_file), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- A privileged action -- support/Supreme authority only, not any active tenant member
-- (matches §18's "privileged actions" note distinctly from the ordinary upload/access
-- runtime actions above, which only require active tenant membership).
create function app.set_file_legal_hold(
  p_file_id uuid,
  p_legal_hold boolean,
  p_legal_hold_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.files
language plpgsql
as $$
declare
  v_file app.files;
  v_updated app.files;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  if not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
    raise exception 'document_legal_hold_unauthorized: identity % lacks support/supreme authority over tenant %', p_actor_auth_user_id, v_file.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_legal_hold and (p_legal_hold_reason is null or length(trim(p_legal_hold_reason)) = 0) then
    raise exception 'document_legal_hold_reason_required: legal_hold_reason is required when legal_hold is true'
      using errcode = 'check_violation';
  end if;

  update app.files
  set legal_hold = p_legal_hold,
      legal_hold_reason = case when p_legal_hold then p_legal_hold_reason else null end
  where id = p_file_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_file_legal_hold',
    'app.files', v_updated.id, 'success', null, to_jsonb(v_file), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- RLS. app.document_types is a broadly readable registry (mirrors notification_types/
-- status_sets). app.files composes app.can_access_record() plus a stricter
-- restricted/credential-classification gate and a deleted-row visibility restriction --
-- deliberately does NOT reference malware_scan_status (this migration's own header).
-- app.file_access_logs has no authenticated policy at all.
alter table app.document_types enable row level security;
alter table app.files enable row level security;
alter table app.file_access_logs enable row level security;

create policy document_types_select_all on app.document_types
for select to authenticated
using (true);

create policy files_select_scoped on app.files
for select to authenticated
using (
  app.is_supreme_admin()
  or (
    app.has_active_tenant_membership(tenant_id)
    and (deleted_at is null or app.is_support_grant_authority(auth.uid(), tenant_id))
    and (
      uploaded_by_auth_user_id = auth.uid()
      or app.can_access_record(auth.uid(), tenant_id, uploaded_by_auth_user_id, shared_org_unit_ids, customer_account_ref)
      or app.is_support_grant_authority(auth.uid(), tenant_id)
    )
    and (
      classification not in ('restricted', 'credential')
      or uploaded_by_auth_user_id = auth.uid()
      or app.is_support_grant_authority(auth.uid(), tenant_id)
    )
  )
);

revoke execute on all functions in schema app from public;

grant select on app.document_types to authenticated, service_role;
grant insert, update, delete on app.document_types to service_role;

grant select on app.files to authenticated, service_role;
grant insert, update, delete on app.files to service_role;

grant select, insert, update, delete on app.file_access_logs to service_role;

grant execute on function app.register_document_type(text, text, text, uuid, text) to service_role;
grant execute on function app.validate_document_type_definition(uuid) to service_role;
grant execute on function app.publish_document_type_definition(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.classification_level_rank(text) to service_role;
grant execute on function app.check_file_action_authority(uuid, uuid) to service_role;
grant execute on function app.resolve_document_type_definition(uuid, text) to service_role;
grant execute on function app.initiate_file_upload(uuid, text, text, uuid, text, text, bigint, text, boolean, text, uuid[], text, text, uuid, text) to service_role;
grant execute on function app.record_file_scan_result(uuid, text, text, uuid, text) to service_role;
grant execute on function app.authorize_file_access(uuid, text, uuid, uuid) to service_role;
grant execute on function app.create_file_version(uuid, text, text, bigint, text, uuid, text) to service_role;
grant execute on function app.request_file_deletion(uuid, text, uuid, text) to service_role;
grant execute on function app.set_file_legal_hold(uuid, boolean, text, uuid, text) to service_role;

-- First real RLS consumer of app.is_support_grant_authority() -- additive grant, see
-- this migration's own header.
grant execute on function app.is_support_grant_authority(uuid, uuid) to authenticated;
