-- Closes `ISS-2026-058`: `262_VENDOR_CAPACITY_AVAILABILITY_PROMPT.md` §22 names "manual
-- confirmation with evidence" as a required alternative flow, and nothing implemented it.
-- Grep-confirmed at the time and again now: `20260730710000_create_procurement_vendor_capacity.sql`
-- contains zero references to evidence, file_id, attachment or initiate_file_upload. The
-- capability's own Tier B self-check marked taxonomy class C-10 (file/evidence linking) "N/A" for
-- this domain, which is how a named requirement went missing without anyone noticing.
--
-- WHY THIS IS SMALLER THAN THE ENTRY EXPECTED
--
--   The entry calls this "an architectural decision touching the Document/File Engine". It is
--   not, and the reason is worth stating: `app.files.record_type` is **unconstrained polymorphic
--   text** (`20260719140000:334`), not an enum. PLT-128 was built so a domain could attach
--   evidence without the file engine changing at all. So this needs no file-engine migration and
--   no new vocabulary — only the columns that record WHICH confirmation happened, and an RPC that
--   validates the evidence properly.
--
-- THE REAL DISTINCTION BEING RECORDED, WHICH IS WHY THIS IS NOT JUST A NULLABLE FILE COLUMN
--
--   A reservation reaching `accepted` today means one thing: the vendor accepted it in the
--   system, and the system watched that happen. §22's manual path means something materially
--   weaker — somebody asserts the vendor agreed, out of band, and attaches a document as
--   evidence. Both are legitimate; they are not the same claim.
--
--   Storing only a nullable `evidence_file_id` would blur them: a null could mean "system accept"
--   or "manual confirmation where somebody forgot the file". `confirmation_method` is NOT NULL
--   with a default, so every accepted reservation states which of the two it is, and a CHECK
--   makes a manual confirmation without evidence impossible rather than merely discouraged.
--
--   That matters commercially, not just tidily: a disputed reservation is exactly the case where
--   "did the vendor really agree, and how do we know?" gets asked, and the answer has to be in
--   the record rather than in somebody's memory of which path was used.

alter table app.vendor_capacity_reservations
  add column if not exists confirmation_method text not null default 'system_accept',
  add column if not exists confirmation_evidence_file_id uuid references app.files (id),
  add column if not exists confirmation_note text,
  add column if not exists confirmed_by_auth_user_id uuid references auth.users (id),
  add column if not exists confirmed_at timestamptz;

alter table app.vendor_capacity_reservations
  add constraint vendor_capacity_reservations_confirmation_method_check
  check (confirmation_method in ('system_accept', 'manual_with_evidence'));

-- The constraint that makes the distinction real rather than advisory. A manual confirmation is
-- only worth recording as one if the evidence and the confirming identity are both present.
alter table app.vendor_capacity_reservations
  add constraint vendor_capacity_reservations_manual_evidence_check
  check (
    confirmation_method <> 'manual_with_evidence'
    or (confirmation_evidence_file_id is not null and confirmed_by_auth_user_id is not null and confirmed_at is not null)
  );

comment on column app.vendor_capacity_reservations.confirmation_method is
  'ISS-2026-058 (Prompt 262 §22). system_accept = the vendor accepted in the system and the system watched it happen. manual_with_evidence = somebody asserts the vendor agreed out of band and attached a document. NOT NULL with a default on purpose: a nullable evidence file alone would blur "system accept" with "manual confirmation where the file was forgotten", and those are different claims about how much the platform actually knows.';

comment on column app.vendor_capacity_reservations.confirmation_evidence_file_id is
  'ISS-2026-058: the app.files row backing a manual confirmation. Mandatory for confirmation_method = manual_with_evidence, enforced by vendor_capacity_reservations_manual_evidence_check rather than by the RPC alone. app.files.record_type is unconstrained polymorphic text (PLT-128, 20260719140000:334), so this needed no file-engine change -- the engine was built for exactly this.';

comment on table app.vendor_capacity_reservations is
  'PRC-262: one row per commitment held against an offer''s own declared quantity. "active" (still consuming capacity) = status in (held, accepted, consumed); declined/released free the capacity back. requested_quantity is always in the parent offer''s own uom (design note 3). ISS-2026-058 (20260831150000): a reservation can now reach accepted by either of the two routes §22 names -- app.accept_vendor_capacity_reservation (the vendor accepted in the system) or app.confirm_vendor_capacity_reservation_manually (somebody attests the vendor agreed out of band, with a real scanned evidence file). confirmation_method records which, always.';

