-- Closes `ISS-2026-083`. `284_TRAINING_TALENT_PROMPT.md` §16 names "provider/certificate files
-- are private and malware-scanned". Only the certificate half was ever built:
-- `app.training_certificates.evidence_file_id` + `app.attach_training_certificate_evidence`
-- exist, `app.training_providers` has no evidence column and no attach RPC at all.
--
-- WHY THIS IS BUILT RATHER THAN THE SPEC NARROWED
--
--   The entry's own disposition wavered between the two, noting §13's database-impact list "never
--   separately named a persisted provider-evidence record, so this may be reading more into §16's
--   phrasing than the section intended." That is a fair doubt, and it is settled by asking what
--   the evidence is *for* rather than by parsing the sentence again.
--
--   A training provider is an external party a tenant pays to certify its people. The document
--   that matters is the provider's own accreditation — the thing an auditor asks for when they
--   want to know whether a certificate means anything. Certificate evidence proves an employee
--   attended; provider evidence proves the body that issued it was entitled to. Dropping the
--   second leaves the first resting on an unverifiable claim, which is precisely the gap §16's
--   phrasing guards against. So the spec is right and the implementation was short.
--
-- MIRRORS THE CERTIFICATE HALF EXACTLY, ON PURPOSE
--
--   Same column shape, same `HRS:Edit` gate via `app.check_training_authority`, same optimistic
--   concurrency, same PLT-128 re-validation at the attaching RPC (tenant, record scope, malware
--   scan), same audit event, same grant set and `public.*` wrapper. Two evidence-attachment paths
--   in one capability that behave differently would be a difference a reader has to learn for no
--   benefit — and the certificate path is already proven, so divergence could only be a
--   regression.

alter table app.training_providers
  add column if not exists evidence_file_id uuid references app.files (id);

comment on column app.training_providers.evidence_file_id is
  'ISS-2026-083 (Prompt 284 §16, "provider/certificate files are private and malware-scanned"): the provider''s own accreditation document. Certificate evidence proves an employee attended; this proves the body that issued the certificate was entitled to. Attached only via app.attach_training_provider_evidence, which re-validates tenant, record scope and malware-scan status at the point of attachment (PLT-128) rather than trusting the upload.';

create function app.attach_training_provider_evidence(p_provider_id uuid, p_expected_version integer, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_providers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_provider app.training_providers;
  v_file app.files;
begin
  select * into v_provider from app.training_providers where id = p_provider_id for update;
  if not found then
    raise exception 'training_provider_not_found: %', p_provider_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_provider.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_provider.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_provider.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_provider.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Re-validated here, not trusted from the upload: a file clean at upload may not be clean now,
  -- and one uploaded against a different provider must never count as evidence for this one.
  select * into v_file from app.files where id = p_evidence_file_id;
  if not found or v_file.tenant_id <> v_provider.tenant_id or v_file.record_type <> 'training_provider' or v_file.record_id <> p_provider_id then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file for provider %', p_evidence_file_id, p_provider_id using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.training_providers set evidence_file_id = p_evidence_file_id where id = p_provider_id and record_version = p_expected_version
  returning * into v_provider;
  if not found then
    raise exception 'stale_version: concurrent update detected for provider %', p_provider_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_provider.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_training_provider_evidence',
    'app.training_providers', v_provider.id, 'success', null, null, jsonb_build_object('evidence_file_id', p_evidence_file_id)
  );

  return v_provider;
end;
$$;

comment on function app.attach_training_provider_evidence is
  'ISS-2026-083, Prompt 284 §16''s provider half. Byte-for-byte the shape app.attach_training_certificate_evidence already established -- HRS:Edit, optimistic concurrency, PLT-128 re-validation of tenant/record scope/malware-scan status at the point of attachment, one audit event. Deliberately not a second, differently-behaving evidence path: the certificate path is already proven, so any divergence here could only be a regression.';

revoke execute on function app.attach_training_provider_evidence(uuid, integer, uuid, uuid, text) from public;
grant execute on function app.attach_training_provider_evidence(uuid, integer, uuid, uuid, text) to authenticated, service_role;

-- public.* wrapper (RGL-394 Option 2). `from anon, ...` rather than `from public` alone: Supabase's
-- ALTER DEFAULT PRIVILEGES grants anon EXECUTE explicitly at CREATE time, and an explicit grant
-- survives a PUBLIC revoke (ISS-2026-309).
create function public.attach_training_provider_evidence(p_provider_id uuid, p_expected_version integer, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_providers
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.attach_training_provider_evidence(p_provider_id, p_expected_version, p_evidence_file_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.attach_training_provider_evidence(uuid, integer, uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.attach_training_provider_evidence, never a reimplementation.';

revoke execute on function public.attach_training_provider_evidence(uuid, integer, uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.attach_training_provider_evidence(uuid, integer, uuid, uuid, text) to authenticated, service_role;
