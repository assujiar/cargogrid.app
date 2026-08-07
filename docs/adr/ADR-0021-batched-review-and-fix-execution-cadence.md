# ADR-0021 — Batched adversarial review-and-fix execution cadence (≤ 5 prompts per review round)

Status: ACCEPTED
Date: 2026-08-07   Approver: Repository owner / operator (explicit instruction, 2026-08-07: revise the execution rules so review and fix run every 5 prompts rather than every prompt, while preserving clean code, inter-data dependency correctness, security, absence of errors and potential errors, and freedom from regression), recorded and operationalized by the runtime build agent per `docs/adr/README.md` §3
Source candidate: `ADR-CAND-ARCH-033` (newly minted; no prior candidate covers build-process cadence)   Owning phase/task: Phase 6 (out-of-band process change, applied from Prompt 257 onward)
Supersedes/Superseded-by: — (does not reopen any prior ADR)

## Question

Prompts 220–256 were executed under an unwritten convention: **one full adversarial
review-and-fix round after every single prompt** — implement, then three parallel review lenses,
then a fix pass, then independent re-verification by the orchestrating session. The convention is
recorded only retrospectively, in each checkpoint's own build log and in
`docs/build-log/phase-06/PROCUREMENT_VENDOR_EXECUTION_INDEX.md`.

It is effective and it is slow. Measured across Phase 6, one prompt costs roughly two hours of
wall-clock, and the dominant cost is review *setup* — provisioning a disposable Postgres, forging
JWT sessions, driving concurrent `psql` processes, re-running the full 139-file `db:test` suite
from scratch — rather than the reviewing itself. That setup cost is almost entirely fixed per
round and almost entirely independent of how much code the round covers.

**174 prompts remain (257–430) against an operator deadline of 2026-08-24.** At one review round
per prompt the arithmetic does not close.

The question: **can the review round be amortized across a batch of up to five prompts without
losing the properties that round was buying** — clean code, correct inter-data dependencies,
tenant/security isolation, absence of errors and latent errors, and freedom from regression?

## Evidence gathered this checkpoint

- **Yield is real and concentrated.** Prompts 251–256 produced ~40 independently-verified real
  defects, of which several were Critical or High and would have shipped silently: a
  single-use invitation token with no row lock creating two vendor profiles (Prompt 251); a
  `jsonb` snapshot column leaking `budget_amount` around its own typed sibling's `PRC:View cost`
  mask *and* real customer PII all the way to the browser's RSC payload (Prompt 256); an import
  handler catching every `unique_violation` and silently dropping a rate while reporting success
  (Prompt 255). Removing the round is not an option.
- **The findings are not novel — they repeat.** Read across `docs/build-log/phase-05/ATW-030.md`,
  `ATW-031.md`, `ATW-032.md` and `docs/build-log/phase-06/PRC-251.md` through `PRC-256.md`, more
  than 90 defects collapse into **20 recurring classes**, now enumerated with live evidence in
  `docs/standards/RECURRING_DEFECT_TAXONOMY.md`. Every Critical and High finding in Phase 6 falls
  into one of them.
- **The classes recur even with per-prompt review in place.** Prompt 256 reintroduced the exact
  session-implicit-`auth.uid()` defect Prompt 255 had already found and fixed. Prompts 252, 253
  and 254 each independently reintroduced the idempotency-comparison class `CG-S10-ATW-030` had
  already swept across 20 functions. **This is decisive for the design:** per-prompt review was
  not preventing recurrence — it was catching recurrence after the fact. A written checklist
  attacks the recurrence directly and does so at write time, which per-prompt review never did.
- **Capabilities in this build are written by mirroring the previous capability's shape.** Stated
  explicitly in the build logs: Prompt 252 mirrored `app.item_control_policy_versions`; Prompt 253
  mirrored Prompt 252's precedent; Prompt 254 mirrored "PRC-252/253's own twice-proven shape";
  Prompt 256 mirrored `app.vendor_profile_lifecycle_events`. This is the specific risk batching
  magnifies — a defect uncaught in prompt N is *copied* into N+1..N+4 — and it is why the batch
  review gains a fourth, cross-prompt lens rather than simply running the same three lenses less
  often.
