-- RGL-394 Option-2 wrapper parity fix, self-found-and-fixed: every one of
-- this task's own new externally-callable app.* functions (granted to
-- authenticated and/or service_role) needs a matching public.* thin
-- security-definer pass-through wrapper -- the standing convention
-- 20260826000000_create_public_api_data_wrappers.sql established and
-- scripts/db-tests/public-api-wrapper-regression.sql exhaustively enforces
-- on every db-test run. Caught live by that exact file failing its own
-- first assertion. Mirrors the existing generator's shape verbatim for
-- each: `language sql`, matching volatility/security-definer mode, `set
-- search_path = pg_catalog, pg_temp`, a body that is nothing but `select
-- app.<fn>(...)`, an identical grant set (live-verified via has_function_
-- privilege against each app.* counterpart before writing each wrapper,
-- not assumed), and an explicit `revoke ... from public` before granting
-- -- the exact gap 20260902072600 just found and fixed for one of these
-- ten, applied here to all ten from the start.

create function public.staff_document_ticket_link_access_ok(p_actor_auth_user_id uuid, p_tenant_id uuid, p_uploaded_by_auth_user_id uuid, p_shared_org_unit_ids uuid[], p_customer_account_ref text, p_classification text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.staff_document_ticket_link_access_ok(p_actor_auth_user_id, p_tenant_id, p_uploaded_by_auth_user_id, p_shared_org_unit_ids, p_customer_account_ref, p_classification);
$wrap$;

comment on function public.staff_document_ticket_link_access_ok(p_actor_auth_user_id uuid, p_tenant_id uuid, p_uploaded_by_auth_user_id uuid, p_shared_org_unit_ids uuid[], p_customer_account_ref text, p_classification text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.staff_document_ticket_link_access_ok with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.staff_document_ticket_link_access_ok(p_actor_auth_user_id uuid, p_tenant_id uuid, p_uploaded_by_auth_user_id uuid, p_shared_org_unit_ids uuid[], p_customer_account_ref text, p_classification text) from public;
grant execute on function public.staff_document_ticket_link_access_ok(p_actor_auth_user_id uuid, p_tenant_id uuid, p_uploaded_by_auth_user_id uuid, p_shared_org_unit_ids uuid[], p_customer_account_ref text, p_classification text) to service_role;

create function public.set_loyalty_reward_voucher_value_config(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_voucher_value_type text, p_voucher_face_value numeric, p_voucher_percentage numeric, p_voucher_percentage_base_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_rewards
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.set_loyalty_reward_voucher_value_config(p_tenant_id, p_reward_id, p_expected_version, p_voucher_value_type, p_voucher_face_value, p_voucher_percentage, p_voucher_percentage_base_amount, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.set_loyalty_reward_voucher_value_config(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_voucher_value_type text, p_voucher_face_value numeric, p_voucher_percentage numeric, p_voucher_percentage_base_amount numeric, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.set_loyalty_reward_voucher_value_config with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.set_loyalty_reward_voucher_value_config(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_voucher_value_type text, p_voucher_face_value numeric, p_voucher_percentage numeric, p_voucher_percentage_base_amount numeric, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.set_loyalty_reward_voucher_value_config(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_voucher_value_type text, p_voucher_face_value numeric, p_voucher_percentage numeric, p_voucher_percentage_base_amount numeric, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;

create function public.set_loyalty_reward_auto_approve_customer_redemption(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_enabled boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_rewards
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.set_loyalty_reward_auto_approve_customer_redemption(p_tenant_id, p_reward_id, p_expected_version, p_enabled, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.set_loyalty_reward_auto_approve_customer_redemption(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_enabled boolean, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.set_loyalty_reward_auto_approve_customer_redemption with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.set_loyalty_reward_auto_approve_customer_redemption(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_enabled boolean, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.set_loyalty_reward_auto_approve_customer_redemption(p_tenant_id uuid, p_reward_id uuid, p_expected_version integer, p_enabled boolean, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;

create function public.set_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_principal_auth_user_id uuid, p_principal_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_redemption_auto_approval_principals
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.set_loyalty_redemption_auto_approval_principal(p_tenant_id, p_principal_auth_user_id, p_principal_label, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.set_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_principal_auth_user_id uuid, p_principal_label text, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.set_loyalty_redemption_auto_approval_principal with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.set_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_principal_auth_user_id uuid, p_principal_label text, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.set_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_principal_auth_user_id uuid, p_principal_label text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;

create function public.get_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_redemption_auto_approval_principals
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.get_loyalty_redemption_auto_approval_principal(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_loyalty_redemption_auto_approval_principal with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid) from public;
grant execute on function public.get_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;

create function public.clear_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns void
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.clear_loyalty_redemption_auto_approval_principal(p_tenant_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.clear_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.clear_loyalty_redemption_auto_approval_principal with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.clear_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.clear_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;

create function public.prepare_finance_liability_handoff_from_loyalty_liability(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_finance_liability_handoff_batches
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.prepare_finance_liability_handoff_from_loyalty_liability(p_tenant_id, p_run_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.prepare_finance_liability_handoff_from_loyalty_liability(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.prepare_finance_liability_handoff_from_loyalty_liability with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.prepare_finance_liability_handoff_from_loyalty_liability(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.prepare_finance_liability_handoff_from_loyalty_liability(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;

create function public.search_loyalty_finance_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.loyalty_finance_liability_handoff_batches
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.search_loyalty_finance_handoffs_pending_acknowledgement(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.search_loyalty_finance_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.search_loyalty_finance_handoffs_pending_acknowledgement with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.search_loyalty_finance_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid) from public;
grant execute on function public.search_loyalty_finance_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;

create function public.acknowledge_loyalty_finance_liability_handoff(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_finance_liability_handoff_batches
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.acknowledge_loyalty_finance_liability_handoff(p_batch_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.acknowledge_loyalty_finance_liability_handoff(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.acknowledge_loyalty_finance_liability_handoff with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.acknowledge_loyalty_finance_liability_handoff(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.acknowledge_loyalty_finance_liability_handoff(p_batch_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;

create function public.get_loyalty_finance_liability_handoff(p_batch_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_finance_liability_handoff_batches
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.get_loyalty_finance_liability_handoff(p_batch_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_loyalty_finance_liability_handoff(p_batch_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_loyalty_finance_liability_handoff with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_loyalty_finance_liability_handoff(p_batch_id uuid, p_actor_auth_user_id uuid) from public;
grant execute on function public.get_loyalty_finance_liability_handoff(p_batch_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
