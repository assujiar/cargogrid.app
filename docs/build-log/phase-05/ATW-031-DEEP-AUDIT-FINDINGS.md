# ATW-031 — Deep Audit Finding Register (UNVERIFIED CANDIDATES)

**Task:** `CG-S10-ATW-031` (post-Prompt-248 codebase audit)  
**Produced by:** a 12-way parallel adversarial audit fan-out over the whole repository.  
**Status:** **CANDIDATE FINDINGS — NOT INDIVIDUALLY VERIFIED.**

## Why this file exists, and how to read it

The audit's finder phase completed and produced the findings below. Its adversarial
**verification phase did not run** — the workflow stalled before it. Everything here is
therefore a *claim by a finder agent*, not a confirmed defect, and must be independently
re-derived from the code before anyone acts on it.

That caveat is load-bearing. `ATW-030` and `ATW-031` both demonstrated that this
repository's real defects survive precisely because plausible-sounding reasoning goes
unchecked: `ISS-2026-024` was recorded for months as a timing flake on the strength of a
hypothesis nobody re-derived, and it was a deterministic product defect. The same
discipline applies in reverse — do not treat any row below as real until you have
reproduced it.

**What HAS been verified:** the four authorization findings named in `ISS-2026-033` were
spot-checked directly against the live schema during `ATW-031` and are structurally
confirmed (SECURITY DEFINER, granted to `authenticated`, no authority helper anywhere in
the body). Nothing else in this file has been checked.

**Counts:** 64 candidates — 10 critical, 29 high, 22 medium, 3 low.

## Findings

### CRITICAL

#### app.consume_inventory_reservation posts the negative movement before releasing `reserved`, so a fully-reserved balance can never be consumed

- **File:** `/home/user/cargogrid.app/supabase/migrations/20260730280000_harden_advanced_tms_inventory_balances_reservation_record_version.sql`:257
- **Symbol:** `app.consume_inventory_reservation`
- **Category:** correctness

**Claim.** `app.consume_inventory_reservation` calls `app.post_inventory_movement(...)` (line 243-251) to post the `-reserved_quantity` line FIRST, and only then runs `update app.inventory_balances set reserved = reserved - v_reservation.reserved_quantity ...` (line 257). `app.inventory_balances` carries a non-deferrable table CHECK `inventory_balances_reserved_held_bound_check check (reserved + held <= on_hand)` (20260730190000 line 153). At the moment the movement's UPDATE lowers `on_hand`, `reserved` is still at its pre-consume value, so the constraint is evaluated against the stale pair. The invariant only survives when `on_hand - reserved - held >= 2 * reserved_quantity`, i.e. only when at least as much free stock exists as is being consumed. The repository elsewhere knows the correct order: `app.confirm_wms_pick_task` explicitly comments "Design note 4: the exact statement order the reservation/transfer interaction requires -- reduce reserved FIRST, then post the transfer" (20260730240000 line ~1347) and does exactly that. The db-test only exercises the safe case (on_hand=30, reserve 10), so the defect is invisible to `pnpm run db:test`. The TS wrapper `consumeInventoryReservation` (server/mutations/inventory-ledger.ts line 178) has no classifier entry for a raw check violation, so the caller receives an opaque `mutation_failed`.

**Claimed failure scenario.** Reproduced on a scratch DB with all migrations applied. Balance SKU-INV-A1 @ BIN-1: on_hand=20, reserved=0, available=20. `app.reserve_inventory(..., 20, 'manual', null, 'k1', ...)` succeeds -> reserved=20, available=0. `app.consume_inventory_reservation(<reservation>, 'k2', ...)` then fails with `sqlstate=23514 message=new row for relation "inventory_balances" violates check constraint "inventory_balances_reserved_held_bound_check"`. The reservation is permanently stuck in status='active' -- every retry raises the same raw error, so the reserved 20 units can never be consumed and can only be abandoned via `release_inventory_reservation` (which returns the stock to available instead of shipping it). Any caller that reserves the whole available quantity -- the ordinary "allocate this line in full" case -- hits this on 100% of consume attempts.

**Proposed fix.** Swap the statement order in `app.consume_inventory_reservation`: run `update app.inventory_balances set reserved = reserved - v_reservation.reserved_quantity, updated_at = now(), record_version = record_version + 1 where id = v_reservation.balance_id;` BEFORE calling `app.post_inventory_movement`, exactly as `app.confirm_wms_pick_task` already does. Add a db-test case that reserves the full available quantity and then consumes it.

#### Ordinary tenant members can act as tenant_admin on vendor rate approvals: app.approve_rate_version trusts the caller-supplied p_actor_auth_user_id and app.users_directory/app.role_assignments hand out the admin's UUID

- **File:** `supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql`:315
- **Symbol:** `app.approve_rate_version`
- **Category:** privilege-escalation

**Claim.** `app.approve_rate_version` (and its siblings `create_rate_version` line 222, `reject_rate_version` line 363, `withdraw_rate_version` line 417) are SECURITY DEFINER, granted to `authenticated` (lines 714-717), and their ONLY authority gate is `app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id)` — i.e. "is the identity NAMED IN THE CALL a Supreme Admin or tenant_admin", never "is the connected session that identity". Unlike the vast majority of RPCs in this repo these carry no second `evaluate_permission`/`can_access_record` gate that would independently constrain the caller. The missing auth.uid() cross-check (ISS-2026-017) is only exploitable if an attacker can discover a privileged UUID; here they can: `app.users_directory` is `grant select … to authenticated` and exposes `auth_user_id` + `display_name` for every user of any tenant the caller is a member of, and `app.role_assignments` carries policy `role_assignments_select_own_tenant` (`using app.has_active_tenant_membership(tenant_id)`) exposing auth_user_id → role_version_id. The audit event written at the end of the function records `p_actor_auth_user_id`, so the forged action is attributed to the impersonated admin.

**Claimed failure scenario.** Verified live against a scratch DB. Tenant E has admin `bbbb…000a` (active `principal_memberships` row, layer `tenant_admin`) and sales rep `bbbb…000b` (active `tenant_user_identities` row only; `app.is_support_grant_authority('bbbb…000b', tenant) = false`). Vendor rate version 7777…0001 sits at `pending_approval`, record_version 1, base_amount 1,000,000 IDR. As role `authenticated`, the rep runs `select * from app.approve_rate_version('7777…0001', 1, 'bbbb…000a', 'Rex Rep')` — the UUID obtained from `select auth_user_id, display_name from app.users_directory`. Result: approval_status becomes `approved`, record_version 2, and `app.audit_logs` records actor_auth_user_id = `bbbb…000a` (the admin) with result `success`. A rep with no approval authority has published a vendor buy rate and the audit trail blames the admin.

