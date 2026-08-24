# CargoGrid Recurring Defect Taxonomy

**Owner:** Runtime build agent
**Established by:** `ADR-0021` (batched review-and-fix execution cadence)
**Status:** Active — mandatory per-prompt self-check (Tier B, `docs/standards/BUILD_EXECUTION_PROTOCOL.md` §4)
**Version:** `1.2.0` (2026-08-07)

## 1. Why this document exists

Between Prompt 220 and Prompt 256 this repository's adversarial reviews found and closed
**more than 90 independently-verified real defects**. They are not 90 different mistakes.
Read against each other, they collapse into **20 recurring classes** (as of Prompt 256; batch
`CG-S11-PRC-008..010`'s own Tier C review added two more, C-21 and C-22; batch `CG-S11-PRC-011`
(Prompt 260)'s own Tier C review added one further class, C-23 — see §4), and a small
number of those classes account for every Critical and High finding Phase 6 has produced so far.

Two facts make this actionable:

1. **The classes repeat across capabilities that share no code.** Prompt 256 reintroduced the
   exact `auth.uid()`-versus-actor-parameter defect Prompt 255 had already found and fixed
   (`docs/build-log/phase-06/PRC-256.md`, `docs/build-log/phase-06/PRC-255.md`). Prompts 252,
   253 and 254 each independently reintroduced the same idempotency-comparison defect class
   that `CG-S10-ATW-030` had already swept across 20 functions.
2. **The classes are cheap to check for and expensive to find by review.** Every one below has
   a mechanical question attached. Answering the question against a diff takes minutes. Finding
   the same defect by adversarial review takes a live database, forged sessions, and concurrent
   `psql` processes — which is exactly why full review is now batched (`ADR-0021`).

**This checklist is the compensating control that makes batching review safe.** It is not
advice. Running it against your own diff before declaring a prompt `COMPLETED` is a mandatory
Tier B gate. A prompt that skips it is not complete regardless of what the automated gates say.

## 2. How to use it

At the end of every prompt, before writing the build log:

1. Take your own diff (`git diff`, plus every new file).
2. Walk §4 in order. For each class, answer its **Check** question against the diff, not
   against memory of what you intended.
3. Any class you cannot answer `N/A — this diff contains no such construct` or
   `verified clean, here is where` is a finding. Fix it now, inside the prompt.
4. Record in the prompt's build log which classes applied and how each was cleared. A build log
   that does not name this document has not run the gate.

Do not treat a clean walk as proof of correctness. It proves you did not repeat this
repository's own known mistakes. Novel defects are what the batch review in
`docs/standards/BUILD_EXECUTION_PROTOCOL.md` §5 exists to find.

## 3. Class-to-lens map

The batch review's four lenses each own a subset. If a class is cleared at Tier B, the owning
lens still re-checks it — Tier B reduces the load, it does not replace the lens.

| Lens | Owns classes |
|---|---|
| Spec-compliance | 15, 18, 20, 23 |
| Security / RLS / tenant isolation | 5, 6, 7, 8, 10, 11, 12, 13, 17, 24 |
| Correctness / concurrency | 1, 2, 3, 4, 9, 14, 19, 21 |
| Cross-prompt integration and data dependency (new at `ADR-0021`) | 7, 8, 16, 19, 20, 22, 24 |

## 4. The classes

### Concurrency and idempotency

**C-01 — Idempotency replay matched the key but never verified the target.**
The short-circuit found a row by `(tenant_id, idempotency_key)` and returned it without
checking it describes the operation actually requested. Damage comes in two shapes: silent
misattribution (you get someone else's row) and silent no-op (your operation is skipped while
the call reports success). `p_idempotency_key` is user-supplied free text in this product, so
key reuse is an ordinary operator typo, not an attack.
*Evidence:* `CG-S10-ATW-030` F-1 (High) — 29 short-circuits across 20 WMS functions;
`app.generate_wms_pick_task` deterministically returned a **different** outbound order line's
task, with zero concurrency required. Fixed in
`supabase/migrations/20260730380000_harden_advanced_tms_wms_idempotency_target_mismatch.sql`.
`ISS-2026-029` carried the same class into ~27 Finance/Operations/Platform functions — sharpest
case: `apply_finance_ar_allocation` and `reverse_finance_ar_allocation` write the same table
under the same unique key, so reusing a key to **reverse** an allocation silently did nothing
and returned success. Reintroduced independently at Prompts 252, 253 (`issue_date`/`expiry_date`
omitted from an expiry-tracking capability's own comparison) and 254.
**Check:** does every replay short-circuit compare the *complete* target tuple — every field
that identifies what the caller asked for, including dates and amounts — or only the key?

**C-02 — Idempotency guard raised inside a block that traps its own exception.**
`raise exception ... using errcode = 'unique_violation'` placed inside a block whose own
`exception when unique_violation` handler catches it is inert. It reads as a guard and does
nothing.
*Evidence:* `CG-S10-ATW-032` swept all 55 guards added by `ATW-030`/`ATW-031`; parsing block
nesting rather than grepping, because a `raise exception` line contains the word `exception` and
a naive scan mistakes it for a handler section — which is precisely what hid it.
`ingest_milestone_event`'s guard was genuinely dead, so a `DELIVERED` submission reusing an
earlier key returned that earlier event with no error and the delivery was silently discarded.
**Check:** for each guard, trace the enclosing block structure. Would its own handler swallow it?

**C-03 — Optimistic-version predicate written on the UPDATE but never checked.**
`where record_version = p_expected_version` on the UPDATE, with no check that a row was
actually updated. The concurrent loser falls through with an unset composite, writes a
fabricated `success` audit row with a NULL `tenant_id`, and returns an all-NULL record the
TypeScript guard does not catch. Any transition-history row written earlier in the same
transaction commits describing a change that never took effect.
*Evidence:* `CG-S10-ATW-032` — **74 functions**. Named as a residual in
`supabase/migrations/20260730480000_harden_optimistic_concurrency_row_lock.sql`'s own header
and closed by `supabase/migrations/20260730520000_harden_stale_version_no_op_and_swallowed_idempotency_guard.sql`.
Reintroduced at Prompt 251 (`revoke_vendor_intake_token`, the one function in that migration
missing the check) and Prompt 252 (a blind, version-unguarded archive on template publish).
**Check:** is every versioned UPDATE immediately followed by an explicit applied-check that
raises on a lost race?

**C-04 — A decision was made on a parent/state row that was read without a lock.**
The single most frequent Critical/High class in Phase 6. Read the parent's status, decide,
then act — while a concurrent session changes that status in between.
*Evidence, all live-reproduced:* Prompt 251 **CRITICAL** —
`redeem_vendor_intake_token_and_submit` had no lock, so two concurrent redemptions of one
single-use invitation (double-click, slow-network retry, two tabs) created **two vendor
profiles**. Prompt 251 HIGH — child records still addable after the profile left `draft`.
Prompt 252 HIGH — a corrective action attachable to an already-`closed` assessment. Prompt 253
HIGH — a stale-overwrite race in compliance-status recalculation, reproduced with three
concurrent `psql` sessions, permanently stranding a verified document at `pending_verification`
with nothing to self-heal it. Prompt 254 — the advisory lock meant to serialize a supersede
race computed its key from the wrong row, dead code for the exact race it existed to close.
Prompt 255 HIGH — `create_rate_version`'s supersede path had no lock or version guard.
Prompt 256 HIGH — `shortlist_sourcing_candidate` and `evaluate_sourcing_candidate_eligibility`
both read the parent request status unlocked.
**Check:** every row whose value gates a decision is either locked `for update` before the read,
or the decision is re-validated under lock before the write. **And:** when a fix adds a second
lock, state the lock order explicitly in the function comment — Prompt 256 fixed two functions
in one pass and had to pin candidate-row-before-parent-row so the two fixes could not deadlock
against each other.

**C-09 — Exception handler catches an SQLSTATE class instead of its intended constraint.**
`exception when unique_violation` catches *every* unique violation in the block, including ones
the handler's recovery logic is wrong for.
*Evidence:* Prompt 255 **CRITICAL** — the import commit's handler caught any `unique_violation`,
silently dropping a rate on a genuine `vendor_code` race while reporting the import job fully
successful, with no recoverable retry path.
**Check:** does the handler discriminate on the constraint name before recovering, or does it
assume there is only one way to violate uniqueness here?

**C-19 — Supersede or uniqueness validated on a narrower scope tuple than the real one.**
*Evidence:* Prompt 254 — a bank-account supersede validated vendor + purpose but not
vendor + purpose + **currency**, the real active-scope tuple. Live-reproduced: two legitimately
privileged, non-colluding actors silently deactivated an unrelated active different-currency
account as a side effect of an unrelated approval.
**Check:** write out the tuple that actually defines "one active record of this kind" and
compare it against what the code matches on.

**C-21 — Sibling functions take locks on the same two tables in inconsistent order.**
Function A locks parent-then-child; function B (often documented as the reason A should lock
child-then-parent, or vice versa) locks child-then-parent. Each function is individually
correct — every lock it takes is the lock it needs — but the two together are a live deadlock
the moment they run concurrently against overlapping rows. This is distinct from C-04 (a
decision made on an unlocked row): every function here DOES lock what it reads: the defect is
the *order*, not the absence, of the lock.
*Evidence:* Batch `CG-S11-PRC-008..010` (Prompts 257-259) Tier C, **HIGH**, live-reproduced —
`app.close_rfq_for_comparison` locked `app.rfqs` first, then implicitly locked
`app.rfq_invitations` rows second via an unlocked bulk `UPDATE`; `app.submit_rfq_response` and
`app.decline_rfq_invitation` (the same migration's own "design note 8: child locked before
parent") lock invitation-then-rfq — the exact inverse order. Two real, concurrent `psql`
sessions taking each function's own documented lock sequence against the same RFQ's two
different rows produced a genuine Postgres `deadlock detected` (SQLSTATE `40P01`). Fixed in
`supabase/migrations/20260730670000_harden_procurement_batch_257_259_review_fixes.sql` by
making `close_rfq_for_comparison` lock every still-`invited` invitation row before locking the
parent `rfqs` row, matching the order its own sibling functions already used.
**Check:** for every pair of functions in one migration (or one capability) that both lock two
of the same tables, write out each function's own lock order. If a fix adds a second lock (the
C-04 checklist item), does its order match every *other* function in this migration that
already locks the same two tables — not just avoid deadlocking against itself?

### Authorization, isolation, and disclosure

**C-05 — Permission check ordered after a read that already discloses data.**
The check is present and correct, but a row was read, or an error message shaped, before it ran.
That is an information-leak oracle available to unauthorized and cross-tenant callers, and the
probe typically leaves no audit trail.
*Evidence:* Prompt 254 — the evidence-access RPCs let any authenticated user of **any** tenant
learn whether a specific record has attached evidence. Prompt 256 HIGH —
`shortlist_sourcing_candidate` disclosed the parent request's real status and the candidate's
eligibility bit to a zero-permission, fully cross-tenant caller before the permission check ran.
**Check:** is `evaluate_permission` (or its equivalent) the first statement in the function that
can observe or leak row data? Do failure paths differ observably by whether the row exists?

**C-06 — Session-implicit `auth.uid()` reached from an RPC that takes an explicit actor.**
The RPC validates `p_actor_auth_user_id` correctly, then reads through a view or policy whose
own row filter and column masks resolve the actor from `auth.uid()`. For any caller without a
real browser JWT session — a service-role call, a job context, a db-test — the RPC returns
all-null or empty rows for a legitimately authorized actor.
*Evidence:* Prompt 255 established the fix pattern at `search_vendor_rates`. Prompt 256 hit it
again anyway, in three read RPCs, caught by the implement agent's own live `db:test` iteration.
**Check:** does any read path in this diff reach a view, policy, or helper that resolves the
actor implicitly? If yes, reconstruct the masked projection against the base table with the
validated actor parameter passed through explicitly.

**C-07 — A `jsonb` snapshot column carries the unmasked source row.**
The typed columns are masked correctly and the `jsonb` sibling beside them carries the same
values verbatim, with zero field-level protection — and, because snapshots are usually built
with `to_jsonb(source_row)`, it carries fields the capability's own RLS never replicates.
*Evidence:* Prompt 256 **CRITICAL** — `demand_snapshot` leaked `budget_amount` around the typed
column's own `PRC:View cost` mask (readable as `demand_snapshot->>'budget_amount'` by an actor
who simultaneously saw `cost_masked=true`), and leaked real `consignee_snapshot` /
`notify_party_snapshot` customer PII governed on the source row by record-scoped access — traced
all the way to the browser's RSC/flight payload through server-to-client prop passing.
**Check:** every `jsonb` snapshot has an explicit key allowlist at write time and the *same*
mask as its typed sibling at read time. Never `to_jsonb(whole_row)`.

**C-08 — Widening an existing function exposes new data to its existing callers.**
A function that already had permission holders gains a field, and every existing holder can now
see it — including holders with none of the new field's own gating permission.
*Evidence:* Prompt 255 HIGH — `select_vendor_rate` (a pre-existing, already-`VERIFIED` COM-149
function) leaked PRC-gated tier cost data to any plain `COM:View cost` holder with zero PRC
permissions. No forged credentials required; reproduced with an ordinary own-identity session.
**Check:** for each field added to an existing function or view, enumerate every permission that
can already reach that function and confirm each is entitled to the new field.

**C-10 — File or evidence linked without re-validating tenant, record scope, and scan status.**
*Evidence:* Prompt 252 HIGH — a different tenant's file, and a file with
`malware_scan_status='infected'`, both attachable as assessment evidence, live-reproduced both
ways. Fixed by mirroring `app.record_gps_device_installation`'s established re-validation.
**Check:** every RPC that accepts a file id re-validates it against `app.files` for tenant,
record scope, and scan status — at the accepting RPC, not upstream.

**C-11 — Grants: absent where RLS exists, or blanket where they should be deliberate.**
Two opposite failures with the same root cause — grants treated as boilerplate.
*Evidence:* Prompt 253 — RLS policies present on all four new tables, no `grant select` on any
of them, so `authenticated` got `permission denied` on every read. `CG-S10-ATW-032` — a blanket
`grant ... to authenticated, service_role` inside a 74-function mechanical sweep would have
turned `app.transition_gps_device_status`, deliberately un-granted, into a public API; a
standing db-test assertion caught it. `CREATE OR REPLACE` preserves an existing ACL, so the
grant block was removed entirely rather than "restored."
**Check:** is every new table's grant explicit and every function's grant deliberate? Does any
sweep in this diff contain a blanket grant?

**C-12 — `SECURITY DEFINER` granted to `authenticated` with no authority check.**
*Evidence:* `ISS-2026-033` — 91 such functions, 30 of them writes. Four spot-verified against the
live schema as real cross-tenant read **and** write paths, including
`app.recalculate_quotation_totals` (rewrites any tenant's quotation money columns).
**Check:** every new `SECURITY DEFINER` function granted to `authenticated` either gates on
`app.evaluate_permission`, or authenticates by token/signature, or delegates to a checked
callee — and the build log says which.

**C-13 — Asking "is the claimed actor allowed?" instead of "is the caller that actor?"**
*Evidence:* `ISS-2026-032` — 33 actionable functions. Each already validated authority; none
validated identity. `app.approve_rate_version` gated on
`is_support_grant_authority(p_actor_auth_user_id, ...)`, so any session that knew a
tenant_admin's UUID could approve a vendor rate **as them**. Closed by wiring
`app.assert_actor_is_session_identity` into the single `evaluate_permission` choke point.
**Check:** does the authority path assert caller-is-actor, or does it trust the parameter?

**C-17 — `select("*")` against a column-restricted table.**
*Evidence:* `CG-S10-ATW-030` F-4; `listTenantUsers` corrected to read the granted 17 columns of
`app.users` merged with `app.users_directory`'s masked address.
**Check:** no `select("*")` and no `select *` anywhere a column-level `GRANT` or mask applies.

### Correctness, constraints, and completeness

**C-14 — Postgres identifier over 63 characters, silently truncated.**
*Evidence:* Prompt 253 — a 66-character index name was silently truncated past the limit,
breaking an exception-recovery branch that referenced the intended name.
**Check:** every new index, constraint, and trigger name is ≤ 63 characters.

**C-15 — Missing domain constraints: non-negativity, closed enums, totals.**
*Evidence:* Prompt 256 — no non-negativity `CHECK` on cargo weight/volume; a negative value was
accepted through both direct creation and the override RPC's "null-to-value always widens"
carve-out. Prompt 252 HIGH — the scorer hardcoded a 100-point denominator while
`weight_total_required` was accepted at any value: a 150/150 template crashed the scorer
outright, and a 60-point template made its own `pass_threshold` mathematically unreachable.
**Check:** for every numeric column, what is its legal range, and is that range a `CHECK`? For
every formula, what does it assume about its inputs, and is that assumption constrained?

**C-16 — A `"use server"` module exports something that is not a function.**
A Next.js hard constraint. Breaks `next build` outright, and nothing earlier in the gate chain
catches it.
*Evidence:* Prompt 253 — a new server-actions file re-exported a plain object constant. The
export had zero consumers; it broke the build on the very route the fix was meant to add, and
was found only by the orchestrating session's own independent `next build`.
**Check:** every export from a `"use server"` file is an async function. Run `next build` — this
class is invisible to `typecheck` and `lint`.

**C-18 — Maker-checker or MFA enforced on the happy path only.**
The approve path is guarded; `hold`, `reactivate`, `deactivate`, `reject`, `cancel` are not.
*Evidence:* Prompt 254 HIGH — `hold`/`reactivate`/`deactivate` bypassed maker-checker **and**
MFA entirely: a single actor could place a fraud-investigation hold and immediately lift it
alone. `ISS-2026-038` — self-approval not blocked on rate creation/approval.
**Check:** enumerate every state transition the capability defines, not just the primary one,
and confirm each carries the control its risk warrants. Is self-approval blocked on all of them?

**C-20 — A capability with no caller: built, tested, and unreachable.**
The flag exists, the RPC exists, the unit tests pass, and no route in the application ever calls
it — or the reviewers a workflow depends on have no surface to review from.
*Evidence:* Prompt 251 HIGH — a self-registration feature was flagged, implemented and
unit-tested, with no public page ever calling it; closed with a real registration page, not a
disclosure. Prompt 253 HIGH — no document or version viewer existed anywhere, leaving compliance
reviewers to verify pending evidence completely blind. Prompt 255 — the import adapter has no UI
caller anywhere (disclosed, not fixed).
**Check:** trace at least one real path from a route to every capability this prompt adds. If
there is none, either build it or disclose it explicitly in the build log — never leave it
silently unreachable.

**C-22 — A numeric threshold or limit compared without normalizing the value's own unit.**
A `min_value_amount`/threshold/limit column has no currency (or other unit) dimension, and the
comparison function that evaluates it takes a bare `p_value_amount numeric` with no accompanying
unit parameter — so two amounts that differ by orders of magnitude in real-world value, because
they are denominated in different currencies, produce the identical threshold-crossing decision.
Distinct from C-15 (a missing range constraint on one column): the column itself is perfectly
well-formed, and distinct from C-19 (a narrower *scope* tuple): the value being compared is
correct, but the comparison silently assumes every caller's amount is already in the same unit
as the policy's own amount, with nothing in the schema or the function signature enforcing or
even recording that assumption.
*Evidence:* Batch `CG-S11-PRC-008..010` (Prompt 259) Tier C, **HIGH**, live-confirmed —
`app.procurement_approval_policies.min_value_amount` carries no `currency` column, and
`app.evaluate_procurement_approval_requirement(p_entity_type, p_tenant_id, p_value_amount,
p_actor_auth_user_id)` compares `p_value_amount >= v_policy.min_value_amount` directly, with no
currency parameter at all. A published `rate_version` policy with `min_value_amount=5000`
returned identical `required=true` for both a 6000 **USD** rate and a 6000 **IDR** rate —
roughly a 15,000x real-value difference in this repository's own supported currency pair. This
governs two genuinely multi-currency entity types the same batch produces (`rate_version` via
`app.vendor_rate_versions.base_amount`, `vendor_selection` via
`app.vendor_comparison_offers.normalized_amount`). Disclosed as `ISS-2026-045` rather than fixed
— the correct model (per-currency policy rows vs. a single reference currency with
FIN-194-composed conversion) is a genuine architectural decision the fix pass had no mandate to
make unilaterally.
**Check:** for every column that stores a monetary/quantity threshold, does its own table (or
the function that evaluates it) carry the unit the threshold is denominated in? If the value
being compared against it can arrive in more than one unit, is that unit thread through the
comparison, or silently assumed?

**C-23 — A named spec requirement is silently dropped instead of joining the checkpoint's own
disclosed-scope-boundary list.**
Distinct from C-20 (a capability that IS built but has no caller): here the capability is never
built at all. The tell is not that something is missing — plenty of real, legitimate scope
decisions are — it is that the SAME checkpoint's own build log or migration header discloses
several other omissions in meticulous, itemized detail (naming the exact spec section, the
exact reason, and the exact precedent it does or doesn't follow) while this specific one is
simply absent, with no reasoning trail at all. A reviewer (or a future capability) cannot tell
the difference between "considered and deliberately deferred" and "never noticed," which is
exactly the ambiguity the rest of this repository's disclosure discipline exists to remove.
*Evidence:* Batch `CG-S11-PRC-011` (Prompt 260) Tier C, **MEDIUM** (two instances) — Prompt 260
§14 (API impact) names `close` as a required domain operation, distinct from `cancel-eligible`;
zero trace of it exists anywhere in the migration, and `purchase_orders_status_check` has no
`closed` value. §22 (Alternative flow) names four items; only two are implemented, and neither
of the missing two ("schedule line", "vendor-requested revision before approval") appears
anywhere. Meanwhile the SAME checkpoint's own `docs/build-log/phase-06/PRC-260.md` §9
("Residual, disclosed limitations") itemizes eight OTHER scope boundaries in exactly this
itemized, precedent-citing style (no per-line pricing, no external vendor-facing acknowledgement
surface, no REST/GraphQL, fulfillment-tracking-is-descriptive-not-a-match-engine, and four more)
— proving the checkpoint's own author both knew how to disclose an omission and did so
repeatedly, just not for these three. A repository-internal precedent for the missing `close`
operation already existed one capability earlier (`app.close_rfq_for_comparison`, PRC-257),
making the omission easier to miss precisely because the shape looked so familiar.
**Check:** for every named operation, entity, or alternative-flow item in this prompt's own
source spec sections (API impact, alternative flow, business rules), can you point to either (a)
the code that implements it, or (b) the exact sentence in this checkpoint's own build log that
discloses it as deliberately out of scope, with a reason? If neither exists, this is a finding —
not "the spec is aspirational," and not something a future checkpoint can be trusted to notice
on its own, since the checkpoint's own document is the one place a reader would look first.

**C-24 — A money or free-text-reason value reaches `app.audit_logs` unmasked via
`capture_audit_event`'s `p_reason`/`after_value` parameters.**
`app.redact_audit_payload()` only key-name-pattern-redacts `before_value`/`after_value` (and
never touches `reason` at all) — so a caller that builds its own small `jsonb_build_object(...)`
with a field named `amount`/`principal_amount`/`net_pay_total` (never matching the shared
redactor's `secret|password|token|key|authorization|cookie|ssn|npwp|bank|account_number|
salary|payroll` pattern), or that routes a `p_decided_reason`/`p_cancel_reason`/
`p_resolution_note` parameter straight into `p_reason`, persists it in the clear. Distinct from
C-07 (a persisted `jsonb` *snapshot column*, masked at the write site with an explicit
allowlist) — this is the *audit-capture call site itself* carrying an unmasked value into a
table gated far more broadly than the capability's own read surface: `app.query_audit_logs`
grants any tenant's own **plain `tenant_admin`** (a routine, common administrative layer present
in essentially every tenant), which is a materially broader bar than a compensation-shaped
capability's own `HRS:View payroll`-class gate.
*Evidence:* HRT-280 (Prompt 280) — `app.leave_request_audit_projection` built specifically to
close this shape for leave. HRT-281 (Prompt 281) Tier C — recurred: `to_jsonb(v_summary)` (2
sites) plus 8 further `capture_audit_event` call sites routed unmasked `decided_reason`/
`cancel_reason`/`last_reopen_reason` into the audit trail; fixed with a new masked
`app.timesheet_period_summary_audit_projection`. HRT-282 (Prompt 282) Tier C **CRITICAL** —
recurred a third time, one checkpoint later on the same branch, and worse: live-reproduced a
bare tenant_admin (zero `HRS` role, correctly denied on every raw table and read RPC) reading a
real reimbursement `amount`+`employee_id`, a real loan `principal_amount`+`employee_id`, and
real free-text decision/finalize/cancel reason text straight out of `app.query_audit_logs` —
across 13 call sites in 12 functions.
**Check:** for every `capture_audit_event(...)` call in the diff, is `p_reason` ever a raw
`p_*_reason`/`p_*_note` parameter, and does the `after_value` `jsonb_build_object(...)` ever
name a money-shaped or otherwise sensitive key? If either is true, either mask it explicitly (an
allowlist projection, never `to_jsonb(whole_row)`) or pass `null` — and confirm who can actually
read `app.query_audit_logs` for this tenant (usually broader than the capability's own read
gate, since it is `is_support_grant_authority` = Supreme Admin OR any active `tenant_admin`, not
the capability's own permission).

**C-25 — Two independently-built enforcement mechanisms for the same conceptual control, neither
aware of the other.**
A capability ships its own narrow, domain-native control (e.g. a boolean flag plus a dedicated
RPC), and a later, separate capability ships a generic, cross-domain primitive meant to cover
every domain's version of the same concept (e.g. a polymorphic hold/lock/override table). Nothing
bridges them: a control applied through one mechanism is invisible to the other's own enforcement
and classification logic, in both directions. Distinct from C-08 (a function widened to leak a
field to its existing callers) and C-11 (a grant treated as boilerplate) — here both mechanisms
are individually correct and fully tested on their own; the gap only exists in the seam between
them, which neither capability's own test suite exercises because neither was written aware the
other existed.
*Evidence:* `HDN-377` (Storage and Signed URL Audit) **CRITICAL**, live-forced both directions —
PLT-128's own file-native `app.files.legal_hold` + `app.set_file_legal_hold()` (consulted only by
`app.request_file_deletion()`) and IAE-031's later, generic `app.legal_holds` +
`app.request_legal_hold()`/`app._is_under_legal_hold()` (meant to cover every domain's own hold
needs, `app.files` included) never composed: a hold placed via the generic RPC left
`app.files.legal_hold` false and `app.request_file_deletion()` still soft-deleted the file; a
file-native hold was simultaneously invisible to `app.request_retention_archive()`'s own dry-run
classification (`legal_hold_blocking=false`). Fixed by extending `app._is_under_legal_hold()`
with an explicit `app.files`-scoped OR-branch and having `app.request_file_deletion()` consult it
too, closing both directions from the one seam.
**Check:** when a new generic/cross-domain primitive is introduced specifically to replace or
unify N domains' own narrower, pre-existing mechanisms for the same concept, does the diff
actually wire each existing domain's own mechanism into it (or vice versa), or does it merely
add a new, parallel path that domain never calls and is never called by? Live-force both
directions: apply the control through mechanism A, verify mechanism B's own enforcement/read
path sees it, and the reverse.

**C-26 — An RPC-level check has no schema-level backstop against the same mutation issued
directly.**
The correct guard exists and is correctly placed at the one RPC every legitimate caller is
expected to use — but nothing at the table itself (a `CHECK` constraint, a `BEFORE
UPDATE`/`DELETE` trigger) enforces the same invariant, so any other `SECURITY DEFINER` function,
future job, ad hoc migration, or a compromised/misused `service_role` credential that issues the
same mutation directly bypasses it completely. Distinct from C-12 (a function with no authority
check at all) — here the *intended* path is correctly gated; the defect is that it is not the
*only* path capable of performing the mutation. Related to the standing, still-open, larger
`HDN-BLK-018`/`ISS-2026-205` finding (only 13 of ~90+ append-only/audit/ledger-shaped tables
carry a real guard trigger at all) — this class names the narrower, single-invariant version of
the same root gap: a specific field-level rule (not "this whole table is append-only") enforced
by exactly one RPC and nowhere else.
*Evidence:* `HDN-377` (Storage and Signed URL Audit) **HIGH**, live-forced — `app.files.legal_hold`
was checked only inside `app.request_file_deletion()`; a raw `delete from app.files where
id = ...` issued directly (no RLS bypass required, ordinary `service_role` grant) physically
erased a legally-held row with zero error, `app.files` carrying no `BEFORE DELETE` trigger at
all. Fixed with a narrowly-scoped guard trigger mirroring
`app.protect_transaction_lineage_edges_append_only`'s own proven RPD-022 supreme-admin-bypass
shape — firing only on `DELETE` of a `legal_hold=true` row, leaving every other UPDATE path
(scan-status transitions, versioning supersede, soft-deletion) untouched.
**Check:** for every `raise exception` guard inside an RPC that protects a specific row-level
invariant (not merely "does the caller have permission"), is the identical invariant also
reachable by a direct table mutation issued by any role the RPC's own callers already hold (most
often `service_role`)? If yes, and the guard is cheap to express as a trigger without widening
what the RPC itself already allows, add the schema-level backstop; if not, disclose the gap
explicitly rather than leaving the RPC's own check looking like the only line of defense it is
not.

**C-27 — An RPC's `RETURNING`/return-value clause carries a column that a table-level column
grant deliberately excludes.**
A column-privilege fix correctly revokes table-level `SELECT` on a sensitive column and re-grants
an explicit column list omitting it — but an RPC's own `RETURNING * INTO v_row; RETURN v_row;`
(or an equivalent `SELECT *`-shaped composite return) is not a `SELECT` against the table and is
therefore not subject to column-level ACLs at all: any caller with `EXECUTE` on the function gets
the excluded column back anyway, in the function's own response. Distinct from C-17 (`select("*")`
on the *client/TypeScript* side against a column-restricted table, which correctly fails closed) —
here the failure is silent and the opposite direction: the column-privilege fix looks complete
(direct `SELECT` genuinely denied) while a same-checkpoint or pre-existing RPC quietly hands the
value back through its own return type instead.
*Evidence:* `HDN-378` (Security Hardening) Tier C **CRITICAL**, live-forced — `ISS-2026-232`'s own
column-privilege fix revoked `authenticated`'s table-level `SELECT` on `token_hash` across 3
tables, but each table's own "revoke" RPC (`app.revoke_shipment_tracking_token`,
`app.revoke_driver_mobile_session`, `app.revoke_vendor_intake_token`) returned the full composite
row type including `token_hash` verbatim, defeating the fix for all 3 tables in the same
checkpoint that shipped it. Fixed by explicitly nulling the excluded column on the returned
composite immediately before `RETURN`, preserving the return type so no caller-side contract
change was needed.
**Check:** for every table that gains a column-level grant restriction, does any `SECURITY
DEFINER` function that reads or writes that table ever return the whole row (`RETURNING *`, `SELECT
*` into a composite, or an explicit `RETURNS table (...)`/`RETURNS <table>` that mirrors every
column)? If yes, either narrow the return shape to an explicit column list, or mask the excluded
column's value on the returned composite before it leaves the function — a table-level grant
alone never protects an RPC's own return value.

**C-28 — A specialized wrapper's extra protections are bypassed because the generic primitive it
delegates to remains independently callable with only its own, weaker check.**
A high-risk sub-case (e.g. one connection type, one document type, one workflow branch) gets its
own dedicated wrapper function layering extra protections on top of a shared, generic primitive —
a lockout guard, step-up-MFA, an IP-restriction check, an additional approval step. The generic
primitive underneath is never revisited: it keeps its own original, broader `EXECUTE` grant and
its own original, narrower authority check, so any caller who satisfies the generic check alone
can call it directly and achieve the same effect as the wrapper, skipping every protection the
wrapper was built to add. Distinct from C-25 (two independently-built mechanisms for the *same*
conceptual control, neither aware of the other, added in parallel) — here there is only one
underlying mechanism and one, later, intentionally-layered wrapper around it; the defect is that
layering a wrapper on top never closes the direct path to what it wraps. Also distinct from C-26
(an RPC check with no schema-level backstop) — here the direct path is itself another RPC with its
own real, working, but weaker check, not a raw table mutation.
*Evidence:* `HDN-378` (Security Hardening) Tier C **CRITICAL**, live-forced — `ISS-2026-150`'s own
IP-restriction fix, IAE-026's lockout guard, and `CG-S14-IAE-039`'s step-up-MFA were all layered
onto `app.activate_enterprise_idp_connection`, a wrapper around the generic, shared
`app.set_integration_connection_status` (created at Prompt 336, long before any of the three
layers existed). `set_integration_connection_status` kept its own original `INTHUB:Configure`-only
check and its own `authenticated` grant; calling it directly, as an actor holding `INTHUB:Configure`
but none of the wrapper's own extra requirements, reactivated a live enterprise SSO connection
with zero verified test login, zero step-up challenge, and zero client IP — defeating all three
layered protections in one call. Registered as `ISS-2026-235`/`HDN-BLK-023`, not yet fixed (the
correct shape — guard the generic function conditionally, or revoke direct access entirely — is a
design decision touching a heavily-reused primitive).
**Check:** whenever a new protection (step-up-MFA, IP-restriction, a lockout/lookback guard, an
extra approval) is layered onto one wrapper function around a shared, generic primitive, is the
generic primitive itself still independently callable by a role that does not need to satisfy the
new protection? If yes, either move the new check into the generic primitive (scoped to the
specific transition/case that needs it) or revoke the generic primitive's own direct grant in
favor of forcing every caller through the wrapper.

**C-29 — `CREATE OR REPLACE FUNCTION` with an added parameter silently creates a second overload
instead of replacing the original.**
Postgres identifies a function by name *and* argument-type signature, not name alone — appending
even a single defaulted, trailing parameter changes the signature, so `CREATE OR REPLACE FUNCTION`
does not replace the existing function at all; it silently creates a second, co-existing overload.
Every already-compiled caller that doesn't pass the new parameter keeps resolving to the OLD
overload, forever, regardless of how the new one behaves — a security gate added this way is
therefore never actually reached by any existing caller, while looking, from the migration diff
alone, exactly like an in-place update. Only surfaces as a real Postgres error
(`function name "..." is not unique`) on the next statement that references the function
unqualified by argument types (e.g. a bare `COMMENT ON FUNCTION name(...)` without the newly
ambiguous full signature, or a second migration attempting the same `CREATE OR REPLACE`) — not on
the defining statement itself, which succeeds silently.
*Evidence:* `HDN-378` (Security Hardening) first round, self-caught before commit — a first draft
added a trailing `p_client_ip text default null` parameter to 4 functions via a bare
`CREATE OR REPLACE FUNCTION`, live-tested against a real disposable database as this checkpoint's
own Tier A validation. Surfaced as `function name "app.decide_ai_output_approval" is not unique` on
the very next `COMMENT ON FUNCTION` statement — caught before any commit, not shipped. Fixed by an
explicit `DROP FUNCTION` (old signature) + `CREATE FUNCTION` (new signature) + re-`GRANT EXECUTE`
(restoring the exact original grants, verified against each function's own origin migration) for
all 4 functions.
**Check:** does any migration diff add, remove, or reorder a parameter on an existing function via
a bare `CREATE OR REPLACE FUNCTION`? If so, verify post-migration (via `pg_proc`, grouping by
`(schema, function name) having count(*) > 1`) that exactly one overload exists — never assume a
signature-changing `CREATE OR REPLACE` replaced the original; prefer an explicit `DROP FUNCTION`
(old signature) + `CREATE FUNCTION` (new signature) + re-`GRANT EXECUTE` whenever the parameter
list changes at all.

**C-30 — An e2e/browser test harness pointed at a dev-mode server (Turbopack/webpack `next dev`)
can fail on a client-hydration timing race that never reproduces under a real production build,
making a tooling artifact look like an application defect.**
A form submit button becomes "visible, enabled, and stable" (Playwright's own readiness
definition) before the framework's client-side event interception has actually attached, because
dev-mode compiles/hydrates routes on demand and more slowly than a production build. The click
then falls through to a real browser-native navigation the framework's dev-mode runtime does not
resolve, which never fires its `load` event — the test sees `net::ERR_ABORTED`, an empty
`page.url()`, or a hang to the full test timeout, with no server-side error, no non-2xx status,
and no stack trace to point at, because nothing on the server side ever failed. The route's own
guard logic, server action, and RPC layer are all completely uninvolved. This can also cascade:
once one test in a file hangs to its own 30s timeout against a still-busy dev server, later tests
in the same run can fail the same way even though their own routes are individually fine.
*Evidence:* `HDN-380` (Accessibility Audit) — `e2e/vendor-registration.spec.ts` failed 5 of 7 tests
(`net::ERR_ABORTED`/timeout, `page.url()` returning `""`) against `playwright.config.ts`'s
`webServer.command: "pnpm exec next dev --port 3000"`, reproducible in isolation
(`--workers=1`, ruling out parallel-worker contention) and via a standalone throwaway Playwright
script clicking the same button against a manually-started `next dev` server (`locator.click()`
hangs on "waiting for scheduled navigations to finish"). The identical click against a
`next build && next start` production server on the same route resolved in under 500ms, and the
full suite passed 18/18 with zero 500s against production — conclusively isolating the failure to
dev-mode itself, not the application. Fixed by changing `webServer.command` to
`next build && next start` (with `webServer.timeout` raised to accommodate the build step), which
also directly serves this repository's own `next build`-required convention for this lane.
**Check:** before registering an e2e/browser-harness failure as an application defect (a broken
guard, a hanging server action, a real regression), check what `webServer.command` (or equivalent)
the harness is actually running against. If it is a dev-mode server, reproduce the same failure
against a production build (`next build && next start` or equivalent) before trusting the
diagnosis — a failure that disappears under production is a harness artifact, not a shippable bug,
and the harness itself should point at a production build rather than being routinely excused.

## 5. Two process lessons that are not code classes

Recorded here because both cost real rework and both recur.

- **A finding fixed only where it was found is an incomplete fix.** Every class above was first
  seen once and later found to span 20, 33, 55, 74, or 91 sites. When the batch review confirms
  a finding, the sweep across the rest of the batch and the rest of the repository is part of
  the fix, not a follow-up. `docs/standards/BUILD_EXECUTION_PROTOCOL.md` §5.4 makes this
  mandatory.
- **An unverified finding is not a defect.** `CG-S10-ATW-032` verified 32 claims inherited from
  an audit fan-out: 20 confirmed, 7 already fixed by a later migration, 5 correct by design. A
  clear majority of plausible claims do not survive contact with the live schema. Never fix
  from a register directly — re-derive first.

## 6. Maintenance

Every batch review that confirms a defect not covered by an existing class **adds a class here,
in the same checkpoint**, with its own live evidence citation. This document is the accumulating
memory that lets the cadence in `ADR-0021` stay safe as the build accelerates; a review that
finds a novel class and does not record it has spent the finding.

Classes are append-only and never renumbered. A class fully closed by a structural control
(a database constraint, a lint rule, a CI gate) is marked closed with the control named, not
deleted — the check still runs against diffs that predate the control.