- **The cheap gates were already catching a distinct class, and they are not the expensive part.**
  `typecheck`, `lint`, `db:test`, `node --test` and `next build` run in minutes. Prompt 253's
  build-breaking `"use server"` regression, Prompt 256's array-operator bug, and Prompt 256's
  three broken read RPCs were all caught by automated gates or the implementing agent's own live
  `db:test` iteration — **not** by the adversarial round. Nothing is gained by batching those.
- **The heavyweight lenses do need a live database, and that is what costs.** The
  security/RLS lens live-tests with forged and alternate-actor sessions; the correctness lens
  live-tests with real concurrent `psql` processes. Both were decisive at Prompts 251, 253, 254,
  255 and 256. Both amortize cleanly across five capabilities, because the fixture setup is the
  same fixture setup.
- **Corrective migrations are already the established repair mechanism.** The rule against
  editing an applied migration means a defect found four prompts late is repaired the same way a
  defect found immediately is: a new migration. `20260730380000_harden_advanced_tms_wms_idempotency_target_mismatch.sql`,
  `20260730480000_harden_optimistic_concurrency_row_lock.sql` and
  `20260730520000_harden_stale_version_no_op_and_swallowed_idempotency_guard.sql` are three
  existing precedents, each repairing 20–74 sites across already-`VERIFIED` phases. Latency of
  discovery therefore raises rework cost but does not change the repair *mechanism* — which is
  what makes a bounded deferral tolerable.
- **Verification discipline must not be relaxed with cadence.** `CG-S10-ATW-032` verified 32
  inherited claims: 20 confirmed, 7 already fixed by a later migration, 5 correct by design. A
  clear majority of plausible claims do not survive contact with the live schema. Whatever the
  cadence, findings are re-derived before they are fixed.

## Options

1. **(SELECTED) Split the round into three tiers — two per-prompt, one per-batch — with
   risk-based triggers that cut a batch short, a fourth cross-prompt review lens, and an adaptive
   batch size.** Tier A (automated gates) and Tier B (a mandatory self-check against the
   documented defect taxonomy) stay per-prompt. Tier C (the four-lens adversarial review, fix
   pass, propagation sweep, and independent full-suite re-verification) runs once per batch of at
   most five prompts. A batch closes early on any Critical/High finding, on a first-of-its-kind
   security mechanism, on any prompt touching finance posting / the RBAC evaluator / RLS
   primitives / auth, on a destructive migration, on a Tier A failure that cannot be cleared
   in-prompt, or wherever the dependency graph forbids the split. Verification, hardening,
   release and final-validation prompts are never batched. Batch size shrinks automatically to 4
   or 3 after a batch that finds Critical/High defects and recovers to 5 only after a clean
   batch. No prompt reaches `VERIFIED` until its whole batch's Tier C closes. Full protocol:
   `docs/standards/BUILD_EXECUTION_PROTOCOL.md`.
   - **Trade-off accepted:** a defect introduced in the first prompt of a batch may be pattern-
     copied into as many as four later prompts before review sees it, raising rework cost when it
     is found. Mitigated by Tier B (the copied defect is most likely a known class, checked at
     write time in every one of the five prompts), by the new cross-prompt lens (whose explicit
     job is to find exactly this), and by the mandatory propagation sweep in §5.4 of the protocol.
     Bounded by the ceiling of five.
   - **Trade-off accepted:** review context is less fresh at batch close than immediately after a
     prompt. Mitigated by per-prompt build logs written at the time, by per-prompt Tier B records
     that hand the reviewers a structured claim to verify, and by the batch plan being declared
     before any code is written.
   - **Trade-off accepted:** the `COMPLETED` state now genuinely means "unreviewed", so a batch
     abandoned mid-flight leaves up to five prompts in a weaker state than the previous cadence
     would have. Mitigated by all-or-nothing batch verification, per-prompt commits, and a
     handoff record at every batch close.
   - **Not accepted as a trade-off, and explicitly preserved:** no gate is disabled, weakened, or
     relabelled; no applied migration is edited; no Critical/High finding is left open
     uncontained; independent re-verification by the orchestrating session remains mandatory and
     may not be replaced by a fix agent's self-report.