**Proposed fix.** Inside these four functions, reject the call when `p_actor_auth_user_id is distinct from auth.uid()` for any non-service_role caller (or drop `authenticated` from the grants at lines 714-717 and route them through the server's service-role client after the Server Action has verified the session), so the claimed actor can no longer differ from the connected principal.

#### app.recalculate_quotation_totals is SECURITY DEFINER with zero authority check yet granted to `authenticated`, giving any logged-in user write access to any tenant's quotation money columns

- **File:** `supabase/migrations/20260724210000_create_commercial_quotation_builder.sql`:180
- **Symbol:** `app.recalculate_quotation_totals`
- **Category:** tenant-isolation

**Claim.** The function is declared `security definer` (runs as the table owner, bypassing RLS), takes only `p_quotation_id`, and performs `update app.quotations set subtotal_amount/discount_amount/tax_amount/total_amount, updated_at = now(), record_version = record_version + 1 where id = p_quotation_id` (line 202). It resolves no tenant, calls no `app.evaluate_permission`, no `app.can_access_record`, and takes no actor parameter at all. It also has no status/`is_current` guard, so it writes to `submitted`, `cancelled` and superseded historical versions that every other mutation explicitly refuses to touch. Its own header comment at lines 176-178 states the opposite of what the migration does: "Never exposed directly to `authenticated` (internal helper, called only from the mutation functions below, all of which already hold the caller's authority)" — yet line 924 issues `grant execute on function app.recalculate_quotation_totals(uuid) to authenticated, service_role;`. Because `NEXT_PUBLIC_SUPABASE_ANON_KEY` is a browser-shipped public key (lib/supabase/server.ts), any account holder can reach this over PostgREST `/rpc/recalculate_quotation_totals` directly.

**Claimed failure scenario.** Verified live against a scratch DB with all 143 migrations applied. Tenant V has quotation 5555…5555, status `submitted`, subtotal/total 100000.00, record_version 7. A session with role `authenticated` and no membership in any tenant runs `select * from app.recalculate_quotation_totals('5555…5555')` twice. Result: the row is rewritten to subtotal_amount 0.00, total_amount 0.00 and record_version 9, with no audit_logs entry. Tenant V's owner, whose UI holds version 7, then calls `app.submit_quotation(id, 7, …)` or `app.cancel_quotation(id, 7, …)` and gets `stale_version`; the attacker can repeat indefinitely, permanently wedging every optimistic-concurrency-guarded operation on that quotation. Only the quotation UUID is needed, and no membership, role, or permission of any kind is checked.

**Proposed fix.** Remove `authenticated` from the grant on line 924 (make it service_role-only, matching the function's own documented intent), or, if it must stay reachable, add `p_actor_auth_user_id` plus the same `app.evaluate_permission(actor, v_quotation.tenant_id, 'COM', 'Edit')` + `app.can_access_record(...)` pair every other quotation mutation in this file already performs, and a `status = 'draft' and is_current` guard.

#### accounts_select_scoped is tenant-wide only — a customer-portal principal reads every other customer's account master data, and branch isolation is dropped for staff

- **File:** `supabase/migrations/20260724290000_create_commercial_customer_account_conversion.sql`:415
- **Symbol:** `accounts_select_scoped`
- **Category:** tenant-isolation

**Claim.** The effective policy is `create policy accounts_select_scoped on app.accounts for select to authenticated using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())`. `app.has_active_tenant_membership` (supabase/migrations/20260716111315_create_support_access.sql:285) is layer-blind: it only checks for an `active` row in `app.tenant_user_identities`. `app.invite_user` -> `app.link_auth_identity` + `app.transition_user_status(...,'active',...)` creates exactly such a row for a customer-portal user — this is the exact provisioning sequence scripts/db-tests/advanced-tms-customer-inventory-access.sql:71-93 uses for its four live `customer_user` principals. So `has_active_tenant_membership` returns TRUE for a customer_user, and the policy admits every account row in the tenant.

Two separate scopes are lost:
(1) Customer scope. `app.accounts` carries every customer's `legal_name`, `trade_name`, `tax_id`, `billing_address`, `duplicate_fingerprint`, `parent_account_id`. `app.principal_memberships.customer_account_ref` is literally `app.accounts.id::text` (design note 6b of ATW-016), i.e. this table IS the owner-scope anchor for the whole customer-portal model, yet it has no owner-scope branch at all.
(2) Org-unit/branch scope. `app.accounts` carries populated `owner_user_id` and `org_unit_id` (set at 20260724290000:316-321 and 20260725090000:141-146), and `app.resolve_commercial_record_ref` (20260724290000:~380) has a dedicated `'account'` branch returning exactly `(tenant_id, owner_user_id, org_unit_id)` for record-scoping. Every sibling commercial table uses them — `leads_select_scoped`, `prospects_select_scoped`, `opportunities_select_scoped`, `quotations_select_scoped`, `contacts_select_scoped`, `activities_select_scoped`, `sales_plans_select_scoped`, `sales_targets_select_scoped`, `costing_requests_select_scoped` all use `app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)`. `accounts_select_scoped` is the one that ignores them.

docs/architecture/06_RLS_RBAC_WORKSTREAM.md:194 designates this table `customer_portal_scoped prep on customers`, and line 87 defines `customer_portal_scoped` as scope key `tenant_id + customer_account_id`, never `tenant_id` alone.

This is live, not theoretical: lib/supabase/server.ts:37 builds an RLS-scoped anon-key client and server/queries/account.ts:30 reads `client.from("accounts").select("*").eq("tenant_id", tenantId)` through it — the `.eq()` is a client-supplied filter, not an authorization boundary, and a browser holding the session JWT can hit PostgREST `/rest/v1/accounts?select=*` directly.

**Claimed failure scenario.** Reproduced on a scratch DB with all 141 migrations applied. Tenant `probe1` has two customer accounts, `Probe Alpha Ltd` (billing_address `{"street":"alpha secret st"}`) and `Probe Beta Ltd` (`{"street":"beta secret st"}`). Auth user `...ff002` is invited, activated, then granted `app.grant_principal_membership('...ff002','customer_user', probe1, <Alpha.id>::text, 'tester')` — scoped to Alpha only. Then `set local role authenticated; set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000ff002","role":"authenticated"}'; select legal_name, billing_address from app.accounts;` returns BOTH rows, including `Probe Beta Ltd | {"street": "beta secret st"}`. `app.resolve_actor_owner_account_scope` correctly reports this actor's scope as `{<Alpha.id>}`, so the owner-scope machinery exists and is correct — the policy simply never calls it. Expected: 1 row (Alpha). Actual: 2 rows.

**Proposed fix.** Add a new migration that does `drop policy accounts_select_scoped on app.accounts; create policy accounts_select_scoped on app.accounts for select to authenticated using (app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), id::text));` — passing `id::text` as `p_customer_account_ref` gives a customer_user exactly their own account row (matching the `customer_account_ref = owner_account_id::text` convention already used everywhere else) while restoring the same owner/org-unit scoping every sibling commercial table already has. Apply the same shape to `account_conversions_select_scoped` (same file, line 419), which joins to `account_id` and has the identical tenant-only expression.

#### transition_shipment_order replay short-circuit has no target discriminator and precedes the record_version check — requested transitions are silently skipped

- **File:** `supabase/migrations/20260727110000_create_operations_shipment_lifecycle.sql`:131
- **Symbol:** `app.transition_shipment_order`
- **Category:** idempotency-target-mismatch

**Claim.** The short-circuit at lines 131-135 selects on `(tenant_id, shipment_order_id, idempotency_key)` and returns the freshly-read `v_shipment` unchanged. Missing discriminator columns: `to_status` (and `from_status`, i.e. whether the stored transition's `from_status` still matches the shipment's current status). This is the SILENT NO-OP shape the 20260730380000 WMS hardening migration closed for `confirm_wms_pick_task`/`load_wms_outbound_shipment` etc.; it was never applied here. Worse, the short-circuit sits BEFORE the `record_version <> p_expected_version` check at line 137, so a key collision also bypasses the documented optimistic-concurrency guard. Reachability is not theoretical: `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx:295` generates ONE `transitionIdempotencyKey = randomUUID()` per render and binds that single key to every button `permittedNextStatuses()` renders (from 'confirmed' that is held, cancelled AND planned — three different `to_status` values sharing one key).

**Claimed failure scenario.** LIVE-REPRODUCED. Shipment SHP-2026-000001 at status 'delivered', record_version 12, with an existing transition row carrying key K (from its earlier confirmed->planned move). Call `app.transition_shipment_order(S, 'cancelled', 12, 'need to cancel', null, K, actor, 'Rep A')`. Output: no exception, the function returns a row with `status = 'delivered'`, `app.shipment_orders.status` is unchanged, and no `delivered->cancelled` history row exists. The TS wrapper (server/mutations/shipment-lifecycle.ts) parses that row and returns it as a successful mutation; the UI reports success and the cancel never happened.

**Proposed fix.** Follow the ATW-030 pattern: after `if found`, raise `idempotency_key_conflict` (errcode `unique_violation`) when `v_existing_transition.to_status <> p_to_status or v_existing_transition.from_status <> v_shipment.status`; only replay when the target genuinely matches. Also move the short-circuit after the `record_version` check, and give each transition button in page.tsx its own key.

#### publish_milestone_template_version archives the supersede target with no tenant or mode check — cross-tenant write

- **File:** `supabase/migrations/20260727140000_create_operations_milestone_management.sql`:335
- **Symbol:** `app.publish_milestone_template_version`
- **Category:** tenant-isolation

**Claim.** The supersede branch does `select * into v_superseded from app.milestone_template_versions where id = p_supersedes_version_id;` (line 335) and then `update app.milestone_template_versions set status = 'archived' where id = p_supersedes_version_id;` (line 340). Neither statement constrains `tenant_id` to `v_version.tenant_id`, nor `mode` to `v_version.mode`. The only authority check performed (line 328) is `OPS:Edit` for the *publishing* tenant. `p_supersedes_version_id` is an unvalidated caller-supplied uuid, and the function is granted to `authenticated` (line 714). The resulting row also stores a cross-tenant FK in `supersedes_version_id`.

**Claimed failure scenario.** LIVE-REPRODUCED on a freshly migrated DB. Tenant B has a published 'land' milestone template V_B. An ordinary OPS:Edit user of tenant A calls `app.create_milestone_template_draft(A,'land',...)`, `app.set_milestone_template_sequence(...)`, then `app.publish_milestone_template_version(draft_A, ver, V_B, actorA, 'Rep A')`. Output: tenant A's template publishes successfully with `supersedes_version_id = V_B`, tenant B's V_B `status` flips to `archived`, and `select count(*) from app.milestone_template_versions where tenant_id = B and mode='land' and status='published'` drops to 0. Tenant B silently loses its published expected-milestone sequence; tenant A never sees an error.

**Proposed fix.** Add `and tenant_id = v_version.tenant_id and mode = v_version.mode` to the lookup at line 335, and raise `milestone_template_not_found` (or a dedicated `supersedes_target_mismatch`) when the target belongs to another tenant or another mode.

#### dispatch_shipment_order records a completed dispatch while the shipment never leaves 'assigned'

- **File:** `supabase/migrations/20260727160000_create_operations_basic_dispatch.sql`:207
- **Symbol:** `app.dispatch_shipment_order`
- **Category:** correctness

**Claim.** Line 207 forwards the caller's `p_idempotency_key` verbatim into `app.transition_shipment_order(..., 'dispatched', ...)`, and then unconditionally inserts an `app.dispatch_commands` row using the *same* key. `app.transition_shipment_order`'s replay short-circuit (20260727110000, lines 131-135) matches on `(tenant_id, shipment_order_id, idempotency_key)` only — it does not compare `to_status`. So a key already consumed by ANY earlier transition on that shipment makes the nested transition a silent no-op, but `dispatch_shipment_order` still writes its history row and returns it as success. The two key namespaces are shared but the tables are different, so no unique constraint catches it.

**Claimed failure scenario.** LIVE-REPRODUCED. Shipment S: confirmed->planned transitioned with idempotency key 'SHARED-KEY-2'; planned->assigned with 'k-assigned-2'; an active vendor assignment and planned_pickup_at set, so `evaluate_dispatch_readiness` returns `{"is_ready":true,"blockers":[]}`. Operator then calls `app.dispatch_shipment_order(S, 4, 'SHARED-KEY-2', actor, 'Rep A')`. Result: a fully populated `app.dispatch_commands` row is written (`dispatched_at` set, `readiness_snapshot` is_ready=true), NO exception is raised, but `app.shipment_orders.status` is still `assigned` and `select count(*) from app.shipment_status_transitions where shipment_order_id=S and to_status='dispatched'` = 0. The truck is recorded as dispatched in dispatch history while the canonical lifecycle never moved; the shipment stays in `app.dispatch_ready_queue` forever and every downstream consumer (billing readiness, public tracking) still sees it as awaiting dispatch.

**Proposed fix.** Derive a distinct key for the nested transition (e.g. `p_idempotency_key || ':dispatch'`), and make `app.dispatch_shipment_order` verify the transition actually landed (re-read status = 'dispatched') before inserting the `dispatch_commands` row. Fixing the underlying `to_status` discriminator in `transition_shipment_order` (see separate finding) also closes this.

#### prepare_finance_settlement replays on idempotency_key alone, so a reused key returns a settlement for a different vendor/allocation set

- **File:** `supabase/migrations/20260729150000_create_finance_settlement.sql`:243
- **Symbol:** `app.prepare_finance_settlement`
- **Category:** idempotency-target-mismatch

**Claim.** The replay short-circuit is `select * into v_settlement from app.finance_settlements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key; if found then return v_settlement; end if;` — it compares none of the discriminating request parameters before returning. Table: `app.finance_settlements`. Discriminator columns that should be compared (or folded into a stored request fingerprint) before the early return: `company_id`, `vendor_master_id`, `currency`, `settlement_date`, `fee_amount`, `payment_reference`, `bank_account_label`, plus the allocation set in `app.finance_settlement_allocations` (`ap_open_item_id`, `amount`). FIN-208 built exactly this guard (`app.claim_finance_idempotency_key`, supabase/migrations/20260729220000_create_finance_idempotent_posting.sql:93-136) but wired it only into `create_finance_journal_draft`.

**Claimed failure scenario.** AP clerk prepares settlement key 'PAYRUN-2026-06-15' for vendor Acme, allocations [{AP-1, 50000}]. A UI retry (or a client that derives the key from the pay-run date rather than the payload) then calls prepare with vendor Beta and allocations [{AP-9, 12000}] under the same key. The function returns the ORIGINAL Acme settlement row. The screen shows a prepared settlement, the approver approves it, `execute_finance_settlement` records the bank transfer, and 50000 is paid to Acme while the operator believes they authorized 12000 to Beta. No error is ever raised.

**Proposed fix.** Route this through `app.claim_finance_idempotency_key` with scope 'settlement' and a fingerprint over (company_id, vendor_master_id, currency, settlement_date, fee_amount, canonicalized p_allocations), so a reused key with a different payload raises `finance_idempotency_fingerprint_conflict` instead of silently returning the prior settlement.

#### Receipt allocation derives its per-open-item idempotency key without the receipt id, so two receipts sharing one allocate key silently skip the AR balance update

- **File:** `supabase/migrations/20260729160000_create_finance_subledger.sql`:670
- **Symbol:** `app.allocate_finance_receipt`
- **Category:** data-integrity

**Claim.** `allocate_finance_receipt` guards batch replay on `(tenant_id, receipt_id, idempotency_key)` (line 625), so the same `p_idempotency_key` is legitimately reusable across two different receipts. But the key it hands to `app.apply_finance_ar_allocation` is only `p_idempotency_key || ':' || open_item_id` (line 670) — the receipt id is missing. `app.finance_ar_open_item_events` is unique on `(tenant_id, open_item_id, idempotency_key)` and `apply_finance_ar_allocation` short-circuits on a key hit (supabase/migrations/20260729100000_create_finance_accounts_receivable.sql:387-393), returning the open item untouched. The caller does not inspect that return value: it still writes the `finance_receipt_allocations` lineage row (line 672), still posts the `receipt_allocation` subledger batch crediting `ar_control` (line 680), and still increments `finance_receipts.allocated_amount` (line 689). The key is caller-supplied end-to-end with no server-side namespacing (server/mutations/receipt-allocation.ts:108).

**Claimed failure scenario.** Tenant T, customer C, AR open item X (original 2000, allocated 0). Call `allocate_finance_receipt(R1, 'BATCH-1', [{X, 1000}])` -> X.allocated=1000, event (T,X,'BATCH-1:X') written. Now call `allocate_finance_receipt(R2, 'BATCH-1', [{X, 500}])` for a second receipt R2 of 500. The batch guard passes (different receipt_id), but `apply_finance_ar_allocation(X, 500, ..., 'BATCH-1:X')` finds the existing event and returns without applying. Result: X.allocated stays 1000 and X.open_amount stays 1000 (should be 500); R2.allocated_amount=500 and R2.unapplied_amount=0; a `finance_receipt_allocations` row claims 500 applied to X; a GL journal credits ar_control an extra 500. The customer is still dunned for 500 they already paid, and `app.get_finance_subledger_reconciliation_summary` / `app.execute_finance_reconciliation_run` report a permanent 500 AR control-vs-open-item variance that blocks certification.

**Proposed fix.** Namespace the derived key with the batch or receipt: `v_batch.id::text || ':' || v_open_item_id::text` (or `p_receipt_id || ':' || p_idempotency_key || ':' || v_open_item_id`). The settlement path is already safe because `finance_settlements.idempotency_key` is unique per tenant; the receipt path's key is not.

#### app.generate_route_planning_candidates is SECURITY DEFINER with no authority check and granted to `authenticated`, letting any logged-in user destroy and rewrite another tenant's route plans

- **File:** `supabase/migrations/20260729320000_create_advanced_tms_route_load_planning.sql`:871
- **Symbol:** `app.generate_route_planning_candidates`
- **Category:** tenant-isolation

**Claim.** The function takes only `(p_scenario_id uuid, p_actor_label text)` — no actor identity at all — and contains no `evaluate_permission`, no `can_access_record`, no membership test (confirmed by grepping the compiled `pg_proc.prosrc`: the only tenant references are `where tenant_id = v_scenario.tenant_id` data filters at lines 83/93/125 of the body). It then `delete from app.route_planning_score_components …` (line 913), `delete from app.route_planning_candidate_plans where scenario_id = p_scenario_id` (line 916), re-inserts plans, and unconditionally forces `update app.route_planning_scenarios set status = 'ready'` (lines 989 and 1031). Line 1592 grants it to `authenticated`; the migration's own comment above the function acknowledges it is "Internal to app.run_next_route_planning_job, but granted execute like every other function in this migration." The `route_planning_scenarios_touch_row` BEFORE UPDATE trigger additionally bumps `record_version` on that forced status write. `app.run_next_route_planning_job(text)` (line 1050, granted at line 1593) has the same problem and additionally wraps `app.claim_next_job`, which the background-job migration deliberately restricts to service_role — the SECURITY DEFINER wrapper hands that privilege to `authenticated`.

**Claimed failure scenario.** Tenant B's dispatcher has a route planning scenario S in status `ready` with three ranked candidate plans awaiting selection, record_version 5. An `authenticated` user from unrelated tenant A (or any customer-portal user) calls `select * from app.generate_route_planning_candidates('<S>', 'x')`. All of tenant B's candidate plans and score components for S are deleted and regenerated from tenant B's own vehicles/drivers, and record_version is bumped to 6 — so the dispatcher's pending `app.select_route_planning_plan('<S>', '<planId>', 5, …)` fails with `stale_version` and the plan id they were looking at no longer exists. Worse, if S had been cancelled (`status = 'cancelled'`, which `app.cancel_route_planning_scenario` refuses to re-open), the unconditional `set status = 'ready'` returns it to a selectable state, defeating that guard entirely.

**Proposed fix.** Revoke `authenticated` on lines 1592-1593 (both are worker-internal entry points; `app.execute_route_planning_scenario` at line ~800 is the correctly-gated user-facing path), or add `p_actor_auth_user_id` and the same `OPS:Edit` + `can_access_record` pair against the scenario's shipment order that `execute_route_planning_scenario` and `cancel_route_planning_scenario` already perform.

### HIGH

#### app.reserve_inventory's idempotency conflict check ignores the reserved dimension and quantity, letting approve_wms_pick_substitution bind a pick task to an unrelated reservation and never reserve the substitute stock

- **File:** `/home/user/cargogrid.app/supabase/migrations/20260730390000_harden_platform_operations_finance_idempotency_target_mismatch.sql`:1850
- **Symbol:** `app.reserve_inventory / app.approve_wms_pick_substitution`
- **Category:** double-allocation

**Claim.** The ATW-031 target-mismatch hardening of `app.reserve_inventory` compares only `source_type` and `source_id` (line 1850: `if v_existing.source_type is distinct from p_source_type or v_existing.source_id is distinct from p_source_id then ... idempotency_key_conflict`). It never compares warehouse/owner/item/location/lot/serial or quantity. Every pick-related reservation for one outbound order shares `source_type='wms_outbound_order'` and `source_id=<order id>`, so any key reuse within a single order passes the check and silently returns a reservation for a completely different dimension. `app.approve_wms_pick_substitution` (20260730380000 line 1595) forwards its own `p_idempotency_key` straight into `reserve_inventory` and then stores the returned row as the task's `reservation_id` without verifying it points at the substitute balance. Contrast `app.post_inventory_movement`, whose hardened check (same file, line 1672) does compare warehouse/type/source.

**Claimed failure scenario.** Reproduced end to end on a scratch DB against the wms-picking fixture. (1) `app.reserve_inventory(tenant, WH-PICK-1, Alpha, SKU-PICK-PLAIN, RACK-PICK-A, null, null, 1, 'wms_outbound_order', <order O>, 'K', ...)` creates a 1-unit reservation on the SKU-PICK-PLAIN balance. (2) A normal `generate_wms_pick_task` on order O's SKU-PICK-SUB-FROM line creates a 2-unit task with its own reservation. (3) `approve_wms_pick_substitution(task, SKU-PICK-SUB-TO, RACK-PICK-A, ..., 'K', ...)` is ACCEPTED: the original reservation is released, `reserve_inventory` short-circuits and hands back the stray 1-unit SKU-PICK-PLAIN reservation, and the task's `reservation_id` becomes that row. SKU-PICK-SUB-TO @ RACK-PICK-A stays `reserved=0, available=5` -- the 2 substitute units are never earmarked, so a second order can allocate the same units. (4) Confirming the task then moved 2 units of SKU-PICK-SUB-TO (on_hand 5 -> 3) but decremented `reserved` on the WRONG balance: SKU-PICK-PLAIN @ RACK-PICK-A went reserved 78 -> 76, silently erasing 2 units of earmark belonging to other still-active pick tasks, which can later drive that balance's `reserved` negative (`inventory_balances_reserved_check`) or trip `reserved + held <= on_hand`.

**Proposed fix.** Extend `app.reserve_inventory`'s replay short-circuit to also require `v_existing.balance_id` to resolve to the requested (warehouse, owner_account, item_master, location, lot, serial) tuple and `v_existing.reserved_quantity = p_quantity`, raising `idempotency_key_conflict` otherwise. Independently, in `app.approve_wms_pick_substitution` either derive a distinct sub-key for the reserve call (e.g. `p_idempotency_key || ':sub-reserve'`) or assert after the call that `v_new_reservation.balance_id` is the substitute balance before writing it onto the task.

#### app.post_inventory_movement validates only on_hand >= 0, never on_hand >= reserved + held, so any negative movement against reserved stock aborts with a raw 23514

- **File:** `/home/user/cargogrid.app/supabase/migrations/20260730390000_harden_platform_operations_finance_idempotency_target_mismatch.sql`:1754
- **Symbol:** `app.post_inventory_movement`
- **Category:** unhandled-error

**Claim.** In the balance-update branch (lines 1753-1760) the only guard is `if v_new_on_hand < 0 then raise 'insufficient_stock' ...`. The table also enforces `inventory_balances_reserved_held_bound_check check (reserved + held <= on_hand)` (20260730190000 line 153), which the function never anticipates. The function's own header comment claims "the table's own check constraint becomes a pure defense-in-depth backstop, never a value the write path can trip for a legitimate movement" -- that claim is false for any balance carrying outstanding reservations or holds. The 20260730280000 header even acknowledges this failure mode for cycle count ("the approval aborts with a raw, unhandled Postgres inventory_balances_reserved_held_bound_check violation instead of a clean, named domain error") but its fix only covers reservations placed AFTER the freeze (via record_version staleness); a reservation that already existed at freeze time still reaches the constraint. Neither `INVENTORY_LEDGER_KNOWN_MUTATION_ERROR_CODES` (server/mutations/inventory-ledger.ts lines 29-52) nor the cycle-count contract classifies a raw check violation, so callers see an opaque `mutation_failed`.

**Claimed failure scenario.** Reproduced on a scratch DB: balance SKU-INV-A1 @ BIN-1 with on_hand=20, reserved=20 (a pre-existing full reservation). `app.post_inventory_movement(tenant, wh, 'adjustment', 'cycle_count', <scope item>, 'k', 'counted one short', [{... signed_quantity: -1 ...}], ...)` fails with `sqlstate=23514 ... violates check constraint "inventory_balances_reserved_held_bound_check"`. Concretely for ATW-020: a balance with on_hand=100 and reserved=100 (fully allocated to an open outbound order) is frozen into a cycle-count plan; the counter observes 60; `app.approve_cycle_count_variance` posts signed_quantity=-40; the balance's record_version still matches the snapshot so `balance_changed_since_snapshot` does not fire; the movement's UPDATE then trips the constraint and aborts the whole approval. The scope item stays in `pending_review` forever -- it can only ever be rejected or cancelled, never adjusted -- and the operator gets an unclassified database error rather than a named domain error.

**Proposed fix.** In the update branch of `app.post_inventory_movement`, read `reserved`/`held` alongside `on_hand` under the same `FOR UPDATE` and raise a named domain error (e.g. `insufficient_unreserved_stock`) when `v_new_on_hand < reserved + held`, mirroring the existing `insufficient_stock` message shape, so the constraint is never the first line of defence.

#### ISS-2026-012 remediation is incomplete: print_label/route_load_planning jobs can be enqueued but their result row cannot be parsed and they can never be claimed

- **File:** `server/contracts/import-export/import-export.ts`:28
- **Symbol:** `IMPORT_EXPORT_JOB_TYPES / ImportExportJobSchema.jobType / ClaimNextJobInputSchema.jobTypes`
- **Category:** contract-mismatch

**Claim.** ATW-031 (supabase/migrations/20260730410000_harden_job_type_single_source_of_truth.sql) closed ISS-2026-012 by making `app.generic_job_types()` the single authority and widening `GENERIC_JOB_TYPES` in server/contracts/background-job/background-job.ts:33-44 to ten values including `route_load_planning` and `print_label`. It did NOT widen the OTHER TypeScript job_type list — `IMPORT_EXPORT_JOB_TYPES` at server/contracts/import-export/import-export.ts:28-32, still ten values missing exactly those two. That list backs `ImportExportJobTypeSchema`, which backs `ImportExportJobSchema.jobType` (import-export.ts:82) — the schema `parseImportExportJob` uses, and which background-job.ts's own header explicitly says is 'reuse[d] ... directly for generic (non-import/export) job rows too'. Two concrete consequences: (1) `enqueueJob` (server/mutations/background-job.ts:88) validates its input against `GenericJobTypeSchema` (accepts print_label), the RPC commits the `app.jobs` row, then line 106 calls `parseImportExportJob(data)` which throws a ZodError — an unhandled error class the wrapper's own `BackgroundJobMutationError` contract does not cover. Same at line 202 for `dispatchEventAsJob`. (2) `ClaimNextJobInputSchema.jobTypes: z.array(ImportExportJobTypeSchema)` (background-job.ts:82) rejects both values outright, so `claimNextJob` can never be called for them. That directly contradicts the label migration's documented invariant (supabase/migrations/20260730290000_create_advanced_tms_label_barcode_operations.sql:112-113: 'app.claim_next_job (PLT-132) already generically covers job_type = print_label the moment it is added to the valid-type list, with zero further code'). Verified empirically: `EnqueueJobInputSchema.safeParse({jobType:"print_label", ...})` succeeds, `parseImportExportJob` on the resulting row throws ZodError, and `ClaimNextJobInputSchema.safeParse({workerId:"w1", jobTypes:["print_label"]})` is REJECTED while `["export"]` is accepted.

**Claimed failure scenario.** Caller invokes `enqueueJob(client, { tenantId, jobType: "print_label", idempotencyKey: "k1", actorAuthUserId, actorLabel })`. Input validation passes (GENERIC_JOB_TYPES includes print_label), `app.enqueue_job` COMMITS a real `app.jobs` row, then `parseImportExportJob` throws a ZodError. The caller sees a hard, unclassified failure and retries; because `app.enqueue_job` is idempotent on (tenantId, idempotencyKey) the retry returns the same committed row and throws again — the job exists in the queue but can never be reported as created. Separately, a worker attempting `claimNextJob(client, { workerId, jobTypes: ["print_label"] })` to drain the `print_label` rows that `printLabel` (server/mutations/label-barcode.ts:296, wired to the label UI) enqueues throws a ZodError before the RPC is reached, so those rows can never be claimed.

**Proposed fix.** Add "print_label" and "route_load_planning" to `IMPORT_EXPORT_JOB_TYPES` (server/contracts/import-export/import-export.ts:28) so it is set-equal to `app.all_job_types()` / the `jobs_job_type_check` constraint, the same way ATW-031 widened `GENERIC_JOB_TYPES`. Extend background-job.test.ts's exact-list assertion to cover this array too.

#### FinanceJournal contract omits the 'correction' source_type the DB accepts, so one posted journal correction permanently 500s the Finance > Journals page

- **File:** `server/contracts/journal/journal.ts`:9
- **Symbol:** `FINANCE_JOURNAL_SOURCE_TYPES / parseFinanceJournal`
- **Category:** contract-mismatch

**Claim.** `FINANCE_JOURNAL_SOURCE_TYPES = ["manual", "subledger"]` (server/contracts/journal/journal.ts:9) feeds `FinanceJournalSourceTypeSchema` which `FinanceJournalSchema.sourceType` uses. FIN-206 widened the database in `supabase/migrations/20260729200000_create_finance_reversal_adjustment.sql:549` — `alter table app.finance_journals add constraint finance_journals_source_type_check check (source_type in ('manual', 'subledger', 'correction'))` — and `app.post_finance_correction` writes exactly that value via `app.create_and_post_finance_system_journal(v_correction.tenant_id, v_correction.company_id, 'correction', ...)` at line 461 of the same migration. Confirmed against the applied schema: `app.finance_journals.source_type` CHECK allows {correction, manual, subledger}. The contract was never widened alongside the migration. `server/queries/journal.ts:35` maps EVERY row returned by `app.list_finance_journals` through `parseFinanceJournal`, so a single correction row poisons the whole list, not just its own entry. The thrown value is a raw ZodError, not a `JournalQueryError`, so `app/(tenant)/[tenantSlug]/finance/journals/page.tsx:62-65` (`if (!(error instanceof JournalQueryError)) { throw error; }`) rethrows it instead of rendering its ErrorState. Verified empirically by running the real schema through node: parseFinanceJournal on a `source_type: "correction"` row throws `ZodError ... Invalid option: expected one of "manual"|"subledger"` at path ["sourceType"].

**Claimed failure scenario.** A finance user completes the built correction flow: `postFinanceCorrectionAction` (app/(tenant)/[tenantSlug]/finance/corrections/actions.ts:222) -> `app.post_finance_correction` -> a new `app.finance_journals` row with `source_type='correction'`. Any user then opens `/{tenantSlug}/finance/journals` (no `?sourceType=` filter, so `p_source_type` is null and all rows are returned). `listFinanceJournals` receives the correction row, `parseFinanceJournal` throws a ZodError, the page's catch rethrows because it is not a `JournalQueryError`, and the Journals page returns a 500 for every user in that tenant, permanently — the row cannot be un-posted, so the page never recovers.

**Proposed fix.** Add "correction" to `FINANCE_JOURNAL_SOURCE_TYPES` in server/contracts/journal/journal.ts:9 so it is set-equal to the `finance_journals_source_type_check` constraint, mirroring how ATW-031 handled the job_type drift. A unit test asserting the array against the migration's list would prevent recurrence.

#### app.resolve_config lets any authenticated user read any tenant's published configuration, bypassing the deliberate service_role-only posture on config_versions/config_items

- **File:** `supabase/migrations/20260717130000_create_configuration_engine.sql`:656
- **Symbol:** `app.resolve_config`
- **Category:** tenant-isolation

**Claim.** `app.resolve_config(p_config_type_code, p_tenant_id, …)` is `security definer` and granted to `authenticated` at line 848, but performs no membership or authority check on `p_tenant_id` whatsoever — it simply walks the six scope levels and returns the resolved version id plus a `jsonb_object_agg` of every `app.config_items` row. Lines 815-821 of the same migration state the opposite intent: "app.config_versions/app.config_items/app.config_dependencies are deliberately NOT given a direct authenticated grant … RLS is still enabled … but with no policy at all for authenticated -- service_role only". The SECURITY DEFINER function is the hole in that wall. The tenant UUID needed is not secret: `app.resolve_tenant_by_domain(text)` (20260717103015_create_custom_domain.sql) is SECURITY DEFINER and granted to `anon`, returning `resolved_tenant_id` for any active custom hostname. Config types include `finance_posting_map`, `finance_close_policy`, `finance_numbering`, `approval`, `notification` — the approval config in particular carries `allow_self_approval` and `threshold_required_steps`, which `app.decide_approval_step` reads to decide governance.

**Claimed failure scenario.** Verified live against a scratch DB. Tenant V has a published `finance_posting_map` config version with items {"ar_control_account": "1200-SECRET", "margin_floor_pct": 12.5}. A session with role `authenticated` and no membership in V runs `select * from app.resolve_config('finance_posting_map','<V uuid>')` and receives the full items JSON plus the version id. In the same session `select 1 from app.config_items` correctly fails with `permission denied for table config_items` — proving the intended restriction exists and that the SECURITY DEFINER function is what defeats it. Chained with the anon-callable `app.resolve_tenant_by_domain('victim.example.com')`, an attacker needs only a self-service account in any tenant to enumerate a competitor's approval thresholds, finance posting map and numbering policy.

**Proposed fix.** Add `if not app.has_active_tenant_membership(p_tenant_id, coalesce(p_actor, auth.uid())) and not app.is_supreme_admin(...) then raise insufficient_authority` at the top of the function body (an actor parameter has to be threaded in, matching the convention every other authenticated-facing RPC uses), or revoke `authenticated` on line 848 and expose a tenant-checked wrapper instead. `app.verify_config_version_current` (line 734, granted line 849) and `app.render_notification_template` (20260719130000_create_notification_engine.sql:223, granted line 709) have the identical unchecked shape and need the same treatment.

#### Numbering counters are keyed per config_version, so republishing a numbering definition permanently wedges allocation for that tenant

- **File:** `supabase/migrations/20260719110000_create_numbering_engine.sql`:175
- **Symbol:** `app.numbering_counters / app.allocate_or_reserve_number`
- **Category:** correctness

**Claim.** `app.numbering_counters` is unique on `(config_version_id, scope_key, period_key)` (line 175) and `app.allocate_numbering_seq` (lines 211-215) upserts on that key, so the sequence is scoped to one config_version. But `app.numbering_allocations` is unique on `(tenant_id, formatted_number)` (line 304), which is scoped to the tenant across all versions. Changing a numbering definition is done through `app.publish_config_version` (20260717130000:511-521), which archives the prior published version and publishes a NEW row with a new id — so the counter restarts at 0 while the formatted numbers it renders already exist. The unique violation propagates out of the plpgsql function, aborting the caller's transaction and rolling back the counter increment too, so every subsequent attempt regenerates the same colliding value.

**Claimed failure scenario.** LIVE-REPRODUCED. Tenant publishes numbering definition v1 (`PO-{YYYY}-{SEQ}`, yearly, padding 5) and allocates PO-2026-00001..00003. The tenant admin then edits the definition the only supported way — a new draft on the same config object, published via `app.publish_numbering_definition` — which archives v1 and creates v2. Counter state after republish: only v1's counter exists at last_seq=3; v2 has none. The next `app.allocate_number(v2, ...)` fails with `[23505] duplicate key value violates unique constraint "numbering_allocations_tenant_formatted_unique"`, and so does every retry, with a different idempotency key each time. Number allocation for that tenant/format is dead until a service_role operator manually calls `app.bootstrap_numbering_counter`.

**Proposed fix.** Key the counter on the config *object* (or on tenant + schema code) rather than the config version, or have `app.publish_numbering_definition` seed the new version's counter from the prior published version's `next_seq` via `app.bootstrap_numbering_counter`.

#### 65 SECURITY DEFINER mutations silently no-op on a lost update instead of raising stale_version, and write a fabricated `success` audit row with NULL tenant_id

- **File:** `supabase/migrations/20260723090000_create_commercial_lead_management.sql`:491
- **Symbol:** `app.transition_lead_status`
- **Category:** race

**Claim.** The optimistic-concurrency pattern used across this repo reads the row, compares `record_version` to `p_expected_version` and raises `stale_version`, then issues `update … where id = … and record_version = p_expected_version returning * into v_row;` with no `if not found` re-check afterwards. Under READ COMMITTED the predicate is re-evaluated after a concurrent writer commits, so the UPDATE can match zero rows; PL/pgSQL then leaves `v_row` all-NULL and execution falls straight through to `app.capture_audit_event(v_row.tenant_id, …, 'success', …)`. `app.audit_logs.tenant_id` is nullable and the tenant-scoped index is `WHERE tenant_id IS NOT NULL`, so the bogus row is written and is invisible to tenant-scoped audit queries. A scan of `pg_proc.prosrc` for all 529 SECURITY DEFINER functions granted to `authenticated` found 65 with this exact shape, including `submit_quotation`, `transition_shipment_order`, `cancel_shipment_order`, `confirm_job_order`, `approve_warehouse_billing_event`, `decide_claim_responsibility`, `release_credit_profile`, `deregister_gps_device`, `override_billing_readiness`, `transition_shipment_leg`. The TS layer treats a returned object as success (`server/mutations/lead.ts:69-73` only rejects when `data` is falsy or non-object), so the null-filled composite is passed to `parseLead` rather than surfacing the documented `stale_version` code listed in `LEAD_KNOWN_MUTATION_ERROR_CODES`.

**Claimed failure scenario.** Verified live with two concurrent psql sessions against a scratch DB. Lead 2222…0001 is at status `new`, record_version 1. Session A opens a transaction and runs `update app.leads set record_version = record_version + 1, status='contacted' where id = '2222…0001'` (holding the row lock, uncommitted). Session B calls `app.qualify_lead('2222…0001', 1, '<supreme admin uuid>', 'clientB')`; it reads version 1, passes the stale_version check, and blocks on the UPDATE. Session A commits. Session B's UPDATE re-evaluates `record_version = 1` against the now-committed version 2, matches 0 rows, and the function RETURNS A ROW OF ALL NULLS instead of raising. Final state: the lead is still `contacted`/version 2 (never qualified), and `app.audit_logs` contains exactly one row — `action='qualify_lead', result='success', tenant_id=NULL, resource_id=NULL, actor_label='clientB'`. The user is told the transition succeeded, it did not, and the tenant's auditor can never see the entry because it carries no tenant_id.

**Proposed fix.** After every `update … where record_version = p_expected_version returning * into v_row;` add `if not found then raise exception 'stale_version: … ' using errcode = 'serialization_failure'; end if;` — the pattern `app.create_quotation_revision` (20260724240000_create_commercial_quotation_versioning.sql:317-322) already uses correctly. Alternatively `select … for update` the row before the version comparison so the read and the write see the same snapshot.

#### customer_contracts and the credit-profile directory views expose every customer's negotiated pricing and credit limits to any tenant-layer principal, including customer-portal users

- **File:** `supabase/migrations/20260724300000_create_commercial_customer_contract_pricing.sql`:691
- **Symbol:** `customer_contracts_select_scoped`
- **Category:** tenant-isolation

**Claim.** `create policy customer_contracts_select_scoped on app.customer_contracts for select to authenticated using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());` (line 691), and the sibling `customer_contract_price_components_select_scoped` (line 695). `app.customer_contracts` carries `account_id` AND populated `owner_user_id`/`org_unit_id` (set at lines 243-246 and 273-276 of the same file), none of which the policy consults.

The credit tables reach `authenticated` through views rather than table grants, but the predicate is the same tenant-only expression, and these views are owned by `postgres` with no `security_invoker=true` reloption (confirmed against pg_class.reloptions on the applied schema), so they bypass the underlying table RLS entirely and their own WHERE clause is the whole control:
- `app.credit_profiles_directory` (20260724310000:642) — `WHERE (app.has_active_tenant_membership(tenant_id) OR app.is_supreme_admin())`, exposing `account_id`, `requested_limit_amount`, `approved_limit_amount`, `hold_reason`, `rejected_reason`
- `app.credit_check_snapshots_directory` (20260724310000:674) — same predicate, exposing `effective_limit_amount`, `requested_amount`, `outcome` per `account_id`
- `app.credit_profile_overrides_directory` (20260724310000:700) and `app.customer_contract_price_components_directory` (20260724300000:559) — same predicate

The views' field-masking `CASE WHEN app.has_view_selling_price(tenant_id)` only masks amount columns behind an RBAC permission; the row itself, including `account_id` and every non-amount column, is returned to any tenant-layer principal regardless.

**Claimed failure scenario.** The Alpha-scoped customer_user session satisfies `app.has_active_tenant_membership(<probe1>)` = true (verified live under `set local role authenticated`), which is the complete predicate. A customer-portal browser session therefore reads `GET /rest/v1/customer_contracts?select=*` and `GET /rest/v1/credit_profiles_directory?select=*` and gets competitor Beta's contract versions, effective dates, `account_id`, and Beta's credit-profile rows (status, hold_reason, rejected_reason, and the amounts too if the session's role happens to carry the selling-price permission). Separately, because `owner_user_id`/`org_unit_id` are populated but unused, a sales rep in Branch B reads every Branch A customer contract — while the quotation those very contracts were generated from (`quotations_select_scoped`) is correctly branch-scoped via `app.can_access_record`.

**Proposed fix.** New migration: recreate `customer_contracts_select_scoped` and `customer_contract_price_components_select_scoped` with `app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), account_id::text)` (the price-components child joining through its `contract_id`), matching every sibling commercial table. For the four directory views, either add `security_invoker = true` and give the base tables owner-scoped policies, or AND `app.actor_can_view_owner_scoped_row(auth.uid(), tenant_id, account_id)` into each view's WHERE clause.

#### The MFA/step-up gate on credit approval is a caller-supplied timestamp on functions granted to `authenticated`, so any client can self-attest re-authentication

- **File:** `supabase/migrations/20260724310000_create_commercial_credit_commercial_control.sql`:283
- **Symbol:** `app.decide_credit_profile_approval_step`
- **Category:** authorization-gap

**Claim.** `app.decide_credit_profile_approval_step`, `app.hold_credit_profile`, `app.release_credit_profile` and `app.create_credit_override` each enforce "MFA for privileged approvers" (Prompt 157 §16, AGENTS.md "MFA is mandatory for privileged roles specified by RPD-023") solely with `if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then raise reauth_required` (lines 283, 347, 403, 474). `p_reauth_confirmed_at` is a plain client-supplied value: `server/contracts/credit/credit.ts:147/157/166/177` declares it as `reauthConfirmedAt: z.string()` and `server/mutations/credit.ts:96/115/133/154` passes it straight through; nothing anywhere derives it from an actual authentication event or looks up a session record. Crucially, all four are granted to `authenticated` (lines 769-772), so the attestation is made by the client, not by a trusted server. The migration header (lines 33-38) says this "reuses PLT-115's own reauth_confirmed_at-freshness mechanism … reproduced here verbatim" — but PLT-115's `app.start_support_session` is service_role-only (confirmed: `has_function_privilege('authenticated', …) = false`), where the trusted Next.js server is the attester. Copying the parameter shape while widening the grant to `authenticated` converts a server-attested control into a self-attested one.

**Claimed failure scenario.** An approver's browser session cookie is stolen (the exact threat step-up auth exists to stop) or a legitimate approver simply wants to skip the challenge. Using the public `NEXT_PUBLIC_SUPABASE_ANON_KEY` and the stolen JWT, the caller POSTs to `/rest/v1/rpc/decide_credit_profile_approval_step` with `{"p_request_step_id":"…","p_decision":"approved","p_reauth_confirmed_at":"<new Date().toISOString()>","p_actor_auth_user_id":"<approver>","p_actor_label":"…"}`. The freshness check passes trivially, `app.decide_approval_step` records the approval, and `app.credit_profiles` flips to status `active` with `approved_limit_amount = requested_limit_amount` — a customer credit limit granted with no second factor ever presented. `app.create_credit_override` is worse: it writes an arbitrary override amount under the same forged attestation.

**Proposed fix.** Stop trusting the parameter on an `authenticated`-callable path: either revoke `authenticated` on lines 769-772 so only the server (which can actually observe a re-auth) may call them, or replace the parameter check with a lookup against a server-written re-auth record (e.g. a row in `app.support_access_sessions`-style table keyed by `auth.uid()`) whose freshness the database can verify itself.

#### cancel_shipment_order bypasses the canonical lifecycle matrix — a closed shipment can be cancelled by any OPS:Edit user with no history row

- **File:** `supabase/migrations/20260727100000_create_operations_shipment_order.sql`:447
- **Symbol:** `app.cancel_shipment_order`
- **Category:** state-machine

**Claim.** `app.cancel_shipment_order` (OPS-169) predates the OPS-170 lifecycle and its only state guard is `if v_shipment.status = 'cancelled'` (line 447). It is still granted to `authenticated` (line 502) and writes `app.shipment_orders.status` with a direct UPDATE. OPS-170's own header (20260727110000, lines 3-7) states the status projection is "driven exclusively by one validated, idempotent, optimistic-concurrency-checked transition function -- never a direct UPDATE", and its matrix has no `closed -> cancelled` or `epod -> cancelled` edge; reopening a closed shipment is Supreme-Admin-only (line 157). `cancel_shipment_order` honours none of that and writes no `app.shipment_status_transitions` row.

**Claimed failure scenario.** LIVE-REPRODUCED. Walk a shipment through the sanctioned matrix to `closed` (12 transition-history rows). Then `app.cancel_shipment_order(S, version, 'oops', repA, 'Rep A')` where Rep A holds only OPS:Edit (not Supreme Admin). Output: `cancel_shipment_order SUCCEEDED on a closed shipment -> status = cancelled`, transition-history rows before=12 after=12. A settled, closed shipment is destroyed by a non-privileged user, the append-only canonical history has no record of the change, and `transition_shipment_order` now treats the shipment as terminally cancelled so it cannot be recovered.

**Proposed fix.** Either revoke `cancel_shipment_order` from `authenticated` and reduce it to a thin wrapper that calls `app.transition_shipment_order(..., 'cancelled', ...)`, or add the same matrix guard (`v_shipment.status in ('draft','confirmed','planned','assigned','dispatched','in_transit','delivered')`) plus a transition-history insert.

#### Job-order allocation basis is written and read by two disagreeing rules, so the documented over-allocation block never fires

- **File:** `supabase/migrations/20260727100000_create_operations_shipment_order.sql`:194
- **Symbol:** `app.get_job_shipment_allocation_balance / app.create_shipment_order_from_job`
- **Category:** constraint-bypass

**Claim.** `create_shipment_order_from_job` decides which row may declare the basis with `v_existing_count = 0` where the count is `status <> 'cancelled'` (lines 285, 311-315). `get_job_shipment_allocation_balance` decides which row IS the basis with `order by so.created_at asc limit 1` over ALL rows regardless of status (lines 190-195) — and with no tie-break, so two Shipment Orders created in one transaction share `created_at` (transaction-time `now()`) and the winner is arbitrary. The two rules pick different rows, so a stored `basis_*` can be permanently inert; the over-allocation check at lines 291-305 is then skipped entirely because `v_balance.basis_quantity is not null` is false. The migration header (lines 23-29) promises this is "a hard, structural block".

**Claimed failure scenario.** LIVE-REPRODUCED. Job order JOB-2026-000001 has two Shipment Orders created in one transaction with identical `created_at`; SHP-000001 carries basis_quantity=10, SHP-000002 carries NULL. Both later cancelled. Operator creates SHP-2026-000003 with `p_basis_quantity=100, p_allocated_quantity=999` — accepted with no split_reason and no balance check (v_existing_count=0), and the row stores basis_quantity=100. `app.get_job_shipment_allocation_balance` then reports `basis_quantity = NULL, allocated_quantity = 999, remaining_quantity = NULL`, because it picked SHP-000002. A second split SHP-2026-000004 allocating 5000 with a split_reason is accepted unchecked; final balance is basis NULL / allocated 5999 against a declared basis of 100.

**Proposed fix.** Make the basis a single authoritative source: either add `basis_*` columns to `app.job_orders` (or a dedicated per-job basis row), or have `get_job_shipment_allocation_balance` select the basis row with `where basis_quantity is not null or basis_weight_kg is not null or basis_volume_cbm is not null order by created_at asc, id asc limit 1` and have `create_shipment_order_from_job` refuse to write `basis_*` when any prior row (cancelled or not) already declared one.

#### evaluate_dispatch_readiness is SECURITY DEFINER, granted to authenticated, and performs no authority check — leaks any tenant's shipment state

- **File:** `supabase/migrations/20260727160000_create_operations_basic_dispatch.sql`:46
- **Symbol:** `app.evaluate_dispatch_readiness`
- **Category:** authorization-gap

**Claim.** The function is declared `security definer` (line 50) with no `evaluate_permission`, no `has_active_tenant_membership`, and no `can_access_record` call anywhere in its body, yet it is granted directly to `authenticated` at line 332. Its sibling `app.get_dispatch_readiness` performs the full OPS:View + record-scope gate and then delegates to it — but that gate is trivially bypassed by calling the inner function. Comparable internal helpers in adjacent migrations (e.g. `app.recalculate_shipment_milestone_projection`, 20260727140000:715) are correctly `service_role`-only.

**Claimed failure scenario.** LIVE-REPRODUCED. `set role authenticated;` with no membership in any tenant (`select count(*) from app.shipment_orders where id = '<uuid>'` returns 0 under RLS). `select * from app.evaluate_dispatch_readiness('<other tenant's shipment uuid>')` returns `is_ready=f, blockers=[{"code":"wrong_status","detail":"cancelled"}, {"code":"no_active_assignment","detail":null}]` — the other tenant's lifecycle status verbatim, plus whether it has an active resource assignment, whether it has an open operational exception, and whether a pickup is scheduled. The function is also an existence oracle: a non-existent id raises `shipment_order_not_found` while a real one returns a row.

**Proposed fix.** Revoke the `authenticated` grant at line 332 (leave `service_role` only), matching `app.recalculate_shipment_milestone_projection`'s posture; `app.get_dispatch_readiness` and the `dispatch_ready_queue` view already cover every legitimate caller.

#### review/submit/complete_epod_capture check record_version by SELECT but omit it from the UPDATE — approvals are silently overwritten

- **File:** `supabase/migrations/20260728100000_create_operations_epod_capture_review.sql`:397
- **Symbol:** `app.review_epod_capture`
- **Category:** optimistic-concurrency

**Claim.** `review_epod_capture` reads the row with a plain `select` (line 369), compares `v_capture.record_version <> p_expected_version` (line 373), then issues `update app.epod_captures set status = p_decision, ... where id = p_capture_id` (lines 397-399) with no `and record_version = p_expected_version` predicate. The same check-then-act shape appears in `submit_epod_capture` (lines 288-291 vs 331-333) and `complete_epod_capture` (lines 502-505 vs 525-527). The sibling functions in the same domain do it correctly — `app.confirm_shipment_order` and `app.transition_shipment_order` both carry `and record_version = p_expected_version` in the UPDATE — so this is a departure from the established pattern, not a design choice. Under READ COMMITTED the second transaction blocks on the row lock, then applies its UPDATE unconditionally after the first commits.

**Claimed failure scenario.** Capture C is `submitted` at record_version 3. Reviewer A and reviewer B both load the ePOD panel and both hold expectedVersion 3. A submits 'approved' (status=approved, reviewed_by=A, version->4). B submits 'revision_requested' with notes; B's version check already passed against the stale read, and B's UPDATE has no version predicate, so it lands: status=revision_requested, reviewed_by=B, reviewed_at=now, and A's approval and reviewer identity are gone. Both callers receive a success row; neither ever sees `concurrent_modification`. The `v_capture.status <> 'submitted'` guard at line 389 is bypassed the same way, so a capture can be re-reviewed after it has already left 'submitted'.

**Proposed fix.** Add `and record_version = p_expected_version` to the UPDATE predicate in all three functions and raise `concurrent_modification` when the UPDATE affects zero rows (`if not found then raise ...`).

#### start_epod_capture idempotency is tenant-wide with no shipment discriminator — delivery evidence is attributed to the wrong shipment

- **File:** `supabase/migrations/20260728100000_create_operations_epod_capture_review.sql`:147
- **Symbol:** `app.start_epod_capture`
- **Category:** idempotency-target-mismatch

**Claim.** `app.epod_captures` carries `constraint epod_captures_tenant_idempotency_unique unique (tenant_id, idempotency_key)` (line 80) — tenant-wide, not per shipment — and the replay short-circuit at lines 146-151 matches on `tenant_id` + `idempotency_key` alone and returns `v_existing`. Missing discriminator columns: `shipment_order_id` (and `milestone_event_id`). Every other ePOD-scoped construct in this file is per-shipment; this one is not. It also short-circuits before the `v_shipment.status <> 'delivered'` precondition at line 153, so the delivered-gate is bypassed on a key collision.

**Claimed failure scenario.** A driver completes shipment S1 and starts an ePOD with key 'pod-2026-08-05'. Later that day, on shipment S2, the same key is reused (a bulk client, a retried mobile submission, or an operator typing a date-based key). `start_epod_capture(tenant, S2, ..., 'pod-2026-08-05', ...)` returns S1's capture row — different shipment, different consignee — with no error and without checking that S2 is delivered. The caller then treats that id as S2's capture: `submit_epod_capture` and `review_epod_capture` operate on S1's evidence, and `complete_epod_capture` transitions S1 (not S2) to 'epod' with `evidence_ref = <S1's capture id>`. S2 never gets an ePOD; S1's proof-of-delivery record is closed out by S2's delivery event.

**Proposed fix.** Change the constraint to `unique (tenant_id, shipment_order_id, idempotency_key)` in a new migration, and guard the short-circuit: `if v_existing.shipment_order_id <> p_shipment_order_id then raise 'idempotency_key_conflict' using errcode = 'unique_violation'; end if;`

#### decide_actual_cost / submit_actual_cost check record_version by SELECT but omit it from the UPDATE — a cost approval can be silently overwritten

- **File:** `supabase/migrations/20260728110000_create_operations_actual_cost.sql`:514
- **Symbol:** `app.decide_actual_cost`
- **Category:** optimistic-concurrency

**Claim.** `decide_actual_cost` reads the header (line 482), compares `v_cost.record_version <> p_expected_version` (line 486) and raises `concurrent_modification`, then runs `update app.shipment_actual_costs set status = p_decision, approved_by_auth_user_id = ..., approved_at = ..., rejection_reason = ... where id = p_actual_cost_id` (lines 514-519) with no version predicate. `submit_actual_cost` has the identical shape (lines 422-425 vs line 448). The `v_cost.status <> 'submitted'` guard (line 506) is evaluated against the same stale read, so it is bypassed too. This is financial approval state on `app.shipment_actual_costs`, which OPS-179 job profitability consumes.

**Claimed failure scenario.** Actual-cost header H is `submitted` at record_version 6 with total_amount 42,000,000. Approver A and approver B both open it holding expectedVersion 6. A calls decide('approved') — status=approved, approved_by=A, approved_at=now, version->7. B, blocked on the row lock, then calls decide('rejected','duplicate vendor bill'); B's stale version check already passed, and the UPDATE has no version predicate, so it applies: status=rejected, approved_by_auth_user_id=NULL, approved_at=NULL, rejection_reason set. A's approval is erased with no error to either caller, and the audit trail records two 'success' decisions on the same version. The mirror case (A rejects, B approves) leaves a cost approved that a reviewer had explicitly rejected.

**Proposed fix.** Add `and record_version = p_expected_version` to the UPDATE at line 519 (and line 448), and raise `concurrent_modification` when zero rows are affected.

#### stage_finance_exchange_rate_import replays on idempotency_key alone, silently discarding a corrected rate file

- **File:** `supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql`:559
- **Symbol:** `app.stage_finance_exchange_rate_import`
- **Category:** idempotency-target-mismatch

**Claim.** Lines 559-564 look up `app.finance_exchange_rate_import_batches` by `(coalesce(tenant_id,...), idempotency_key)` and return the existing batch with no comparison of `p_rows`. Table: `app.finance_exchange_rate_import_batches`; the only stored discriminator is `row_count`, and even that is not checked. The correct discriminator is a canonical digest of `p_rows` (per-row `rate_type`, `source_currency`, `target_currency`, `rate`, `source`, `effective_from`, `effective_to`). The function also never calls `app.validate_currency_code` on imported rows, unlike `app.create_finance_exchange_rate_draft` (line 255-262).

**Claimed failure scenario.** Treasury stages the 2026-06-01 ECB file with key 'FX-2026-06-01' (40 rows). The provider re-issues the file with a corrected USD/EUR rate; the operator re-runs the same job, which reuses the date-derived key. The function returns the ORIGINAL batch (row_count 40) and stages none of the corrected rows. The operator approves the batch's drafts believing they are the corrected rates; every subsequent `app.convert_finance_amount` call resolves the stale rate, and the corrected rate never enters the system. No error is raised.

**Proposed fix.** Store a `request_fingerprint` on `finance_exchange_rate_import_batches` computed from the canonicalized `p_rows`, compare it on replay and raise a named conflict on mismatch; also run each imported row through `app.validate_currency_code` before insert.

#### apply/reverse AR allocation and AP settlement primitives short-circuit on idempotency_key without comparing amount or source

- **File:** `supabase/migrations/20260729100000_create_finance_accounts_receivable.sql`:388
- **Symbol:** `app.apply_finance_ar_allocation`
- **Category:** idempotency-target-mismatch

**Claim.** All four shared balance primitives return the open item unchanged whenever an event row already carries the key, with no comparison of the request: `apply_finance_ar_allocation` (20260729100000:387-393), `reverse_finance_ar_allocation` (20260729100000:454-460), `apply_finance_ap_settlement` (20260729130000:374-380), `reverse_finance_ap_settlement` (20260729130000:441-447). Tables: `app.finance_ar_open_item_events` / `app.finance_ap_open_item_events`, unique on `(tenant_id, open_item_id, idempotency_key)`. Discriminator columns that should be compared against the found event before returning: `amount_delta` (vs `p_amount`, sign-adjusted), `source_type`, `source_id`, and `event_type`. Worse, the function returns the open item rather than a signal that nothing was applied, so every composite caller treats the no-op as success — this is what makes the derived-key collision above silently corrupt balances rather than fail loudly.

**Claimed failure scenario.** `apply_finance_ar_allocation(X, 500, 'receipt', R2, 'K:X')` is called when an event `(T, X, 'K:X')` already exists recording `amount_delta = 1000` from source R1. The amount (500 vs 1000) and source (R2 vs R1) both differ, yet the function returns X unchanged and its caller records a 500 allocation on the receipt side. AR is under-relieved by 500 with no exception raised at any layer.

**Proposed fix.** Compare `v_existing_event.amount_delta`, `source_type` and `source_id` against the request and raise a distinct named exception (e.g. `finance_ar_allocation_key_conflict`) when they differ, instead of returning silently.

#### Governed deallocation and settlement reversal mutate AR/AP balances with no fiscal-period or period-lock guard

- **File:** `supabase/migrations/20260729100000_create_finance_accounts_receivable.sql`:445
- **Symbol:** `app.reverse_finance_ar_allocation`
- **Category:** period-lock-enforcement

**Claim.** FIN-207's header states "every posting service calls one authoritative guard... never UI-only" and that every GL-affecting path funnels through `post_finance_journal` / `create_and_post_finance_system_journal` (supabase/migrations/20260729210000:13-28). `app.reverse_finance_ar_allocation` (line 445) and `app.reverse_finance_ap_settlement` (20260729130000:432), and their callers `app.request_finance_receipt_deallocation` (20260729120000:396) and `app.request_finance_settlement_reversal` (20260729150000:612-620), directly UPDATE `finance_ar_open_items.allocated_amount` / `finance_ap_open_items.settled_amount` and never call `app.resolve_finance_period_for_date`, never check `posting_eligible`, and never call `app.assert_finance_period_open_for_posting`. They also emit no reversing subledger batch, so the control account is not adjusted either.

**Claimed failure scenario.** Period 2026-06 is closed (`status='closed'`, so `posting_eligible=false`) and locked with `lock_finance_period(..., 'all', ...)`, and `certify_finance_reconciliation_run` has certified the June AR reconciliation at zero variance. A user holding FIN:Approve calls `request_finance_receipt_deallocation` on a June allocation of 25,000. It succeeds: the AR open item's allocated_amount drops by 25,000 and open_amount rises by 25,000, with no ar_control credit reversal. The certified June reconciliation is now false, and the next `execute_finance_reconciliation_run` reports a 25,000 unexplained variance that no correction path can clear, because FIN-206 explicitly does not touch AR/AP balances.

**Proposed fix.** Resolve the period for the original allocation/settlement date in both reverse paths, assert `posting_eligible`, and call `app.assert_finance_period_open_for_posting(..., 'ar'|'ap')` before mutating the balance — and emit the compensating subledger batch so the control account stays reconciled.

#### Discarding an invoice draft permanently blocks the billing readiness handoff from ever being invoiced

- **File:** `supabase/migrations/20260729110000_create_finance_invoice.sql`:227
- **Symbol:** `app.prepare_finance_invoice_from_readiness`
- **Category:** wedged-state

**Claim.** `prepare_finance_invoice_from_readiness` returns the existing invoice for `(tenant_id, billing_readiness_handoff_id)` with no status filter (line 227-230), while `finance_invoices_handoff_unique unique (tenant_id, billing_readiness_handoff_id)` (line 115) forbids a second row. `app.discard_finance_invoice_draft` sets `status = 'void'` (line 363) rather than deleting, and no un-void or re-prepare path exists anywhere in the migration set. The replay also ignores the request discriminators `p_payment_term_days` and `p_tax_code`, so even without a discard a corrected tax code is silently dropped.

**Claimed failure scenario.** Billing clerk prepares an invoice from handoff H with the wrong tax code (PPN instead of EXEMPT), notices before submitting, and calls `discard_finance_invoice_draft`. The invoice is now `void`. Every subsequent `prepare_finance_invoice_from_readiness(tenant, H, ...)` returns that void invoice — no error, no new draft. The void invoice cannot be submitted (`finance_invoice_not_draft`), so the Job Order's revenue can never be billed and the handoff is permanently stranded. `app.prepare_finance_vendor_bill_from_actual_cost` has the identical wedge at supabase/migrations/20260729140000_create_finance_vendor_bill.sql:222 against `finance_vendor_bills_actual_cost_vendor_unique`.

**Proposed fix.** Exclude `status = 'void'` from the replay lookup and make the uniqueness constraint partial (`where status <> 'void'`), so a discarded draft frees the handoff / (actual_cost, vendor) pair for re-preparation.

#### finance_invoices / AR / receipts policies are tenant-only despite invoices being designated customer_portal_scoped — a customer-portal principal reads every other customer's invoices, balances and payments

- **File:** `supabase/migrations/20260729110000_create_finance_invoice.sql`:544
- **Symbol:** `finance_invoices_select_scoped`
- **Category:** tenant-isolation

**Claim.** `create policy finance_invoices_select_scoped on app.finance_invoices for select to authenticated using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());`. `app.finance_invoices` carries `customer_account_id` — the same uuid a customer_user's `principal_memberships.customer_account_ref` resolves to — but the policy never references it. The identical tenant-only expression is used by the whole customer-facing AR chain, every one of which is granted SELECT to `authenticated`:

- finance_invoices_select_scoped (20260729110000:544) and finance_invoice_lines_select_scoped (:548, joins to `i.tenant_id` only)
- finance_ar_open_items_select_scoped (20260729100000:580) — has `customer_account_id`
- finance_ar_open_item_events_select_scoped (20260729100000:584)
- finance_receipts_select_scoped (20260729120000:464) and finance_receipt_allocations_select_scoped (20260729120000:472)

docs/architecture/06_RLS_RBAC_WORKSTREAM.md:87 explicitly classifies `invoices` as `customer_portal_scoped` with scope key "`tenant_id` + `customer_account_id` (Tech Arch §11.3's `app.can_access_record` example, verbatim)", and line 162 records invariant #2 "Customer user cannot access shipment outside assigned account". The shipped policy implements `standard_tenant_scoped` instead. Because `app.has_active_tenant_membership` is layer-blind (proven below), any customer-portal session satisfies it.

**Claimed failure scenario.** With the same scratch-DB fixture, the Alpha-scoped customer_user session evaluates `app.has_active_tenant_membership(<probe1 tenant id>)` = **true** (verified directly under `set local role authenticated`). Since that is the entire USING clause, `GET /rest/v1/finance_invoices?select=*` from a customer-portal browser session returns every invoice in the tenant: Beta's `invoice_number`, `customer_account_id`, `subtotal_amount`, `tax_amount`, `total_amount`, `payment_term_days`, `due_date`, `void_reason`. Chaining `finance_ar_open_items` and `finance_receipts` yields Beta's full outstanding balance, hold_reason and payment history. Expected under the architecture doc's own `customer_portal_scoped` rule: only rows where `customer_account_id` is in the caller's resolved owner scope.

**Proposed fix.** New migration narrowing each of the six policies with the owner-scope predicate that already exists and is already granted to `authenticated`: for tables with `customer_account_id`, AND in `app.actor_can_view_owner_scoped_row(auth.uid(), tenant_id, customer_account_id)`; for the child tables (`finance_invoice_lines`, `finance_ar_open_item_events`, `finance_receipt_allocations`) AND the same predicate into the existing parent EXISTS sub-select against the parent's `customer_account_id`. That helper returns NULL/unrestricted for supreme_admin, tenant_admin, org_user and no-membership actors, so this cannot narrow any staff read.

#### capture_finance_receipt replays on idempotency_key alone, so a reused key returns a receipt for a different customer, amount or currency

- **File:** `supabase/migrations/20260729120000_create_finance_receipt_allocation.sql`:183
- **Symbol:** `app.capture_finance_receipt`
- **Category:** idempotency-target-mismatch

**Claim.** `select * into v_receipt from app.finance_receipts where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key; if found then return v_receipt; end if;` returns before any of the request parameters are validated or compared — the customer-existence check, currency check, amount check and period check at lines 188-209 are all downstream of the early return. Table: `app.finance_receipts`. Discriminator columns that should be compared: `company_id`, `customer_account_id`, `receipt_reference`, `receipt_date`, `currency`, `amount` (`payer_name`/`bank_account_label` optionally).

**Claimed failure scenario.** A bank-feed adapter derives the idempotency key from the bank's own statement line id. Two different remittances that the bank later re-issued under the same statement line id (or a corrected re-submission changing the amount from 1,000 to 10,000 and the customer from C1 to C2) both call `capture_finance_receipt` with that key. The second call returns the first receipt: 1,000 against C1. The operator sees a captured receipt and allocates it, so C2's 10,000 payment is never recorded, C2's AR stays open, and unapplied cash is understated by 10,000 with no error anywhere in the chain.

**Proposed fix.** Compare `company_id`, `customer_account_id`, `receipt_date`, `currency` and `amount` on the found row against the request and raise a named conflict on mismatch, or adopt `app.claim_finance_idempotency_key` with scope 'receipt' and a fingerprint over those inputs.

#### allocate_finance_receipt replays on the batch key alone, silently discarding a different allocation payload

- **File:** `supabase/migrations/20260729160000_create_finance_subledger.sql`:625
- **Symbol:** `app.allocate_finance_receipt`
- **Category:** idempotency-target-mismatch

**Claim.** `select * into v_batch from app.finance_receipt_allocation_batches where tenant_id = ... and receipt_id = p_receipt_id and idempotency_key = p_idempotency_key; if found then return v_receipt; end if;` returns the receipt unchanged with no comparison of `p_allocations`. Table: `app.finance_receipt_allocation_batches` — which stores no fingerprint at all, so the only available discriminator is the existing batch's own child rows in `app.finance_receipt_allocations` (`ar_open_item_id`, `amount`). The function returns the receipt (not the batch), so the caller cannot even tell a replay happened.

**Claimed failure scenario.** Operator allocates receipt R (key 'ALLOC-1') across [{X, 600}, {Y, 400}]. They then notice Y was wrong, re-open the allocation screen and submit [{X, 600}, {Z, 400}] — the client reuses 'ALLOC-1' because the screen state is unchanged. The function returns R unchanged with `allocated_amount` still 1000 and `unapplied_amount` 0. The UI renders success. Y remains wrongly paid down and Z remains fully open, with no error and no audit event distinguishing the no-op from a real allocation.

**Proposed fix.** Add a request fingerprint column to `finance_receipt_allocation_batches` (or compare the found batch's `finance_receipt_allocations` set against `p_allocations`) and raise a named conflict on mismatch.

#### A settlement whose AP item was consumed by a competing settlement is stuck in 'executed' forever, after the bank payment has already gone out

- **File:** `supabase/migrations/20260729160000_create_finance_subledger.sql`:860
- **Symbol:** `app.post_finance_settlement`
- **Category:** wedged-state

**Claim.** `prepare_finance_settlement` validates `v_amount > v_open_item.open_amount` at prepare time (supabase/migrations/20260729150000:297-300) but reserves nothing — no row lock, no allocated/committed column on `finance_ap_open_items`. The actual AP mutation happens only at post time via `apply_finance_ap_settlement`, which re-checks and raises `finance_ap_over_settlement`. The settlement status machine (`finance_settlements_status_check`, 20260729150000:123) gives `executed` exactly one exit — `posted`. `discard_finance_settlement_draft` only accepts `draft`/`submitted`; `request_finance_settlement_reversal` only accepts `posted`.

**Claimed failure scenario.** AP open item I has open_amount 1000. Settlement S1 and S2 are each prepared for 1000 against I (both pass prepare validation, since neither has applied yet), both approved, and both executed — meaning `execute_finance_settlement` recorded that both bank transfers were actually sent. S1 posts: I.settled=1000, status 'settled'. S2's post raises `finance_ap_over_settlement` and rolls back. S2 is now permanently `executed`: it can never post, can never be voided, and can never be reversed. 1000 has left the bank with no AP relief, no GL entry, and no terminal record.

**Proposed fix.** Lock the AP open items (`for update`) and re-check open_amount inside `prepare_finance_settlement`, and/or add a governed `executed -> void`/`failed` transition so a settlement that cannot post has a terminal, auditable exit.

#### prepare_finance_journal_reversal / prepare_finance_journal_adjustment replay on idempotency_key alone and share one key namespace, so a reused key returns a correction against a different journal or of a different type

- **File:** `supabase/migrations/20260729200000_create_finance_reversal_adjustment.sql`:152
- **Symbol:** `app.prepare_finance_journal_reversal`
- **Category:** idempotency-target-mismatch

**Claim.** Both preparers short-circuit on `where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key` (line 152 for reversal, line 229 for adjustment) with zero comparison of the request. Table: `app.finance_journal_corrections`, unique on `(tenant_id, idempotency_key)` (line 71) — one namespace shared by both correction types. Discriminator columns that should be compared: `original_journal_id`, `correction_type`, `correction_date`, `company_id`, `reason`, `evidence_ref`, and `adjustment_lines` (adjustment only). Because the two functions share the namespace, `prepare_finance_journal_reversal` will happily return a row whose `correction_type = 'adjustment'`, and vice versa.

**Claimed failure scenario.** Accountant prepares a reversal of journal J1 with key 'REV-JUN-CLOSE'. Later, correcting a different mistake, they call `prepare_finance_journal_reversal(tenant, company, J2, ..., 'REV-JUN-CLOSE')`. The function returns the J1 correction row unchanged — no `finance_correction_duplicate_reversal`, no error. They submit, approve and `post_finance_correction` it; `app.create_and_post_finance_system_journal` posts the flipped lines of J1 (line 452-455), so J1 is reversed a second time in substance while J2 — the journal they actually meant to reverse — is left standing. A cross-type variant: a key already used by `prepare_finance_journal_adjustment` returns an adjustment row from the reversal entry point, and the caller's downstream `correction_type = 'reversal'` assumptions silently break.

**Proposed fix.** Compare `original_journal_id`, `correction_type`, `correction_date`, `company_id` and `adjustment_lines` against the found row and raise a named conflict on mismatch, or adopt `app.claim_finance_idempotency_key` with scope 'correction' and a fingerprint over those inputs.

#### Reconciliation bounds the GL side by fiscal-period end date and the subledger side by document date, so any mid-period run reports a false variance and blocks certification

- **File:** `supabase/migrations/20260729230000_create_finance_reconciliation.sql`:190
- **Symbol:** `app.execute_finance_reconciliation_run`
- **Category:** correctness

**Claim.** The control-account total is filtered `fp.end_date <= p_as_of_date` (line 190) — a batch counts only once its whole fiscal period has ended — while the source total is filtered by the document's own business date, `invoice_date <= p_as_of_date` / `bill_date <= p_as_of_date` (lines 197, 200). The two sides therefore use incompatible as-of bases whenever `p_as_of_date` is not exactly a period end. `app.get_finance_cash_position` replicates the same mismatch (supabase/migrations/20260729250000:433 vs 439: `t.transaction_date <= p_as_of_date` against `fp.end_date <= p_as_of_date`).

**Claimed failure scenario.** Tenant has one issued invoice of 10,000 dated 2026-06-05, posted into period 2026-06 (end_date 2026-06-30). Call `execute_finance_reconciliation_run(tenant, null, 'ar', '2026-06-15', 0, ...)`. control_total = 0 (the period has not ended, so the ar_control lines are excluded); source_total = 10,000. `is_within_tolerance` is false, a `finance_reconciliation_exceptions` row is created, and `certify_finance_reconciliation_run` refuses with `finance_reconciliation_unexplained_variance`. Every mid-period reconciliation run is guaranteed to fail by the full amount of the current period's postings.

**Proposed fix.** Bound the GL side by the batch's real business posting date. `finance_subledger_batches` has no posting-date column; add one (populated from `p_posting_date` in `post_finance_subledger_batch`) and filter on it, so both sides share one as-of basis.

#### Direct-device telemetry has no replay dedup, and the gateway's own durable-buffer retry path guarantees duplicate ingestion

- **File:** `supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql`:123
- **Symbol:** `app.direct_device_telemetry_reports / app.ingest_direct_device_telemetry_batch`
- **Category:** telemetry-dedup

**Claim.** `app.direct_device_telemetry_reports` (lines 97-124) carries only two plain indexes -- `(device_id, received_at desc)` and `(tenant_id, received_at desc)` -- and no unique constraint of any kind. `app.ingest_direct_device_telemetry_batch` takes no idempotency key and does no existence check before its INSERT; every call inserts a fresh row per report with a fresh `gen_random_uuid()` id. The sibling third-party path deliberately does the opposite: `third_party_telemetry_reports_connection_event_unique on (connection_id, provider_event_id)` (20260729380000 line 171), whose own table comment calls it 'used for idempotent replay defense'.

Because the canonical layer dedups on `(source_type, source_report_id)` and `source_report_id` is that fresh raw-row id, `app.arbitrate_and_project_vehicle_position`'s dedup short-circuit (20260730350000 line 262) can never recognise a replay -- it only protects against re-canonicalizing the identical raw row.

The replay is not hypothetical, it is built into the gateway: services/gps-gateway/src/server.ts lines 365-372 treat ANY throw from `ingestClient.ingestBatch` as a live-ingest failure and durably enqueue the batch; src/ingestClient.ts lines 90-92 throw on any Supabase error, including a read/network timeout that occurs after Postgres already committed the RPC. src/buffer.ts line 234 then re-calls the identical `ingestBatch(batch.deviceId, batch.reports)` on the next flush pass (src/index.ts line 58-60, every 30s). Teltonika-level retransmission on a lost ACK (see the encodeAckResponse contract, src/codec8e.ts line 254) is a second, independent duplication path.

**Claimed failure scenario.** Device D sends one Codec-8E packet of 20 records. `ingest_direct_device_telemetry_batch` commits all 20 rows, then the HTTP response is lost to a transient network blip, so supabase-js surfaces an error. server.ts:369-371 logs 'live ingest failed, buffering durably' and enqueues the batch. 30 seconds later buffer.flush() re-sends the identical 20 reports; the RPC accepts them and inserts 20 MORE rows into `app.direct_device_telemetry_reports` with new ids, and calls `arbitrate_and_project_vehicle_position` 20 more times with new `source_report_id`s. Result: `app.get_direct_device_telemetry_reports` and `app.get_vehicle_telemetry_history` show every fix twice, 20 spurious `app.canonical_telemetry_events` rows are written with `rejection_reason = 'stale_event_time'` (a wrong reason -- they are duplicates, not stale), `accepted_count`/audit evidence report 40 accepted reports for 20 real fixes, and `app.gps_devices.last_telemetry_at` bookkeeping is driven by a replayed batch.

**Proposed fix.** Give the direct-device path the same replay defense the third-party path already has: add a unique index on the raw table (e.g. `(device_id, event_at, report_type)`, or a device-supplied record identifier if one is threaded through from Codec 8E), and have `app.ingest_direct_device_telemetry_batch` skip-and-count an already-present report instead of inserting -- so a buffered-batch retry is a no-op rather than a duplicate.

#### Tenant-wide Fleet Control Tower signal queues skip app.can_access_record, leaking shipment data past record scope

- **File:** `supabase/migrations/20260730100000_create_advanced_tms_fleet_control_tower.sql`:142
- **Symbol:** `app.get_tenant_pending_exception_signals / app.get_tenant_pending_milestone_candidates`
- **Category:** authorization-gap

**Claim.** Both tenant-wide read RPCs added by ATW-226H are SECURITY DEFINER and gate on `app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View')` ONLY -- `get_tenant_pending_milestone_candidates` at line 107, `get_tenant_pending_exception_signals` at line 142. Neither calls `app.can_access_record(...)`. Their per-shipment siblings in the same feature family DO enforce it: `app.get_shipment_milestone_candidates` (20260730090000 line 944 OPS:View, line 949 can_access_record) and `app.get_shipment_exception_signals` (line 987/992). The house convention for tenant-wide reads over shipment-derived rows is also record-scoped -- `app.exceptions_directory` (20260727150000 line 947) filters on `app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)`.

These functions are the ONLY read path: `app.shipment_milestone_candidates` and `app.shipment_exception_signals` have RLS enabled with zero policies and zero `authenticated` grant (20260730090000 lines 1366-1376), so the definer function's own check is the entire access control. `app.can_access_record` (20260716110430 lines 31-67) grants only on owner match, caller's own org_unit being in the shared list, or supreme admin -- plain tenant membership is NOT sufficient -- so the missing check is a real widening, not a no-op.

Reachable end to end: server/queries/fleet-control-tower.ts:52,69 -> app/(tenant)/[tenantSlug]/operations/fleet-control-tower/page.tsx:41-43, a page gated only by `resolveOperationsAccessForRequest`.

**Claimed failure scenario.** Tenant T has users U1 (owner of shipment S, org unit A) and U2 (org unit B, holds OPS:View, not S's owner, not in A). U2 calls `app.get_shipment_exception_signals(S, U2)` -> correctly raises `insufficient_authority`. U2 then opens /operations/fleet-control-tower, which calls `app.get_tenant_pending_exception_signals(T, U2)` -> returns S's pending route_deviation / overdue_geofence_arrival / tracking_health_no_signal rows including `so.shipment_number`, `s.shipment_leg_id`, the free-text `s.description` (which embeds off-route distance and stop identifiers), and `ST_AsGeoJSON(s.location)` -- the vehicle's exact GPS coordinates. The same call to `get_tenant_pending_milestone_candidates` additionally returns candidate arrival/departure coordinates and times for the same out-of-scope shipment. U2 can then confirm/dismiss those signals via the page's own actions.

**Proposed fix.** Filter both `return query` bodies by record scope, matching the per-shipment siblings and `app.exceptions_directory`: join `app.shipment_orders so` (already joined for `shipment_number`) and add `and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)` to each WHERE clause, via a same-signature CREATE OR REPLACE.

#### item_masters_select_scoped has no owner-scope branch while its own child item_control_policy_versions_select_scoped does — cross-customer SKU catalogue leak

- **File:** `supabase/migrations/20260730160000_create_advanced_tms_item_uom_master.sql`:544
- **Symbol:** `item_masters_select_scoped`
- **Category:** tenant-isolation

**Claim.** `create policy item_masters_select_scoped on app.item_masters for select to authenticated using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());` (lines 544-546). `app.item_masters` carries an `owner_account_id` column — it is per-customer data (code, name, description, base_uom_code, lot/serial/expiry control flags).

The inconsistency is internal to the same feature family and provable side by side: the child table's policy, `item_control_policy_versions_select_scoped` at supabase/migrations/20260730220000_create_advanced_tms_lot_batch_serial_expiry.sql:1267-1272, is `using ((app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin()) and app.actor_can_view_owner_scoped_row(auth.uid(), tenant_id, owner_account_id))` — it does apply the owner-scope predicate against the very same `owner_account_id`. So the per-item control *policy* is owner-scoped but the item *master* it hangs off is not. `app.actor_can_view_owner_scoped_row` (20260730220000:816) is correct and already granted to `authenticated` (line 1303); the item_masters policy simply omits it.

**Claimed failure scenario.** Same scratch-DB fixture as the accounts finding. Two item masters are inserted into tenant `probe1`: `SKU-Alpha` (owner_account_id = Alpha, description `secret spec for Probe Alpha Ltd`) and `SKU-Beta` (owner_account_id = Beta, description `secret spec for Probe Beta Ltd`). Reading as the Alpha-scoped customer_user session (`sub` = `...ff002`), `select code, description, owner_account_id from app.item_masters;` returns BOTH rows, so Alpha's portal session reads Beta's SKU codes, names and descriptions. Expected: 1 row. Actual: 2 rows. A staff-only tenant member in an unrelated branch gets the same tenant-wide result.

**Proposed fix.** New migration: `drop policy item_masters_select_scoped on app.item_masters; create policy item_masters_select_scoped on app.item_masters for select to authenticated using ((app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin()) and app.actor_can_view_owner_scoped_row(auth.uid(), tenant_id, owner_account_id));` — byte-identical to the expression its own child table already uses, so it is a pure AND-narrowing that cannot widen access for any staff actor (`app.resolve_actor_owner_account_scope` returns NULL/unrestricted for supreme_admin, tenant_admin, org_user and no-membership actors).

#### 19 WMS/warehouse-billing policies admit a customer_user-layer actor with no warehouse-eligibility check, contradicting the invariant migration 20260730311000 was written to establish

- **File:** `supabase/migrations/20260730240000_create_advanced_tms_wms_picking.sql`:2255
- **Symbol:** `wms_pick_tasks_select_scoped`
- **Category:** authorization-gap

**Claim.** Migration supabase/migrations/20260730311000_harden_customer_inventory_access_rls_isolation.sql closed this exact hole on four tables (`wms_outbound_orders`, `wms_outbound_order_lines`, `lot_identities`, `serial_identities`) by AND-ing in `not app.actor_holds_customer_user_layer(tenant_id)`, and its header states the resulting invariant: "a customer_user actor's ONLY read path for these tables is now genuinely the SECURITY DEFINER RPCs", and that revoking `app.warehouse_customer_eligibility` "takes effect immediately". Nineteen sibling policies in the same warehouse/owner-scoped family were left with the pre-hardening expression `app.wms_pick_record_scope_ok(auth.uid(), warehouse_id, owner_account_id::text) and app.actor_can_view_owner_scoped_row(auth.uid(), tenant_id, owner_account_id)` (or the parent-join form of it), which admits a customer_user:

- wms_pick_tasks_select_scoped (20260730240000:2255)
- wms_pick_task_confirmations_select_scoped (20260730240000:2263), wms_pick_task_shorts_select_scoped, wms_pick_substitution_approvals_select_scoped (same file)
- wms_packing_tasks_select_scoped (20260730250000:1653), wms_packages_select_scoped (:1662), wms_package_lines_select_scoped, wms_package_line_scans_select_scoped, wms_package_confirmations_select_scoped
- wms_outbound_shipments_select_scoped (20260730260000:1483), wms_shipment_packages_select_scoped, wms_shipment_load_events_select_scoped, wms_shipment_confirmations_select_scoped, wms_shipment_issue_lines_select_scoped, wms_billing_eligibility_events_select_scoped (:1544)
- cycle_count_scope_items_select_scoped (20260730270000:1441), cycle_count_observations_select_scoped
- warehouse_billing_events_select_scoped (20260730300000:2001), warehouse_billing_handoffs_select_scoped

`app.wms_pick_record_scope_ok` (SECURITY DEFINER) resolves to `app.can_access_record(uid, w.tenant_id, null, ..., p_owner_account_ref)`, whose customer branch matches `pm.customer_account_ref = p_owner_account_ref` — so a customer_user passes on their own `owner_account_id`. No policy anywhere references `app.customer_warehouse_eligibility_active` (20260730310000:~290), so eligibility is never consulted on the raw path. These rows carry staff-internal fields the RPC layer deliberately withholds: `wms_pick_tasks.claimed_by_auth_user_id`/`claimed_by_label`/`source_location_id`/`exception_reason`, `wms_packages.qc_status`/`qc_override_reason`/`qc_by_label`/`seal_number`, `warehouse_billing_events.base_amount`/`rate_component_id`/`calculation_explanation`/`hold_reason`/`reviewed_by_auth_user_id`.

**Claimed failure scenario.** Scratch DB, tenant `probe1`, warehouse `WH-PB1` for which the Alpha customer_user has NO `app.warehouse_customer_eligibility` row at all. Evaluating the literal USING clause with that actor's uid: `app.customer_warehouse_eligibility_active(tenant, WH-PB1, alpha)` = **false**, yet `app.wms_pick_record_scope_ok('...ff002', WH-PB1, alpha::text) and app.actor_can_view_owner_scoped_row('...ff002', tenant, alpha)` = **true**. So a portal session whose warehouse eligibility was never granted (or was revoked) still reads every `wms_pick_tasks` / `wms_packages` / `wms_outbound_shipments` / `warehouse_billing_events` row for its own account in that warehouse via `GET /rest/v1/wms_pick_tasks?select=*` — including the picker's auth user id, internal bin locations, QC override reasons and the internal billing base_amount/rate breakdown. The same predicate correctly returns false for Beta-owned rows, confirming the owner filter works and the missing piece is specifically the customer-layer denial + eligibility gate. Meanwhile scripts/db-tests/advanced-tms-customer-inventory-access.sql:728-789 asserts exactly the opposite outcome for the four tables 20260730311000 did narrow.

**Proposed fix.** New migration applying the identical pure AND-narrowing 20260730311000 already used, to each of the 19 policies: drop and recreate with `not app.actor_holds_customer_user_layer(<tenant_id expr>) and <existing expression>`. `app.actor_holds_customer_user_layer(uuid, uuid)` is already created and granted to `authenticated, service_role` (20260730311000, final line), so no new helper is needed. As in 20260730311000, no staff actor is affected because none holds a customer_user-layer membership.

### MEDIUM

#### generate_wms_pick_task auto-select takes the first FIFO/FEFO candidate without checking it has enough available stock, hard-failing when a later location could satisfy the task

- **File:** `/home/user/cargogrid.app/supabase/migrations/20260730380000_harden_advanced_tms_wms_idempotency_target_mismatch.sql`:1036
- **Symbol:** `app.generate_wms_pick_task`
- **Category:** correctness

**Claim.** The auto-select loop (lines 1032-1046) walks `app.list_allocation_candidates` and accepts the first candidate whose location is `pick_enabled` and `active`; it never compares `v_candidate.available` to `p_quantity`. The reservation is then attempted for the full `p_quantity` against that one location (line 1052), which raises `insufficient_available_stock` and aborts the whole call. The sibling resolver in `app.approve_wms_pick_substitution` (same file, lines 1570-1583) does contain the missing guard verbatim: `if v_candidate.available < v_task.task_quantity then continue; end if;` -- so the omission is an inconsistency, not a deliberate policy. `list_allocation_candidates` only filters `available > 0`, so a candidate with a single unit is enough to shadow every later location.

**Claimed failure scenario.** Reproduced on a scratch DB. Item SKU-PROBE-SPLIT2 was given 2 units at RACK-PICK-A and 50 units at RACK-PICK-B (both pick_enabled/active, no lot control). `app.list_allocation_candidates` returns RACK-PICK-A (available=2) first, then RACK-PICK-B (available=50). `app.generate_wms_pick_task(<line>, 10, null, null /* p_location_id = auto */, ...)` fails with `insufficient_available_stock: 2 available but 10 requested`, even though RACK-PICK-B alone can cover the full 10. The pick task can never be auto-generated; an operator must manually supply p_location_id, which defeats the FIFO/FEFO auto-select and, for a warehouse with many small leftover balances, blocks wave generation entirely.

**Proposed fix.** Add `if v_candidate.available < p_quantity then continue; end if;` at the top of the auto-select loop body in `app.generate_wms_pick_task`, matching `app.approve_wms_pick_substitution`'s existing guard, so the resolver skips to the next FIFO/FEFO candidate that can actually satisfy the requested quantity.

#### Serial-controlled on-hand<=1 check reads a single arbitrary balance row instead of summing across locations, allowing the same serial to exist twice

- **File:** `/home/user/cargogrid.app/supabase/migrations/20260730390000_harden_platform_operations_finance_idempotency_target_mismatch.sql`:1784
- **Symbol:** `app.post_inventory_movement`
- **Category:** constraint-violation

**Claim.** The serial guard is `select on_hand into v_serial_on_hand from app.inventory_balances where tenant_id = ... and warehouse_id = ... and item_master_id = ... and serial_number = v_serial_number and status = v_status;` followed by `if v_serial_on_hand > 1 then raise 'serial_conflict' ...`. `app.inventory_balances`' unique index is per (tenant, warehouse, owner, item, LOCATION, lot, serial, status) (20260730190000 line 159), so the same serial legitimately has one row per location. A non-STRICT `SELECT ... INTO` over multiple rows silently takes one arbitrary row, so the check reads a single location's on_hand (always 1) and never the warehouse total. This breaks the invariant the function's own comment asserts ("a serial exceeding 1 both fail the whole call", 20260730190000 line 417) and that the db-test names ("serial-controlled items: on_hand may never exceed 1 for the same serial number", scripts/db-tests/advanced-tms-inventory-ledger.sql line 276) -- the test only ever re-receives at the SAME location, so it passes.

**Claimed failure scenario.** Reproduced on a scratch DB: for serial-controlled item SKU-INV-SERIAL, `post_inventory_movement('opening_balance', ..., location=DOCK-1, signed_quantity=1, serial_number='SN-9999')` succeeds; a second call with the identical serial but `location=BIN-1` is ACCEPTED (no serial_conflict). Query afterwards: `sum(on_hand)=2 across 2 balance rows` for SN-9999 in one warehouse. Downstream, `app.list_allocation_candidates` now returns two candidate rows for the same physical unit and two separate pick tasks can each reserve and ship 'SN-9999', so the ledger reports shipping one physical serialized unit twice.

**Proposed fix.** Change the guard to an aggregate over the whole serial scope, e.g. `select coalesce(sum(on_hand), 0) into v_serial_on_hand from app.inventory_balances where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and item_master_id = v_item_master_id and serial_number = v_serial_number and status = v_status;` (and consider dropping the `status` narrowing so a serial cannot be simultaneously on_hand at one location and damaged at another). Add a db-test that receives the same serial at two different locations.

#### listTenantUsers does select("*") on app.users, which the authenticated role has no table-level SELECT grant on — the query can never succeed

- **File:** `server/queries/user-lifecycle.ts`:27
- **Symbol:** `listTenantUsers`
- **Category:** authorization

**Claim.** `client.from("users").select("*").eq("tenant_id", tenantId)` at server/queries/user-lifecycle.ts:27. `supabase/migrations/20260716110430_create_field_record_access.sql:132-137` deliberately does `revoke select on app.users from authenticated;` and re-grants SELECT on an explicit 17-column list that omits `email`, precisely so 'a bare column-level REVOKE ... cannot carve an exception out of PLT-113's broader table-level grant'. Postgres denies `SELECT *` when any column lacks a grant — confirmed on the applied schema: `set role authenticated; select * from app.users limit 1;` -> `ERROR: permission denied for table users`, while `select id, tenant_id from app.users` succeeds. This is the same defect class as the already-fixed `getThirdPartyProviderConnection` select("*"), and server/queries/third-party-provider-adapter.ts:36-42 documents exactly this rule; user-lifecycle.ts was missed. Compounding it, the query is unfixable by narrowing the column list alone: `UserSchema.email` (server/contracts/user-lifecycle/user-lifecycle.ts:19) is a required `z.string().email()` and `parseUser` reads `row.email`, but `authenticated` can never read that column — the intended read path is `app.users_directory` (already used correctly by server/queries/field-access.ts:62 and server/queries/portal-users.ts:74).

**Claimed failure scenario.** Any caller passing the RLS-scoped client from `lib/supabase/server.ts` (the mandated client for a tenant-admin surface) into `listTenantUsers(supabase, tenantId)` gets `{ error: { message: "permission denied for table users" } }` back from PostgREST for every call, and the function throws `UserLookupError` unconditionally — zero rows are ever returned regardless of tenant, RLS, or permissions. Switching to a narrowed column list would still fail at `UserSchema.parse` because `email` would be undefined against a required `z.string().email()`.

**Proposed fix.** Read `app.users_directory` instead of `app.users` with an explicit column list, and make `UserSchema.email` reflect the masked projection (`email` plus `emailMasked`), matching what `parseUserDirectoryEntry` in server/contracts/field-access/field-access.ts already does.

#### set_custom_field_values: a legitimate retry of an earlier submission silently clobbers newer values

- **File:** `supabase/migrations/20260719120000_create_form_custom_field_builder.sql`:480
- **Symbol:** `app.set_custom_field_values`
- **Category:** data-loss

**Claim.** `app.custom_field_values` stores exactly one row per `(tenant_id, entity_type, entity_id)` (line 394) and carries the idempotency key ON that row under `unique (tenant_id, idempotency_key)` (line 395). The replay lookup at line 467 matches on `(tenant_id, idempotency_key)` with no `entity_type`/`entity_id` discriminator, and the upsert branch at lines 477-481 OVERWRITES `idempotency_key` with the newest key. So the key of an earlier request stops existing the moment a newer submission lands for the same entity, and the replay guard for that earlier request silently stops working; the upsert then applies the stale payload with no version check and no error.

**Claimed failure scenario.** User submits custom-field values V1 for shipment S with key K1 — row created, idempotency_key=K1. User corrects a field and submits V2 with key K2 — the same row is updated to V2 and idempotency_key becomes K2. A network-layer or client retry of the original K1 request now arrives: the lookup at line 467 finds nothing (the row holds K2), validation passes, the entity lookup at line 474 finds the row, and lines 477-481 write `values = V1, idempotency_key = K1`. V2 is silently destroyed and both submissions reported success. Separately, reusing one key across two different entities (line 467 has no entity predicate) returns the first entity's row and discards the second entity's values entirely.

**Proposed fix.** Move idempotency keys to a separate per-request table (or add `entity_type`/`entity_id` to the lookup and never overwrite the stored key), and add a `p_expected_version` optimistic-concurrency predicate to the UPDATE at line 480.

#### claim_next_job re-claims a stale lease without incrementing attempts — a crash-looping job never reaches the DLQ and starves the queue

- **File:** `supabase/migrations/20260719180000_create_background_job_framework.sql`:270
- **Symbol:** `app.claim_next_job`
- **Category:** correctness

**Claim.** The claim predicate at line 270 makes any `in_progress` row whose `locked_until` has passed eligible again, and the function deliberately does not touch `attempts` (documented at lines 241-244). `attempts` is incremented only by `app.record_job_failure`, which a worker that died mid-job never gets to call. So the retry ladder the migration header promises ("exponential backoff -> max attempts -> DLQ after failure", lines 40-41) is never entered for a crash — `compute_job_backoff_seconds` is never consulted and `next_attempt_at` is explicitly reset to null on every claim (line 284). Ordering by `priority desc, created_at asc` (line 272) means the oldest such row is handed out first, ahead of newer work.

**Claimed failure scenario.** A `document_generation` job whose payload deterministically kills the worker process (OOM, segfault, unhandled native crash) is enqueued with max_attempts=3. Worker W1 claims it, dies; the lease expires after 300s. W2 claims the same row (attempts still 0, next_attempt_at null), dies. W3 claims it, dies. `attempts` stays 0 forever, `status` never becomes `dead_letter`, `error` is never set, and because it sorts first by `created_at asc` every free worker keeps picking it up ahead of every newer job of the same type. The queue is permanently poisoned and no operator-visible DLQ entry ever appears.

**Proposed fix.** Increment `attempts` when the claim is a stale-lease reclaim (i.e. when the selected row's `status` was already `in_progress`), and dead-letter it in the same statement once `attempts >= max_attempts`; alternatively add a separate reaper that calls `app.record_job_failure` for expired leases before they become claimable.

#### enqueue_job's idempotency lookup spans every job type including import/export — the requested job is silently never enqueued

- **File:** `supabase/migrations/20260719180000_create_background_job_framework.sql`:200
- **Symbol:** `app.enqueue_job`
- **Category:** idempotency-target-mismatch

**Claim.** Line 200 selects `from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key` and returns that row. Missing discriminator columns: `job_type` and `payload`. The key space is genuinely shared — `app.jobs.jobs_idempotency_key_unique` is `unique (tenant_id, idempotency_key)` across all types (20260719170000:276), and `app.create_import_export_job` uses the identical unguarded lookup (20260719170000:367). So an `enqueue_job` call can be answered by an `import` job and vice versa, and the caller is handed a job whose `job_type` and `payload` it never requested.

**Claimed failure scenario.** A nightly scheduler enqueues an import job with `p_idempotency_key = 'acme-2026-08-05'` via `create_import_export_job`. A different subsystem later calls `app.enqueue_job(acme, 'report_generation', {...}, 0, 'acme-2026-08-05', 3, actor, label)` using the same date-derived key. `enqueue_job` returns the import job row: `job_type='import'`, `payload` = the import filters, `import_export_schema_code` and `source_file_id` set. No report_generation job is ever created and no error is raised; the caller records a successful enqueue and the report never runs. A worker polling `job_types => ARRAY['report_generation']` never sees it.

**Proposed fix.** Guard the short-circuit: `if v_existing.job_type <> p_job_type or v_existing.payload is distinct from coalesce(p_payload,'{}'::jsonb) then raise 'idempotency_key_conflict' using errcode = 'unique_violation'; end if;` — and apply the same guard at 20260719170000:367.

#### app.next_quotation_number is granted to `authenticated` with no tenant check, letting any logged-in user burn another tenant's quote-number sequence

- **File:** `supabase/migrations/20260724210000_create_commercial_quotation_builder.sql`:70
- **Symbol:** `app.next_quotation_number`
- **Category:** tenant-isolation

**Claim.** `app.next_quotation_number(p_tenant_id uuid)` is `security definer` and performs `insert into app.quotation_number_counters (tenant_id, last_seq) values (p_tenant_id, 1) on conflict (tenant_id) do update set last_seq = last_seq + 1 returning last_seq`. It verifies nothing at all about the caller — no membership, no permission, no actor parameter — and line 923 grants it to `authenticated`. The table's own comment declares the invariant this breaks: "Never recycled -- last_seq only increases", and `app.quotations` carries `quotations_tenant_number_unique`, so the sequence is the tenant's authoritative, gap-free quotation numbering.

**Claimed failure scenario.** Verified live against a scratch DB: a session with role `authenticated` and no membership anywhere called `app.next_quotation_number('<victim tenant uuid>')` three times and drove `app.quotation_number_counters.last_seq` from 0 to 3 for that tenant. Scripted, this advances a competitor's counter by millions, so their next genuine `app.create_quotation_draft` issues e.g. QTN-2026-004312 instead of QTN-2026-000042 — an unexplained, permanent, unauditable gap in a document series that finance and audit treat as sequential, plus unbounded write amplification on a single hot row. The only input required is the tenant UUID, obtainable from the anon-callable `app.resolve_tenant_by_domain`.

**Proposed fix.** Revoke `authenticated` on line 923 (the function is only ever called from `create_quotation_draft`, `clone_quotation` and `create_quotation_revision`, all of which are SECURITY DEFINER and already hold the caller's authority), matching the service_role-only posture `app.allocate_numbering_seq` uses.

#### transition_shipment_order can commit a transition-history row without applying the status change and return a NULL composite

- **File:** `supabase/migrations/20260727110000_create_operations_shipment_lifecycle.sql`:219
- **Symbol:** `app.transition_shipment_order`
- **Category:** race

**Claim.** The function reads the shipment with a plain `select` (line 126), validates `record_version` (line 137), inserts the append-only history row (lines 208-212), and only then runs `update app.shipment_orders ... where id = p_shipment_order_id and record_version = p_expected_version returning * into v_shipment` (lines 219-223). There is no `if not found then raise` after that UPDATE. Under READ COMMITTED a concurrent transition that commits first bumps `record_version`, so this UPDATE matches zero rows: `v_shipment` becomes a NULL composite, the already-inserted history row still commits, `capture_audit_event` is called with `v_shipment.tenant_id` = NULL and `v_shipment.id` = NULL (both nullable in `app.audit_logs`) recording result 'success', and the function returns a row of NULLs.

**Claimed failure scenario.** Two dispatchers act on shipment S (status 'confirmed', record_version 5) at the same instant with different idempotency keys, both requesting 'planned'. T1 commits: status planned, version 6, history row 1. T2's SELECT saw version 5 so its version check passed; its INSERT into `app.shipment_status_transitions` succeeds (different key, no lock on shipment_orders); its UPDATE then matches nothing. Result: `app.shipment_status_transitions` holds two `confirmed->planned` rows for one real transition, `app.audit_logs` holds a `transition_shipment_order` success event with `tenant_id` NULL, and T2's caller receives an all-NULL `app.shipment_orders` composite which `parseShipmentOrder` (server/mutations/shipment-lifecycle.ts) will either reject or surface as garbage. The migration's own invariant — history explains the status projection — is broken.

**Proposed fix.** Add `if not found then raise exception 'stale_version: ...' using errcode = 'serialization_failure'; end if;` immediately after line 223, or take `select ... for update` on the shipment row at line 126 so the version check and the UPDATE are serialized.

#### ingest_milestone_event replay has no milestone-code discriminator — a delivery milestone is silently discarded and the projection never recomputed

- **File:** `supabase/migrations/20260727140000_create_operations_milestone_management.sql`:559
- **Symbol:** `app.ingest_milestone_event`
- **Category:** idempotency-target-mismatch

**Claim.** Line 559 selects on `(tenant_id, shipment_order_id, idempotency_key)` and returns `v_event` on a hit. Missing discriminator columns: `milestone_code`, `event_time`, `source`, `corrects_event_id`. Because the short-circuit returns before the INSERT, `app.recalculate_shipment_milestone_projection` (line 573) is also skipped, so `app.shipment_milestone_projections` keeps the prior projection. The reachability is concrete: `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx:313` binds a single `milestoneIdempotencyKey = randomUUID()` per render to the milestone form, so any resubmission of a still-mounted page reuses the key with a different code.

**Claimed failure scenario.** Operator ingests `DEPARTED_ORIGIN` for shipment S with key K. Without a fresh page render, they ingest `DELIVERED` with the same key K. The function returns the DEPARTED_ORIGIN event row with no error. `app.milestone_events` never receives the delivery event, `app.get_shipment_milestone_timeline` shows no delivery, `app.shipment_milestone_projections.last_milestone_code` stays DEPARTED_ORIGIN and `is_delayed` is never re-evaluated, and any downstream customer-visible tracking surface reports the shipment as still in transit.

**Proposed fix.** Guard the short-circuit: raise `idempotency_key_conflict` (errcode `unique_violation`) when `v_event.milestone_code <> p_milestone_code or v_event.event_time is distinct from p_event_time or v_event.corrects_event_id is distinct from p_corrects_event_id`; bind a fresh key per milestone form submission in the UI.

#### add_actual_cost_component replay has no line discriminator — a real cost line is silently dropped and total_amount understated

- **File:** `supabase/migrations/20260728110000_create_operations_actual_cost.sql`:308
- **Symbol:** `app.add_actual_cost_component`
- **Category:** idempotency-target-mismatch

**Claim.** Line 308 selects `from app.shipment_actual_cost_components where actual_cost_id = p_actual_cost_id and idempotency_key = p_idempotency_key` and returns `v_existing` on a hit. Missing discriminator columns: `category`, `source_type`, `vendor_id`, `assignment_id`, `quantity`, `rate`, `minimum_charge`, `surcharge`. Because it returns early, the INSERT and the `app.recalculate_actual_cost_total` call (line 337) are both skipped, so the header's `total_amount` — which OPS-179 job profitability and the `shipment_actual_costs_directory` view both read — never reflects the omitted line.

**Claimed failure scenario.** A cost clerk adds a `trucking` component (rate 3,500,000, vendor V1) to draft cost header H with key 'inv-8842'. They then add a `customs` component (rate 12,000,000, vendor V2) and paste the same key 'inv-8842' from the vendor invoice they are transcribing. The function returns the trucking component row unchanged; the customs line is never inserted and `total_amount` stays at 3,500,000 instead of 15,500,000. The clerk sees a component row come back and moves on; `submit_actual_cost` then passes its `count(*) > 0` check and the header is approved 12,000,000 short.

**Proposed fix.** Guard the short-circuit: raise `idempotency_key_conflict` (errcode `unique_violation`) when any of `category`, `source_type`, `vendor_id`, `assignment_id`, `quantity`, `rate`, `surcharge` on `v_existing` differs from the corresponding parameter.

#### convert_finance_amount resolves the governed rounding 'order' setting, reports it in the response, and never applies it

- **File:** `supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql`:495
- **Symbol:** `app.convert_finance_amount`
- **Category:** silent-config-ignored

**Claim.** `v_order` is read from the tenant's effective `finance_rounding` config at lines 481/487/491 and returned as `roundingOrder` at line 499, but line 495 unconditionally computes `apply_finance_rounding(p_amount * v_rate.rate, ...)` — i.e. always convert_then_round. There is no branch on `v_order` anywhere in the function. `order` is not an inert field: the config engine explicitly validates it against `('convert_then_round','round_then_convert')` and rejects anything else (supabase/migrations/20260728200000_create_finance_configuration.sql:248-250), so a tenant that configures `round_then_convert` has made a governed, validated choice that is silently discarded while the API response claims it was honoured.

**Claimed failure scenario.** Tenant publishes `finance_rounding` with `{"fx_conversion": {"mode": "round_half_up", "precision": 0, "order": "round_then_convert"}}` for a JPY-reporting entity. Converting 1234.56 USD at rate 150.25: the configured behaviour is round(1234.56, 0) = 1235, then 1235 * 150.25 = 185,558.75 -> 185,559. The function instead computes 1234.56 * 150.25 = 185,492.64 -> 185,493, a 66 JPY difference, and returns `"roundingOrder": "round_then_convert"` asserting it did the opposite.

**Proposed fix.** Branch on `v_order`: when it is 'round_then_convert', round `p_amount` to `v_precision` before multiplying by the rate; otherwise keep the current path.

#### approve_finance_exchange_rate checks for overlapping approved windows with an unlocked read, so concurrent approvals produce two overlapping approved rates

- **File:** `supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql`:369
- **Symbol:** `app.approve_finance_exchange_rate`
- **Category:** race

**Claim.** The overlap guard is a plain `select count(*)` (lines 369-381) followed by an UPDATE, with no row lock, no advisory lock and no exclusion constraint backing it — `finance_exchange_rates` has only the non-unique lookup index at line 170. Under READ COMMITTED two concurrent transactions each see zero overlapping approved rows and both commit, violating the invariant this function's own comment asserts ("Approval rejects an overlapping already-approved window", lines 333-335). `app.resolve_finance_exchange_rate` then breaks the tie with `order by (tenant_id is null) asc, effective_from desc limit 1`, which is non-deterministic when both rows share an `effective_from`.

**Claimed failure scenario.** Two treasury users simultaneously approve drafts A (USD->EUR, spot, effective_from 2026-06-01, effective_to null, rate 0.92) and B (USD->EUR, spot, same window, rate 0.95). Both count queries return 0, both UPDATEs succeed, and two overlapping approved rates now exist. Subsequent `convert_finance_amount` calls pick either row arbitrarily (identical `effective_from`, no further ordering key), so the same 100,000 USD conversion yields 92,000 EUR or 95,000 EUR depending on plan/heap order — and re-running a report can change the answer.

**Proposed fix.** Back the invariant with a real constraint: a btree_gist EXCLUDE on (tenant-scope, rate_type, source_currency, target_currency, tstzrange(effective_from, effective_to)) WHERE status='approved'; or serialize with `pg_advisory_xact_lock` on the scope/pair hash before the count.

#### Fixed-amount tax rules are applied to invoices and vendor bills without checking the rule's own currency

- **File:** `supabase/migrations/20260729110000_create_finance_invoice.sql`:261
- **Symbol:** `app.prepare_finance_invoice_from_readiness`
- **Category:** currency-handling

**Claim.** `app.finance_tax_rule_versions` requires a non-null `currency` for `rate_basis = 'fixed_amount'` (`finance_tax_rule_versions_fixed_amount_currency_check`, supabase/migrations/20260729090000:132), and `app.calculate_finance_tax` returns that currency in its result (20260729090000:531). Both consumers read only `taxAmount` and discard `currency`: the invoice path at lines 260-264 posts `v_tax_amount` into an invoice denominated in `v_currency` (the Job Order's revenue-snapshot currency), and `app.prepare_finance_vendor_bill_from_actual_cost` does the same at supabase/migrations/20260729140000:261-265 against `v_cost.currency`. No comparison is made between the rule's currency and the document's currency.

**Claimed failure scenario.** Tenant approves a fixed_amount stamp-duty rule for code 'STAMP' with rate_value 10000 and currency 'IDR'. A USD job order (revenue snapshot currency 'USD', subtotal 5,000) is prepared with `p_tax_code = 'STAMP'`. `calculate_finance_tax` returns `{taxAmount: 10000, currency: 'IDR'}`; the invoice is written with tax_amount = 10000 and currency 'USD', total_amount 15,000 USD instead of 5,000 USD + ~0.61 USD. On issue this flows straight into `post_finance_ar_open_item` and the ar_control/tax_payable GL journal, so the customer is invoiced ~10,000 USD too much and the ledger is out by the same amount.

**Proposed fix.** After `calculate_finance_tax`, when `rateBasis = 'fixed_amount'` reject with a named exception unless `v_tax_result ->> 'currency'` equals the document currency (or convert via `app.convert_finance_amount` and record the rate).

#### execute_finance_reconciliation_run accepts and stores p_company_id but never filters by it

- **File:** `supabase/migrations/20260729230000_create_finance_reconciliation.sql`:205
- **Symbol:** `app.execute_finance_reconciliation_run`
- **Category:** correctness

**Claim.** `p_company_id` is written into `finance_reconciliation_runs.company_id` (line 205-206) and is the parameter the console filters runs by (`list_finance_reconciliation_runs`, line 327), but neither the control-total query (lines 185-190) nor the source-total queries (lines 195-201) reference company at all — they are tenant-wide. `finance_subledger_batches`, `finance_ar_open_items` and `finance_ap_open_items` all carry a `company_id` column, so the filter is available and simply not applied.

**Claimed failure scenario.** A tenant runs two companies. AR control balance and open items: Company A 100,000, Company B 40,000. Finance runs `execute_finance_reconciliation_run(tenant, CompanyA, 'ar', <period end>, 0, ...)`. The run row records company_id = Company A, but control_total and source_total are both 140,000. Company A's certified reconciliation evidence attests to a balance that is 40,000 larger than Company A's actual AR, and a genuine Company-A-only imbalance offset by an equal-and-opposite Company B imbalance is reported as reconciled.

**Proposed fix.** Add `(p_company_id is null or b.company_id = p_company_id)` to the control query and `(p_company_id is null or i.company_id = p_company_id)` to both source queries.

#### The as-of aging report filters and reports on current open_amount rather than the balance as of p_as_of_date

- **File:** `supabase/migrations/20260729240000_create_finance_aging.sql`:267
- **Symbol:** `app.get_finance_aging_report`
- **Category:** correctness

**Claim.** The report takes `p_as_of_date` and bounds inclusion by document date (`i.invoice_date <= p_as_of_date` at line 268, `i.bill_date <= p_as_of_date` at line 282), but the amount it selects and filters on — `i.open_amount` (lines 260, 267 and 274, 281) — is the generated live column `original_amount - allocated_amount`, which reflects every allocation made after `p_as_of_date`. `app.get_finance_aging_summary` aggregates the same rows (lines 305-309), so both are affected. The append-only `finance_ar_open_item_events` / `finance_ap_open_item_events` tables carry the deltas needed to compute a true as-of balance and are not used.

**Claimed failure scenario.** Invoice INV-1 for 10,000 dated 2026-06-01, due 2026-06-30, is fully paid by a receipt allocated on 2026-07-15. Re-running `get_finance_aging_report(tenant, null, 'ar', '2026-06-30', false, ...)` today (2026-08-05) evaluates `open_amount > 0` as 0 > 0 and drops the row entirely, so the 2026-06-30 AR aging shows 0 where it should show 10,000 in the 0-day bucket. The aging report therefore cannot be tied back to the AR control balance at that date, and a re-run of the same period-end report returns different totals each month as later allocations land.

**Proposed fix.** Compute the as-of balance from the open-item event trail (`original_amount` less the sum of `amount_delta` for events with `created_at <= p_as_of_date`), and filter on that value rather than the live `open_amount`.

#### Bank statement import deduplicates on a hash that cannot distinguish genuinely identical transactions, silently dropping real lines

- **File:** `supabase/migrations/20260729250000_create_finance_cash_bank.sql`:270
- **Symbol:** `app.import_finance_bank_statement`
- **Category:** silent-data-loss

**Claim.** `line_hash` is `md5(bank_account_id | transactionDate | direction | amount | coalesce(reference,''))` and the insert uses `on conflict (bank_account_id, line_hash) do nothing` (line 277). Nothing in the hash distinguishes two genuinely distinct transactions that happen to share date, direction, amount and reference — a common shape for fee lines, card transactions and same-day split remittances, which frequently carry no per-line reference. The migration's own comment (lines 209-212) calls the skip "a silent, safe no-op", but the skipped row is not a duplicate. `description` and any per-line ordinal are excluded from the hash.

**Claimed failure scenario.** A statement for account BA contains two separate 5.00 debit wire fees on 2026-06-01, both with an empty `reference`. Both hash identically; the second is dropped. The batch's `line_count` reports 1, so the operator has no signal. `get_finance_cash_position` then computes a statement balance 5.00 higher than the bank's, and every subsequent import of a statement containing those same fee amounts compounds the drift.

**Proposed fix.** Include the line's ordinal within the batch (and `description`) in the hash, or key dedup on a real bank-supplied unique transaction id when present and fall back to (batch_id, line index) otherwise, so only true re-imports of the same statement are suppressed.

#### import_finance_bank_statement replays on source_reference alone, discarding a corrected statement file

- **File:** `supabase/migrations/20260729250000_create_finance_cash_bank.sql`:249
- **Symbol:** `app.import_finance_bank_statement`
- **Category:** idempotency-target-mismatch

**Claim.** Lines 249-252 return the existing batch for `(tenant_id, bank_account_id, source_reference)` with no comparison of `p_lines`. Table: `app.finance_bank_statement_batches`; the only stored discriminator is `line_count`, and it is not checked. The correct discriminator is a canonical digest of `p_lines` (per line: transactionDate, direction, amount, reference, description).

**Claimed failure scenario.** Bank issues statement 'ACCT-9931-2026-06' with 120 lines; it is imported. The bank re-issues the same statement reference with 3 corrected lines and 5 additional late-posting entries. Re-running the import with the same `source_reference` returns the original batch and stages none of the 8 changed/new lines. The operator sees a successful import; the 5 missing transactions never reach `finance_bank_transactions`, so `get_finance_cash_position` under-reports the bank balance and the corresponding receipts/settlements can never be matched.

**Proposed fix.** Store a `request_fingerprint` on `finance_bank_statement_batches` computed from the canonicalized `p_lines`, compare it on replay, and raise a named conflict on mismatch instead of returning the stale batch.

#### app.allocate_shipment_leg_cargo has no lock, so concurrent per-leg allocations can exceed the shipment's own allocated_* basis

- **File:** `supabase/migrations/20260729290000_create_advanced_tms_multi_leg_shipment.sql`:543
- **Symbol:** `app.allocate_shipment_leg_cargo`
- **Category:** race

**Claim.** Lines 543-547 sum the allocations of every OTHER non-cancelled leg of the shipment, lines 549-560 compare that sum plus the request against `app.shipment_orders.allocated_quantity/allocated_weight_kg/allocated_volume_cbm`, and lines 562-568 upsert. Nothing between the read and the write serializes concurrent callers: there is no `for update` on the parent shipment order, no `pg_advisory_xact_lock`, and no exclusion constraint. `app.shipment_leg_cargo_allocations` enforces only one-row-per-leg (`shipment_leg_cargo_allocations_leg_unique`), never the cross-leg sum.

The table's own comment states the invariant as absolute: 'The sum of every non-cancelled leg's allocation for a shipment must never exceed that Shipment Order's own allocated_quantity/allocated_weight_kg/allocated_volume_cbm (app.allocate_shipment_leg_cargo enforces this)' (line 168). The repository's own comparable ledger does take a lock for exactly this shape -- `app.reserve_vehicle_capacity` acquires `select * from app.vehicle_operational_profiles ... for update` before summing overlapping reservations (20260730120000 lines 188-190, design note 3).

**Claimed failure scenario.** Shipment order S has allocated_weight_kg = 1000 and two planned legs L1 and L2, neither with an allocation row yet. Two dispatchers submit at the same instant: session X calls allocate_shipment_leg_cargo(L1, null, 1000, null, ...) and session Y calls allocate_shipment_leg_cargo(L2, null, 1000, null, ...). Both execute the sum at line 543 before either commits; each sees v_other_weight = 0, so 0 + 1000 > 1000 is false for both and neither raises `cargo_over_allocated`. Both INSERTs succeed on distinct shipment_leg_ids, so no unique constraint fires. S now carries 2000 kg allocated across its legs against a 1000 kg basis -- a permanently violated documented invariant, with downstream `app.confirm_shipment_leg_network` happily confirming the network (it only checks that every leg HAS an allocation, lines 640-647).

**Proposed fix.** Serialize on the parent before reading the sum -- either `select ... from app.shipment_orders where id = v_leg.shipment_order_id for update` (replacing the unlocked read at line 525) or `perform pg_advisory_xact_lock(hashtextextended(v_leg.shipment_order_id::text, <salt>))` before line 543, matching the technique app.reserve_vehicle_capacity and app.arbitrate_and_project_vehicle_position already use.

#### Geofence/deviation evaluator resolves at most one leg per vehicle with no deterministic tiebreak, silently dropping signals for concurrent shipments

- **File:** `supabase/migrations/20260730090000_create_advanced_tms_geofence_route_deviation_signals.sql`:581
- **Symbol:** `app.evaluate_geofence_and_deviation_signals`
- **Category:** correctness

**Claim.** Lines 576-584 resolve the leg to evaluate with:

  select sl.* into v_leg
  from app.resource_assignments ra
  join app.shipment_legs sl on sl.shipment_order_id = ra.shipment_order_id and sl.leg_status in ('dispatched','in_transit')
  where ra.role = 'vehicle' and ra.resource_id = p_vehicle_master_id and ra.is_current and ra.status = 'active'
  order by sl.sequence_no
  limit 1;

A vehicle may legitimately be the current active assignee of more than one shipment order at once -- the tracking-health writer added in the SAME call site explicitly says so and loops over all of them ('there may legitimately be zero, one, or more than one active shipment concurrently assigned the same vehicle -- no "exactly one" assumption', 20260730320000 design note 7, loop at lines 568-574). This evaluator instead takes `limit 1`. Worse, `sequence_no` is unique only per shipment order (`shipment_legs_tenant_shipment_sequence_unique`, 20260729290000 line 79), so when two concurrent shipments each have an executing leg with the same sequence_no the ORDER BY is a tie and Postgres may return either row, from one telemetry event to the next.

**Claimed failure scenario.** Vehicle V is the current role='vehicle' assignment on shipment A (leg A1, sequence_no=1, in_transit) and shipment B (leg B1, sequence_no=1, dispatched); both legs have tracking_required policies with geofence_policy enabled. V's telemetry arrives every 30s. Each accepted canonical event evaluates exactly one of A1/B1, chosen by an untied ORDER BY. A1's delivery-stop geofence needs dwell_seconds_before_confirm=120s of sustained presence (app.evaluate_stop_geofence lines 416-417) but only receives roughly half the position events, and each event routed to B1 leaves A1's `last_evaluated_at` frozen; B1 suffers symmetrically. Neither leg reliably reaches `confirmed_inside`, so no `delivery_arrival` milestone candidate is ever staged for either shipment, and sustained route deviation on the leg that keeps losing the tie is never confirmed -- both signals are silently absent rather than reported.

**Proposed fix.** Mirror the tracking-health writer: iterate every currently-executing leg for every shipment order currently assigned this vehicle (a FOR ... LOOP over the join, no LIMIT), calling app.evaluate_stop_geofence / app.evaluate_route_deviation once per leg. If a single-leg restriction is genuinely wanted, at minimum add a deterministic tiebreak (e.g. `order by sl.sequence_no, sl.id`) and disclose the dropped shipments.

#### Rejected telemetry still advances vehicle_source_health.last_location, causing the next good fix to be falsely rejected as impossible_movement

- **File:** `supabase/migrations/20260730350000_harden_advanced_tms_third_party_hybrid_tracking.sql`:385
- **Symbol:** `app.arbitrate_and_project_vehicle_position`
- **Category:** arbitration-correctness

**Claim.** The `app.vehicle_source_health` upsert at lines 380-390 runs unconditionally -- outside the `if v_apply then` block -- so `last_location` is advanced from `p_location` for EVERY candidate whose `p_event_at` is the newest seen for that source, including candidates the same call just rejected. The impossible-movement guard at lines 310-318 then measures the NEXT candidate from that same source against `v_source_health.last_location`.

That makes a rejected outlier the baseline for the following legitimate report. Note the rejection chain order (lines 281-319): `accuracy_below_threshold` is evaluated at line 306, BEFORE the impossible-movement elsif, so a low-accuracy fix is rejected for its accuracy yet still poisons `last_location` with its (by definition unreliable) coordinates.

CG-S10-ATW-027's own header (lines 85-103) discloses this unconditional update as a residual, but analyses only `last_seen_event_at` and concludes it 'would simply stop evaluating (v_elapsed_seconds <= 0, a skipped check, not a false rejection)'. That reasoning does not cover the `last_location` case, which produces a real false rejection. Only `app.ingest_driver_mobile_report` threads a real `p_accuracy_meters` (20260730360000 line 531); the other two ingestion RPCs hardcode null, so this bites the driver-mobile source specifically.

**Claimed failure scenario.** Tenant policy accuracy_threshold_meters = 100 (default). Driver-mobile session for vehicle V reports at 10:00:00 with a wifi/cell fallback fix: accuracy_meters = 800, coordinates 50 km from the true position. Line 306 rejects it `accuracy_below_threshold` (correct), but lines 380-390 still set `vehicle_source_health.last_location` to that 50-km-away point and `last_seen_event_at` to 10:00:00. At 10:01:00 the phone reports a clean GPS fix (accuracy 8 m) at the true location. Lines 311-316 compute ST_Distance = 50,000 m over 60 s = 3000 km/h > 200, so this genuinely good fix is rejected `impossible_movement` and never reaches `app.vehicle_current_positions`. The dispatch board's canonical position stays on the older fix, `app.recalculate_shipment_tracking_health` sees no newer position, and the audit trail records a misleading `impossible_movement` reason for a report that was actually fine. Every low-accuracy fix costs exactly one subsequent good fix, so in urban-canyon conditions the canonical position stalls for extended stretches.

**Proposed fix.** Advance `last_location` only from a candidate that was not rejected for a data-quality reason -- e.g. update `last_location` only when `v_apply` is true, or when `v_reason` is null / in ('switch_suppressed'), while continuing to advance `last_seen_event_at`/`last_seen_received_at` unconditionally (liveness evidence, which is the stated purpose of the unconditional update).

#### Ten unauthenticated forged-signature webhook posts permanently disable a tenant's third-party tracking connection

- **File:** `supabase/migrations/20260730350000_harden_advanced_tms_third_party_hybrid_tracking.sql`:512
- **Symbol:** `app.ingest_third_party_provider_webhook_event`
- **Category:** denial-of-service

**Claim.** `app.ingest_third_party_provider_webhook_event` is SECURITY DEFINER and granted to `anon` (line 634 of the same migration). When `app.verify_third_party_provider_webhook_signature` fails, the function increments `consecutive_failure_count` and, at 10, sets the connection `status = 'disabled'` with `disabled_reason = 'consecutive_failure_threshold_exceeded'` (lines 510-517). The 226I header justifies this by mirroring `app.record_webhook_delivery_attempt` (ADR-0011), but that counter is driven by CargoGrid's own OUTBOUND delivery attempts — a trusted signal about endpoint health. Here the counter is driven by arbitrary INBOUND requests from `anon`, so an unauthenticated party controls the tenant's integration kill switch. The rate limiter (lines 486-495) counts `result = 'invalid'` rows bound to `connection_id OR client_key` and trips at >= 10, i.e. exactly at the threshold — request #10 still executes and performs the disable before request #11 is throttled. Recovery requires an operator to call `app.reenable_third_party_provider_connection` (OPS:Edit).

**Claimed failure scenario.** An attacker learns tenant B's webhook `connection_id` UUID (it is embedded in the callback URL handed to the third-party telematics provider, so it is shared outside the trust boundary and appears in provider dashboards, proxy logs and support tickets). They send 10 unauthenticated POSTs to `/rest/v1/rpc/ingest_third_party_provider_webhook_event` with that connection_id, any JSON body and a garbage `p_signature`. Each fails signature verification and increments the counter; the tenth sets `status='disabled'`. Tenant B's live vehicle telemetry feed stops — `app.lookup_public_shipment_tracking` degrades to `vehicle_position_status='unavailable'` and no further positions are ingested — with no audit_logs entry (226I header item 2 deliberately writes none), so there is nothing in the audit trail pointing at the cause. Repeating 10 requests every 15 minutes keeps it disabled indefinitely.

**Proposed fix.** Do not let an unauthenticated caller drive the auto-disable counter. Either count only signature failures whose payload otherwise passes a cheap structural check AND that arrive from a source the connection has previously succeeded from, or replace the hard auto-disable with an alert/quarantine state that keeps ingestion alive, or require a second signal (e.g. no successful ingest for N minutes) in addition to the failure count before flipping `status='disabled'`.

#### Anon-callable driver-mobile ingestion rate limit is bound only to the caller-controlled client_key, so it is trivially bypassed

- **File:** `supabase/migrations/20260730360000_harden_advanced_tms_device_driver_mobile_tracking.sql`:435
- **Symbol:** `app.ingest_driver_mobile_report`
- **Category:** security

**Claim.** The 10-bad-attempts/15-minute limiter counts only `where client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes'` (lines 433-435). `client_key` is entirely attacker-supplied: app/api/tracking/driver-mobile/route.ts lines 45-46 derive it as `sha256(request.headers.get('x-forwarded-for')?.split(',')[0])` -- the first, externally-writable hop of a request header. Varying that header per request produces a fresh bucket every time, so `v_recent_bad_count` never reaches 10 and the `'rate_limited'` branch is unreachable for any attacker who bothers to rotate it.

This is the identical defect that CG-S10-ATW-027 live-reproduced and fixed one function over: 'the 15-minute/10-attempt rate-limit check in app.ingest_third_party_provider_webhook_event counted only rows matching caller-supplied client_key ... trivially bypassed by varying that header per request (live-reproduced: 30 bad-signature attempts against the same connection, 30 distinct client_keys, never tripped rate_limited)' (20260730350000 lines 127-141), repaired there by widening the count to `(connection_id = p_connection_id or client_key = p_client_key)` (line 489). 20260730360000 is a LATER migration in the same hardening family that fully rewrote `app.ingest_driver_mobile_report` and left the same counting predicate untouched. `app.driver_mobile_ingestion_attempts` (20260729360000 lines 100-106) has no column other than `client_key` to bind to.

**Claimed failure scenario.** An unauthenticated attacker POSTs to /api/tracking/driver-mobile with a random Bearer token and a fresh `X-Forwarded-For: 10.0.0.<n>` per request. Every request takes the line 450-453 'invalid' branch and inserts an attempts row, but because each request lands in its own client_key bucket the count at line 433 is always 0 and 'rate_limited' is never returned. The documented anti-enumeration control described in this function's own migration header ('a client_key accumulating 10+ invalid results within a trailing 15-minute window is rate-limited -- the same real, queryable anti-enumeration mechanism app.tracking_lookup_attempts already implements') is inert: unbounded anon-driven INSERT volume into app.driver_mobile_ingestion_attempts (which has no retention sweep) plus one sha256 + one indexed count per request, with no back-pressure at any layer.

**Proposed fix.** Bind the count to something the caller cannot rotate, as ATW-027 did for the third-party path: add a non-caller-controlled discriminator column to app.driver_mobile_ingestion_attempts (e.g. the sha256 token_hash computed at line 448, or the resolved driver_mobile_tracking_session_id) and widen the predicate to `(token_hash = v_hash or client_key = p_client_key)`; alternatively enforce the limit at the route/edge on a trusted client identity rather than on an X-Forwarded-For-derived key.

### LOW

#### Audit-log read RPCs accept an unbounded limit — no clamp in the zod contract and none in the SQL

- **File:** `server/contracts/audit-trail/audit-trail.ts`:69
- **Symbol:** `QueryAuditLogsInputSchema.limit`
- **Category:** pagination-bypass

**Claim.** `limit: z.number().int().positive().default(50)` has no `.max()`, and `server/queries/audit-trail.ts:57` passes `parsedInput.limit` straight through as `p_limit`. Both consumers of that value — `app.query_audit_logs` (supabase/migrations/20260716113048_create_audit_trail.sql:270, 300) and `app.export_audit_logs` (lines 313, 343) — apply `limit p_limit` with no `least(...)` clamp. I scanned every `p_limit`-taking function in the schema: these are the only two without a server-side cap; every other list RPC (list_customer_inventory_balances, list_wms_*, list_claim_*, get_vehicle_telemetry_history, ...) clamps. docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §7 names audit_logs as one of the relations where keyset pagination is mandatory. Note also that the contract's own default (50) silently overrides `app.export_audit_logs`'s documented bulk default of 500, since the value is always sent explicitly.

**Claimed failure scenario.** A tenant_admin (or Supreme Admin) calls `exportAuditLogs(client, { requesterAuthUserId, tenantId, limit: 100000000 })`. Input validation passes, `p_limit` is forwarded verbatim, and `app.export_audit_logs` runs `select al.* from app.audit_logs ... limit 100000000` — the entire tenant audit history is materialized and serialized through PostgREST in one response, defeating the keyset-pagination bound the architecture requires for this relation. (Currently reachable only through the exported server API; no route wires these functions yet.)

**Proposed fix.** Add `.max(...)` to `QueryAuditLogsInputSchema.limit` (e.g. 200 for query, 500 for export) and add a matching `least(coalesce(p_limit, 50), <cap>)` clamp inside `app.query_audit_logs` / `app.export_audit_logs`, so the bound holds regardless of caller.

#### app.canonical_terms has RLS enabled with zero policies while SELECT is granted to authenticated — the grant is dead and every authenticated read silently returns zero rows

- **File:** `supabase/migrations/20260717112000_create_localization.sql`:602
- **Symbol:** `canonical_terms`
- **Category:** silent-failure

**Claim.** Line 602 runs `alter table app.canonical_terms enable row level security;` and line 613 runs `grant select on app.canonical_terms to authenticated, service_role;` with the stated intent in the comment at lines 610-612: "app.canonical_terms is safe to expose broadly (platform-owned baseline copy, no tenant/PII data) -- authenticated may browse it directly (e.g. a future terminology-editor UI listing available codes to override)". No `create policy` is ever issued for this table, in this migration or any of the other 140. PostgreSQL's default-deny then makes the grant unreachable: an authenticated session sees zero rows, always, with no error. This is the only table in the whole schema with an `authenticated` SELECT grant, RLS enabled, and no policy (`app.report_types` is the mirror case — granted with RLS never enabled at all, harmless only because it has no tenant column). Because the failure is a silent empty result rather than a permission error, a terminology-editor UI built against this grant would render an empty code list and pass its own smoke test, and `app.enforce_terminology_overrides_valid` (line 214) would then reject every override the user typed with `invalid_terminology_overrides` for codes that do exist.

**Claimed failure scenario.** Verified on the scratch DB: as `postgres`, `select count(*) from app.canonical_terms` returns 25. Inside `begin; set local role authenticated; set local request.jwt.claims = '{"sub":"...","role":"authenticated"}';` the same query returns 0 — no error, no permission denial, just an empty set that contradicts the migration's own documented intent.

**Proposed fix.** New migration adding `create policy canonical_terms_select_authenticated on app.canonical_terms for select to authenticated using (true);` — the exact shape already used for the other global, non-tenant-scoped catalogues in this schema (`uoms_select_authenticated`, `master_types_select_authenticated`, `milestone_codes_select_authenticated`, `finance_currencies_select_authenticated`, etc.), all of which were verified to carry no tenant_id/org_unit_id/owner column.

#### get_tenant_tracking_utilization_summary overwrites tracked_vehicle_count with tracked+stale, so the capacity page double-counts stale vehicles

- **File:** `supabase/migrations/20260730120000_create_advanced_tms_capacity_utilization.sql`:512
- **Symbol:** `app.get_tenant_tracking_utilization_summary`
- **Category:** correctness

**Claim.** Lines 498-510 populate `tracked_vehicle_count`, `stale_vehicle_count`, `offline_vehicle_count` and `not_tracked_vehicle_count` as four disjoint FILTER counts over `app.get_tenant_tracking_coverage`. Line 512 then mutates the returned field in place:

  v_result.tracked_vehicle_count := coalesce(v_result.tracked_vehicle_count, 0) + coalesce(v_result.stale_vehicle_count, 0);

Only `tracked_vehicle_limit_remaining` (line 514) needs that combined figure. Because the combination is written back into the output field rather than a local, the composite type has no disjoint 'tracked' count left, while `stale_vehicle_count` is still returned separately -- the four counts no longer partition `total_active_vehicle_count`. The function's own comment states the intended split ('stale counted as tracked for the subscription-limit comparison, distinct in its own right for display', line 538), which the code does not deliver.

**Claimed failure scenario.** A tenant has 10 active vehicles: 3 coverage_status='tracked', 2 'stale', 1 'offline', 4 'not_tracked'. The RPC returns tracked_vehicle_count=5, stale_vehicle_count=2, offline_vehicle_count=1, not_tracked_vehicle_count=4 (sum 12 > 10). app/(tenant)/[tenantSlug]/operations/capacity/page.tsx renders 'Tracked vehicles 5 / 10' (line 76) and, in the adjacent tile, 'Offline / not tracked 1 / 4' with the sub-line '2 stale' (lines 83-85). An operator reads 5 tracked plus 2 stale plus 1 offline plus 4 not-tracked = 12 vehicles from a 10-vehicle fleet, and believes 5 vehicles are reporting fresh positions when only 3 are.

**Proposed fix.** Compute the subscription figure in a local variable instead of mutating the output field: `v_limit_basis := coalesce(tracked,0) + coalesce(stale,0);` then `v_result.tracked_vehicle_limit_remaining := v_package.max_tracked_vehicles - v_limit_basis;`, leaving `v_result.tracked_vehicle_count` as the disjoint fresh-only count the four-way partition and the UI both assume.


---

# Verification outcome (`CG-S10-ATW-032`)

The register above was written before any of it had been checked. It has now been checked
against the ratified design and the live schema, and **the majority of it does not survive**.
Recording that is as important as recording the findings were, because acting on an
unverified register is how a codebase acquires changes it never needed.

## What the design documents settle

Read before verifying: `docs/blueprint/` (six primary sources),
`00-control/02_CONFIRMED_DECISION_REGISTER.md` (CPD-001..023, RPD-001..040, INV-001..012),
and `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` (the authoritative RLS policy-family
assignment).

Several findings are not defects at all once the design is read:

- **`06_RLS_RBAC_WORKSTREAM.md` §4 assigns each table exactly one policy family.** Only
  the `customer_portal_scoped` family — "`shipments`, `invoices`, `tickets`,
  `warehouse_orders` — portal-visible subset" — requires `tenant_id + customer_account_id`.
  `skus` (and therefore `item_masters`) are explicitly listed under
  `standard_tenant_scoped`, whose tenant key IS just `tenant_id`. So "policy X is
  tenant-only" is a defect **only** where the design designates that table
  customer-portal-scoped, and correct behaviour everywhere else. Several of the RLS
  findings above assume the opposite.
- **The customer-portal boundary is Phase 8 (Step 13) scope.** No live `customer_user`
  principal exists yet. `ISS-2026-010` already records this correctly, and Phase 8's own
  prompt defines which subset is portal-visible — deciding that here would be inventing
  the contract that prompt exists to define.
- **`RPD-022`** gives Supreme Admin absolute CRUD including audit and ledger records, so
  any claim of the form "Supreme Admin can bypass X" describes ratified behaviour.
- **`RPD-014`** ratifies dashboards reading transactional data directly.

## Disposition of the critical findings

| Claim | Verdict |
|---|---|
| `publish_milestone_template_version` archives a cross-tenant supersede target | **REAL** — fixed, `ISS-2026-035` |
| `dispatch_shipment_order` records a dispatch without applying the status transition | **REFUTED** — it calls `app.transition_shipment_order(..., 'dispatched', ...)` directly |
| `consume_inventory_reservation` can never consume a fully-reserved balance | **REFUTED** — `post_inventory_movement` enforces `on_hand >= 0`, not `on_hand >= reserved`; `advanced-tms-inventory-ledger.sql` exercises this exact path and passes |
| `allocate_finance_receipt` derives a per-item key without the receipt | **REFUTED** — its batch lookup is already scoped `receipt_id = p_receipt_id` |
| `recalculate_quotation_totals` / `generate_route_planning_candidates` / `next_quotation_number` reachable by any user | **ALREADY FIXED** this session (`20260730460000`) |
| `approve_rate_version` trusts `p_actor_auth_user_id` | **ALREADY FIXED** (`20260730440000`, the `auth.uid()` cross-check) |
| `transition_shipment_order` / `prepare_finance_settlement` idempotency replay | **ALREADY FIXED** (`20260730390000`) |
| `accounts` / `finance_invoices` / `item_masters` / `customer_contracts` owner-scope | **PHASE 8 SCOPE** — see above; tracked by `ISS-2026-010` |

## What this means for the rest of the register

The remaining medium/low entries are **still unverified** and must be treated the same way:
re-derive each from the live schema and the ratified design before acting. On the evidence
so far the false-positive rate is high, and the dominant causes are (a) the claim describes
behaviour a later migration already changed, and (b) the claim assumes a design constraint
the design does not actually impose.

`ISS-2026-034` remains open for exactly that work.

---

# Verification round 2 — the medium/low register (`CG-S10-ATW-032`)

The first outcome section above disposed of the critical band and left the medium/low entries
explicitly unverified. They have now been verified the same way: re-derived from the live
post-migration catalogue (`pg_get_functiondef`, `pg_policy`, `pg_constraint`,
`information_schema`), judged against the ratified design, and repaired only where they
survived. 32 claims were individually checked in this round.

| Disposition | Count |
|---|---|
| CONFIRMED — repaired | 20 |
| ALREADY-FIXED by a later migration | 7 |
| BY-DESIGN — ratified, quoted | 5 |

## Confirmed and repaired

| Claim | Landed in |
|---|---|
| `reserve_inventory` replay ignores the reserved balance and quantity | `20260730530000` |
| `post_inventory_movement` never checks `reserved + held` (raw 23514) | `20260730530000` |
| Serial `on_hand <= 1` reads one arbitrary row instead of summing | `20260730530000` |
| `cancel_shipment_order` admits out-of-matrix edges (closed → cancelled) | `20260730530000` |
| Job-order allocation basis written and read by disagreeing rules | `20260730530000` |
| Tenant-wide Fleet Control Tower queues skip `can_access_record` | `20260730530000` |
| Geofence/deviation evaluator resolves one leg per vehicle, no tiebreak | `20260730530000` |
| Direct-device telemetry has no replay dedup | `20260730530000` |
| `complete_epod_capture` missing the family's row lock | `20260730530000` |
| `transition_shipment_order` commits history without applying the status | `20260730520000` |
| 74 version-predicated UPDATEs silently no-op and fabricate a `success` audit row | `20260730520000` |
| `ingest_milestone_event`'s idempotency guard is swallowed by its own handler | `20260730520000` |
| FinanceJournal contract omits the `correction` source_type | contract |
| `IMPORT_EXPORT_JOB_TYPES` drift (`print_label`, `route_load_planning`) | contract |
| Audit-log read RPCs accept an unbounded limit | contract + `20260730550000` |
| `listTenantUsers` does `select("*")` on a column-restricted table | query layer |
| Invoice/vendor-bill discard permanently wedges the source handoff | `20260730540000` |
| Settlement stuck in `executed` after a competing settlement consumed its AP item | `20260730540000` |
| Reconciliation compares two different as-of bases; `p_company_id` never filtered | `20260730540000` |
| Fixed-amount tax rules applied without checking the rule's own currency | `20260730540000` |
| Numbering republish wedges allocation permanently | `20260730550000` |
| `set_custom_field_values` retry destroys newer values | `20260730550000` |
| Driver-mobile rate limit bound only to the caller-controlled `client_key` | `20260730550000` |

## Already fixed before this round

`resolve_config` cross-tenant read (`20260730460000`); `enqueue_job` idempotency spanning job
types, `add_actual_cost_component` replay (`20260730390000`); ePOD and actual-cost
`record_version` checks (`20260730480000`); rejected telemetry advancing
`vehicle_source_health.last_location` (`20260730430000`).

## By design — with the ratified text that settles it

- **`generate_wms_pick_task` auto-select ignoring available stock.** `20260730240000` design
  note 10 ratifies auto-selecting the first FIFO/FEFO candidate; note 11 enumerates what is
  re-verified and quantity is deliberately not among it. Skipping a small oldest lot for a
  large newer one is what FEFO exists to prevent, and the path is not wedged.
- **19 WMS policies admitting a `customer_user` actor.** `20260730311000`'s own closing
  paragraph scopes that migration to the four live-implicated tables and hands the rest to
  `ISS-2026-010`/Phase 8.
- **As-of aging using current `open_amount`.** `20260729240000`'s header discloses this in the
  same words and explicitly refuses the point-in-time reading the claim assumes.
- **Ten forged-signature webhook posts disabling a connection.** `20260730110000`'s header
  names forged-signature probing as the condition it was written to respond to, and ships
  `reenable_third_party_provider_connection` as the recovery path.
- **MFA/step-up as a caller-supplied timestamp.** Ratified in five places as the disclosed
  no-live-MFA-provider boundary; the claim's distinguishing premise (that the service_role
  sibling has a trusted attester) is also false — it passes the value through unmodified too.

## What this register is worth, on the evidence

Across both rounds the finder phase produced real defects at a meaningful rate — 20 confirmed
in this round alone, including two against this audit's own predecessors that nothing else
would have caught. It also produced a large majority of claims that did not survive contact
with the live schema or the design documents. Both halves are the lesson: an unverified
register is worth keeping and worth verifying, and is never worth fixing from directly.