-- The existing system path now states what it always meant, rather than leaving it implied.
create or replace function app.accept_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be accepted', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations
  set status = 'accepted',
      confirmation_method = 'system_accept',
      confirmed_by_auth_user_id = p_actor_auth_user_id,
      confirmed_at = now()
  where id = p_reservation_id and record_version = p_expected_version
  returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('confirmation_method', 'system_accept')
  );

  return v_reservation;
end;
$$;

comment on function app.accept_vendor_capacity_reservation is
  'PRC-262 §21 main flow: the vendor accepts a held reservation in the system. ISS-2026-058 (20260831150000): now stamps confirmation_method = system_accept explicitly, so the record distinguishes this from the §22 manual path rather than leaving it inferable from a null evidence file.';

create function app.confirm_vendor_capacity_reservation_manually(
  p_reservation_id uuid,
  p_expected_version integer,
  p_evidence_file_id uuid,
  p_confirmation_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
  v_file app.files;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be confirmed', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is null then
    raise exception 'confirmation_evidence_required: a manual confirmation must attach the evidence it rests on'
      using errcode = 'check_violation';
  end if;
  if p_confirmation_note is null or length(trim(p_confirmation_note)) = 0 then
    raise exception 'confirmation_note_required: a manual confirmation must state what was agreed and with whom'
      using errcode = 'check_violation';
  end if;

  -- Re-validate tenant, record scope and scan status at THIS accepting RPC (taxonomy C-10) --
  -- never trust a caller's prior upload success as still valid. Byte-for-byte the shape
  -- app.complete_onboarding_task already established for evidence files.
  select * into v_file from app.files where id = p_evidence_file_id;
  if not found
     or v_file.tenant_id <> v_reservation.tenant_id
     or v_file.record_type <> 'vendor_capacity_reservation'
     or v_file.record_id <> p_reservation_id
  then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file for reservation %', p_evidence_file_id, p_reservation_id
      using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations
  set status = 'accepted',
      confirmation_method = 'manual_with_evidence',
      confirmation_evidence_file_id = p_evidence_file_id,
      confirmation_note = trim(p_confirmation_note),
      confirmed_by_auth_user_id = p_actor_auth_user_id,
      confirmed_at = now()
  where id = p_reservation_id and record_version = p_expected_version
  returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_vendor_capacity_reservation_manually',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('confirmation_method', 'manual_with_evidence', 'evidence_file_id', p_evidence_file_id)
  );

  return v_reservation;
end;
$$;

comment on function app.confirm_vendor_capacity_reservation_manually is
  'ISS-2026-058, Prompt 262 §22 "manual confirmation with evidence". Reaches the same accepted status as app.accept_vendor_capacity_reservation but records a materially weaker claim: somebody attests the vendor agreed OUT OF BAND, and attaches the document that says so. Both the evidence file and a note describing what was agreed are mandatory -- an attestation with no evidence and no account of what happened is not a confirmation, it is a status change. The file is re-validated here (tenant, record scope, malware-scan status) rather than trusted from its upload, the taxonomy C-10 discipline app.complete_onboarding_task already established: a file that was clean at upload may not be clean now, and one uploaded against a different record must never be accepted as evidence for this one.';

revoke execute on function app.confirm_vendor_capacity_reservation_manually(uuid, integer, uuid, text, uuid, text) from public;
grant execute on function app.confirm_vendor_capacity_reservation_manually(uuid, integer, uuid, text, uuid, text) to authenticated, service_role;

-- public.* wrapper (RGL-394 Option 2). `from anon, ...` rather than `from public` alone: Supabase's
-- ALTER DEFAULT PRIVILEGES grants anon EXECUTE explicitly at CREATE time, and an explicit grant
-- survives a PUBLIC revoke (ISS-2026-309).
create function public.confirm_vendor_capacity_reservation_manually(
  p_reservation_id uuid, p_expected_version integer, p_evidence_file_id uuid,
  p_confirmation_note text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_capacity_reservations
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.confirm_vendor_capacity_reservation_manually(p_reservation_id, p_expected_version, p_evidence_file_id, p_confirmation_note, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.confirm_vendor_capacity_reservation_manually(uuid, integer, uuid, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.confirm_vendor_capacity_reservation_manually, never a reimplementation.';

revoke execute on function public.confirm_vendor_capacity_reservation_manually(uuid, integer, uuid, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.confirm_vendor_capacity_reservation_manually(uuid, integer, uuid, text, uuid, text) to authenticated, service_role;