2. **Keep per-prompt review and shorten it (drop to one review lens, or review by reading
   instead of live-testing).**
   - Rejected: this is the option that trades safety for speed rather than amortizing fixed cost.
     The evidence is directly against it — the security/RLS and correctness lenses' *live*
     testing produced the Critical and High findings at Prompts 251, 253, 254, 255 and 256, and
     `CG-S10-ATW-029` recorded the underlying lesson explicitly: re-running an existing suite
     cannot surface a defect whose assumptions that suite shares with the code. A single reading
     lens is the weakest part of the current round, not the part worth keeping.

3. **Batch review across a whole phase (~20 prompts) instead of five.**
   - Rejected: the pattern-copying evidence is fatal at that depth. A defect in the phase's first
     capability would propagate through every later one before any review sees it, and — because
     each capability's schema is built on the prior one's — the corrective migration chain would
     grow super-linearly. Five keeps the propagation blast radius small enough that a sweep is a
     bounded, reviewable commit rather than a phase rewrite.

4. **Defer all review to the Step 15 hardening prompts (368–389).**
   - Rejected outright: it is the failure mode the operator explicitly asked to avoid ("so that
     no debugging is needed once construction finishes"). It also contradicts
     `10_MASTER_AGENT_SYSTEM_PROMPT.md` §18 — a phase may not be labelled complete beyond the
     evidence obtained — and would leave nine phases' worth of Critical/High defects to be found
     under release pressure, with corrective migrations landing on top of already-`VERIFIED`
     schema across the whole build.

## Decision

Option 1. Binding on every capability prompt from **Prompt 257** onward. Prompts 220–256 remain
`VERIFIED` under the prior per-prompt cadence and are not revisited.

The protocol is `docs/standards/BUILD_EXECUTION_PROTOCOL.md`. The compensating control that makes
it safe is `docs/standards/RECURRING_DEFECT_TAXONOMY.md`. `AGENTS.md` §"Execution cadence" points
at both and is the entry point a fresh agent reads first.

## Consequences

**Expected.** Review setup cost is amortized roughly 5:1. Per-prompt wall-clock falls to
implementation plus Tier A plus Tier B; the four-lens round, fix pass and full fresh gate suite
are paid once per batch. Tier B is expected to move a meaningful share of the recurring classes
from "found by review" to "not written", which is a net reduction in total work, not merely a
reschedule of it.

**Honest about what this does not buy.** It does not shorten the Step 15 hardening or Step 16
release/go-live sequences, which are what establish publish-readiness. It does not make the
remaining 174 prompts fit comfortably before 2026-08-24 on its own — batching is one lever, and
parallel implementation across independent dependency-graph branches (`docs/standards/BUILD_EXECUTION_PROTOCOL.md` §8)
is the other. Any claim that the deadline is met must rest on evidence at the time, not on this
ADR.

**Reversal.** If two consecutive batches each produce two or more Critical/High findings, or if a
batch review finds a defect that pattern-propagated across four or more prompts in its own batch,
the adaptive rule in the protocol §3.4 has failed to contain the risk and this ADR must be
revisited — reverting to per-prompt review for the affected phase, recorded as a superseding ADR
rather than an undocumented practice change.

**Records updated in this checkpoint.** `AGENTS.md`, `docs/adr/README.md` (§5.2 candidate
register and §6 index), `docs/runtime/CHANGE_MANIFEST.md`, `docs/runtime/CARGOGRID_BUILD_STATUS.md`,
`docs/runtime/HANDOFF.md`.

**Not changed.** No CPD or RPD is touched — this is a build-process decision, not a product
decision, and an ADR may never weaken a ratified product decision
(`docs/adr/README.md` §1). No schema, service, UI, or test file is modified by this checkpoint.
