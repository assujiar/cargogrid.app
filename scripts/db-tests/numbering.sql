-- Real, executable test evidence for PLT-125 (Numbering Engine, CG-S6-PLT-022).
--
-- This file also builds and proves the one safe, isolated, representative hook the
-- migration header discloses as deliberately NOT seeded as migration data: an
-- `INV-{YYYY}-{SEQ}` invoice-shaped numbering format. No format/definition row of any
-- kind exists anywhere in the migration itself.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001701', 'tenantadminnum@example.test'),
    ('00000000-0000-0000-0000-000000001702', 'regularusernum@example.test'),
    ('00000000-0000-0000-0000-000000001703', 'supremenum@example.test'),
    ('00000000-0000-0000-0000-000000001704', 'othertenantadminnum@example.test');

  perform app.provision_tenant('acmenum', 'Acme Numbering Co', 'idem-acmenum', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001701', 'tenantadminnum@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminnum@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001701', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001702', 'regularusernum@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularusernum@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001702', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001703', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmonum', 'Gizmo Numbering Co', 'idem-gizmonum', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmonum');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001704', 'othertenantadminnum@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminnum@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001704', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.format_numbering_value: pure token substitution over the fixed allowlist -- a real preview render, never an executable template'
do $$
declare
  v_result text;
begin
  v_result := app.format_numbering_value('INV-{YYYY}-{SEQ}', 42, 6, null, '2026-07-19T00:00:00Z'::timestamptz);
  if v_result <> 'INV-2026-000042' then
    raise exception 'assertion failed: expected INV-2026-000042, got %', v_result;
  end if;

  v_result := app.format_numbering_value('{SCOPE_CODE}-{MM}{DD}-{SEQ}', 7, 3, 'JKT', '2026-03-05T00:00:00Z'::timestamptz);
  if v_result <> 'JKT-0305-007' then
    raise exception 'assertion failed: expected JKT-0305-007, got %', v_result;
  end if;
end;
$$;

\echo '>> app.validate_numbering_definition / app.publish_numbering_definition: every structural failure mode is a distinct, named exception; a valid INV-{SCOPE_CODE}-{YYYY}-{SEQ} definition publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  v_draft := app.create_config_draft('numbering', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001701', 'tenant admin');

  -- numbering_missing_format
  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
    raise exception 'assertion failed: expected a draft with no format item to raise numbering_missing_format';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_missing_format%' then
        raise exception 'assertion failed: expected numbering_missing_format, got %', sqlerrm;
      end if;
  end;

  -- numbering_invalid_seq_token_count (zero occurrences)
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'format', 'value', 'INV-{YYYY}'),
    jsonb_build_object('key', 'reset_period', 'value', 'yearly'),
    jsonb_build_object('key', 'padding', 'value', 6)
  ), '00000000-0000-0000-0000-000000001701', 'tenant admin');
  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
    raise exception 'assertion failed: expected a format with zero {SEQ} tokens to raise numbering_invalid_seq_token_count';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_invalid_seq_token_count%' then
        raise exception 'assertion failed: expected numbering_invalid_seq_token_count, got %', sqlerrm;
      end if;
  end;

  -- numbering_invalid_seq_token_count (two occurrences)
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'format', 'value', 'INV-{SEQ}-{SEQ}'),
    jsonb_build_object('key', 'reset_period', 'value', 'yearly'),
    jsonb_build_object('key', 'padding', 'value', 6)
  ), '00000000-0000-0000-0000-000000001701', 'tenant admin');
  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
    raise exception 'assertion failed: expected a format with two {SEQ} tokens to raise numbering_invalid_seq_token_count';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_invalid_seq_token_count%' then
        raise exception 'assertion failed: expected numbering_invalid_seq_token_count, got %', sqlerrm;
      end if;
  end;

  -- numbering_unknown_token
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'format', 'value', 'INV-{BOGUS}-{SEQ}'),
    jsonb_build_object('key', 'reset_period', 'value', 'yearly'),
    jsonb_build_object('key', 'padding', 'value', 6)
  ), '00000000-0000-0000-0000-000000001701', 'tenant admin');
  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
    raise exception 'assertion failed: expected an unrecognized token to raise numbering_unknown_token';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_unknown_token%' then
        raise exception 'assertion failed: expected numbering_unknown_token, got %', sqlerrm;
      end if;
  end;

  -- numbering_invalid_reset_period
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'format', 'value', 'INV-{SEQ}'),
    jsonb_build_object('key', 'reset_period', 'value', 'quarterly'),
    jsonb_build_object('key', 'padding', 'value', 6)
  ), '00000000-0000-0000-0000-000000001701', 'tenant admin');
  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
    raise exception 'assertion failed: expected an invalid reset_period to raise numbering_invalid_reset_period';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_invalid_reset_period%' then
        raise exception 'assertion failed: expected numbering_invalid_reset_period, got %', sqlerrm;
      end if;
  end;

  -- numbering_invalid_padding
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'format', 'value', 'INV-{SEQ}'),
    jsonb_build_object('key', 'reset_period', 'value', 'yearly'),
    jsonb_build_object('key', 'padding', 'value', 0)
  ), '00000000-0000-0000-0000-000000001701', 'tenant admin');
  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
    raise exception 'assertion failed: expected padding=0 to raise numbering_invalid_padding';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_invalid_padding%' then
        raise exception 'assertion failed: expected numbering_invalid_padding, got %', sqlerrm;
      end if;
  end;

  -- Now the real, valid example: INV-{SCOPE_CODE}-{YYYY}-{SEQ}, yearly reset,
  -- padding 6. The {SCOPE_CODE} token is a deliberate part of this representative
  -- format, not decoration: it is what lets two different scope_key counters (e.g.
  -- two branches) render distinct, non-colliding numbers under the same tenant-wide
  -- definition, proven directly in the next scenario group. A format that omits
  -- {SCOPE_CODE} while still using multiple scope_key values would legitimately
  -- collide on app.numbering_allocations' own unique(tenant_id, formatted_number)
  -- constraint -- exactly the real, structural "collision analysis" this migration's
  -- own header discloses happens at allocation time, not merely at validation time.
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'format', 'value', 'INV-{SCOPE_CODE}-{YYYY}-{SEQ}'),
    jsonb_build_object('key', 'reset_period', 'value', 'yearly'),
    jsonb_build_object('key', 'padding', 'value', 6)
  ), '00000000-0000-0000-0000-000000001701', 'tenant admin');

  begin
    perform app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001702', null, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied publishing a tenant-scoped numbering definition';
  exception
    when insufficient_privilege then
      null;
  end;

  v_published := app.publish_numbering_definition(v_draft.id, '00000000-0000-0000-0000-000000001701', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid INV-{SCOPE_CODE}-{YYYY}-{SEQ} definition to publish, got %', v_published.status;
  end if;
end;
$$;

\echo '>> app.allocate_number: requires a published definition, is authority-gated, idempotent on (tenant_id, idempotency_key), and allocates a real, sequential, collision-free number'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_draft_version_id uuid;
  v_alloc1 app.numbering_allocations;
  v_alloc2 app.numbering_allocations;
  v_alloc3 app.numbering_allocations;
  v_alloc4 app.numbering_allocations;
  v_expected_year text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  v_expected_year := to_char(now(), 'YYYY');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'numbering' and o.scope_level = 'tenant' and v.status = 'published';

  v_draft_version_id := (app.create_config_draft('numbering', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001701', 'tenant admin')).id;
  begin
    perform app.allocate_number(v_draft_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009201', 'num-bad', '00000000-0000-0000-0000-000000001701', 'tenant admin');
    raise exception 'assertion failed: expected allocating against a non-published version to raise numbering_definition_not_published';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_definition_not_published%' then
        raise exception 'assertion failed: expected numbering_definition_not_published, got %', sqlerrm;
      end if;
  end;
  perform app.discard_config_draft(v_draft_version_id, '00000000-0000-0000-0000-000000001701', 'cleanup', 'tenant admin');

  begin
    perform app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009201', 'num-1', '00000000-0000-0000-0000-000000001704', 'other tenant admin');
    raise exception 'assertion failed: expected an identity with no membership in acmenum to be denied allocating there';
  exception
    when insufficient_privilege then
      null;
  end;

  v_alloc1 := app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009201', 'num-1', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_alloc1.seq <> 1 or v_alloc1.formatted_number <> ('INV-default-' || v_expected_year || '-000001') or v_alloc1.status <> 'allocated' then
    raise exception 'assertion failed: expected seq=1 formatted_number=INV-default-%-000001 status=allocated, got seq=% formatted_number=% status=%', v_expected_year, v_alloc1.seq, v_alloc1.formatted_number, v_alloc1.status;
  end if;

  v_alloc2 := app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009202', 'num-2', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_alloc2.seq <> 2 or v_alloc2.formatted_number <> ('INV-default-' || v_expected_year || '-000002') then
    raise exception 'assertion failed: expected the second allocation to be seq=2 (sequential, collision-free), got seq=% formatted_number=%', v_alloc2.seq, v_alloc2.formatted_number;
  end if;

  -- Idempotent replay: the same idempotency_key never consumes a second seq.
  v_alloc3 := app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009201', 'num-1', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_alloc3.id <> v_alloc1.id or v_alloc3.seq <> 1 then
    raise exception 'assertion failed: expected a repeated allocate_number call with the same idempotency_key to return the existing allocation, not consume a new seq';
  end if;

  -- A distinct scope_key gets its own independent counter, starting again at 1 --
  -- and, because this definition's format includes {SCOPE_CODE}, the rendered number
  -- is genuinely distinct from v_alloc1's (both are seq=1, but "default" vs.
  -- "branch-jkt" render differently), so no formatted_number collision occurs even
  -- though both counters independently reach seq=1.
  v_alloc4 := app.allocate_number(v_published_version_id, v_tenant_id, 'branch-jkt', 'invoice', null, 'num-jkt-1', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_alloc4.seq <> 1 or v_alloc4.formatted_number <> ('INV-branch-jkt-' || v_expected_year || '-000001') then
    raise exception 'assertion failed: expected a distinct scope_key to start its own counter at seq=1 and render as INV-branch-jkt-%-000001, got seq=% formatted_number=%', v_expected_year, v_alloc4.seq, v_alloc4.formatted_number;
  end if;
end;
$$;

\echo '>> app.reserve_number / app.confirm_number_reservation / app.release_number_reservation: the reserve/confirm/release alternative flow never recycles the consumed seq (Prompt 125 §22/§24)'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_reservation app.numbering_allocations;
  v_confirmed app.numbering_allocations;
  v_reservation2 app.numbering_allocations;
  v_released app.numbering_allocations;
  v_next_alloc app.numbering_allocations;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'numbering' and o.scope_level = 'tenant' and v.status = 'published';

  v_reservation := app.reserve_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009203', 'num-3', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_reservation.status <> 'reserved' or v_reservation.seq <> 3 then
    raise exception 'assertion failed: expected a reservation at status=reserved seq=3, got status=% seq=%', v_reservation.status, v_reservation.seq;
  end if;

  v_confirmed := app.confirm_number_reservation(v_reservation.id, '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_confirmed.status <> 'allocated' then
    raise exception 'assertion failed: expected confirming a reservation to move it to status=allocated';
  end if;

  begin
    perform app.confirm_number_reservation(v_confirmed.id, '00000000-0000-0000-0000-000000001702', 'regular user');
    raise exception 'assertion failed: expected confirming an already-allocated reservation to raise numbering_allocation_not_reserved';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_allocation_not_reserved%' then
        raise exception 'assertion failed: expected numbering_allocation_not_reserved, got %', sqlerrm;
      end if;
  end;

  v_reservation2 := app.reserve_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009204', 'num-4', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_reservation2.seq <> 4 then
    raise exception 'assertion failed: expected the next reservation to consume seq=4 (reservations consume real seq values, same counter as allocate_number)';
  end if;

  v_released := app.release_number_reservation(v_reservation2.id, '00000000-0000-0000-0000-000000001701', 'tenant admin', 'order cancelled before confirmation');
  if v_released.status <> 'released' or v_released.voided_at is null then
    raise exception 'assertion failed: expected status=released with voided_at set';
  end if;

  -- The next real allocation must be seq=5, never reusing the released seq=4 (Prompt 125 §24: "not silently recycled").
  v_next_alloc := app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009205', 'num-5', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_next_alloc.seq <> 5 then
    raise exception 'assertion failed: expected the next allocation to be seq=5, never reusing the released seq=4, got seq=%', v_next_alloc.seq;
  end if;
end;
$$;

\echo '>> app.void_number_allocation: an allocated (confirmed) number can be voided with a mandatory reason; the seq is never reused'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_alloc app.numbering_allocations;
  v_voided app.numbering_allocations;
  v_next_alloc app.numbering_allocations;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'numbering' and o.scope_level = 'tenant' and v.status = 'published';

  v_alloc := app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009206', 'num-6', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_alloc.seq <> 6 then
    raise exception 'assertion failed (test setup): expected seq=6 at this point, got %', v_alloc.seq;
  end if;

  begin
    perform app.void_number_allocation(v_alloc.id, '00000000-0000-0000-0000-000000001701', 'tenant admin', null);
    raise exception 'assertion failed: expected voiding with a null reason to raise numbering_void_reason_required';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_void_reason_required%' then
        raise exception 'assertion failed: expected numbering_void_reason_required, got %', sqlerrm;
      end if;
  end;

  v_voided := app.void_number_allocation(v_alloc.id, '00000000-0000-0000-0000-000000001701', 'tenant admin', 'customer disputed and cancelled');
  if v_voided.status <> 'voided' or v_voided.voided_reason <> 'customer disputed and cancelled' then
    raise exception 'assertion failed: expected status=voided with the given reason recorded';
  end if;

  begin
    perform app.void_number_allocation(v_voided.id, '00000000-0000-0000-0000-000000001701', 'tenant admin', 'again');
    raise exception 'assertion failed: expected voiding an already-voided allocation to raise numbering_allocation_not_allocated';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_allocation_not_allocated%' then
        raise exception 'assertion failed: expected numbering_allocation_not_allocated, got %', sqlerrm;
      end if;
  end;

  v_next_alloc := app.allocate_number(v_published_version_id, v_tenant_id, 'default', 'invoice', '00000000-0000-0000-0000-000000009207', 'num-7', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_next_alloc.seq <> 7 then
    raise exception 'assertion failed: expected the next allocation to be seq=7, never reusing the voided seq=6, got seq=%', v_next_alloc.seq;
  end if;
end;
$$;

\echo '>> app.bootstrap_numbering_counter: seeds a counter''s last-used value directly, structurally refuses to lower it, and the next real allocation starts above the verified legacy maximum'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_counter app.numbering_counters;
  v_next_alloc app.numbering_allocations;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'numbering' and o.scope_level = 'tenant' and v.status = 'published';

  begin
    perform app.bootstrap_numbering_counter(v_published_version_id, 'legacy-import', to_char(now(), 'YYYY'), 5000, '00000000-0000-0000-0000-000000001702', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied bootstrapping a counter';
  exception
    when insufficient_privilege then
      null;
  end;

  v_counter := app.bootstrap_numbering_counter(v_published_version_id, 'legacy-import', to_char(now(), 'YYYY'), 5000, '00000000-0000-0000-0000-000000001701', 'tenant admin');
  if v_counter.next_seq <> 5000 then
    raise exception 'assertion failed: expected the bootstrapped counter to hold next_seq=5000, got %', v_counter.next_seq;
  end if;

  begin
    perform app.bootstrap_numbering_counter(v_published_version_id, 'legacy-import', to_char(now(), 'YYYY'), 100, '00000000-0000-0000-0000-000000001701', 'tenant admin');
    raise exception 'assertion failed: expected lowering an already-bootstrapped counter to raise numbering_counter_cannot_decrease';
  exception
    when check_violation then
      if sqlerrm not like 'numbering_counter_cannot_decrease%' then
        raise exception 'assertion failed: expected numbering_counter_cannot_decrease, got %', sqlerrm;
      end if;
  end;

  v_next_alloc := app.allocate_number(v_published_version_id, v_tenant_id, 'legacy-import', 'invoice', null, 'num-legacy-1', '00000000-0000-0000-0000-000000001702', 'regular user');
  if v_next_alloc.seq <> 5001 then
    raise exception 'assertion failed: expected the first real allocation after bootstrap to be seq=5001 (never reusing the legacy maximum), got %', v_next_alloc.seq;
  end if;
end;
$$;

\echo '>> app.get_numbering_allocation_status: authority-gated read; cross-tenant isolation on allocations'
do $$
declare
  v_tenant_id uuid;
  v_allocation_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');
  select id into v_allocation_id from app.numbering_allocations where tenant_id = v_tenant_id and idempotency_key = 'num-1';

  begin
    perform app.get_numbering_allocation_status(v_allocation_id, '00000000-0000-0000-0000-000000001704');
    raise exception 'assertion failed: expected an identity with no membership in acmenum to be denied reading allocation status';
  exception
    when insufficient_privilege then
      null;
  end;

  if (app.get_numbering_allocation_status(v_allocation_id, '00000000-0000-0000-0000-000000001702')).formatted_number is null then
    raise exception 'assertion failed: expected a real formatted_number to be returned for an authorized reader';
  end if;
end;
$$;

\echo '>> every numbering lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table for this capability)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['allocate_number', 'reserve_number', 'confirm_number_reservation', 'release_number_reservation', 'void_number_allocation', 'bootstrap_numbering_counter'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenum');

  foreach v_action in array v_actions loop
    select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_id and action = v_action;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has direct RLS-scoped SELECT on numbering_allocations but none on numbering_counters; anon holds no EXECUTE on service_role-only mutations (ERR-2026-004 regression guard)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.numbering_allocations', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.numbering_allocations';
  end if;

  select has_table_privilege('authenticated', 'app.numbering_counters', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT on app.numbering_counters';
  end if;

  select has_table_privilege('anon', 'app.numbering_allocations', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.numbering_allocations at all';
  end if;

  select has_function_privilege('authenticated', 'app.get_numbering_allocation_status(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.get_numbering_allocation_status';
  end if;

  select has_function_privilege('authenticated', 'app.format_numbering_value(text, integer, integer, text, timestamptz)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.format_numbering_value (a pure, side-effect-free preview)';
  end if;

  select has_function_privilege('anon', 'app.allocate_number(uuid, uuid, text, text, uuid, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.allocate_number (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.bootstrap_numbering_counter(uuid, text, text, integer, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.bootstrap_numbering_counter (ERR-2026-004 regression guard)';
  end if;
end;
$$;
