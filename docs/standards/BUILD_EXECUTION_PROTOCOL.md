# CargoGrid Build Execution Protocol — Batched Review Cadence

**Owner:** Runtime build agent
**Established by:** `ADR-0021` (batched review-and-fix execution cadence)
**Status:** `ACTIVE` — binding on every capability prompt from Prompt 257 onward
**Version:** `1.0.0` (2026-08-07)
**Supersedes:** the per-prompt review convention used for Prompts 220–256 (convention, never
written down as a rule; recorded retrospectively in `docs/build-log/phase-06/PROCUREMENT_VENDOR_EXECUTION_INDEX.md`
as "implement → 3-lens adversarial review → fix", run once per prompt)

## 1. What changed and why

Prompts 220–256 ran a full adversarial review-and-fix round **after every single prompt**. It
worked: more than 90 real defects were found and closed, including every Critical and High
finding the build has produced. It also cost roughly two hours of wall-clock per prompt, most of
it in review setup — spinning a disposable Postgres, forging JWT sessions, driving concurrent
`psql` processes — rather than in the review itself.

From Prompt 257 the review round runs **once per batch of up to five prompts** instead of once
per prompt. The heavy machinery is amortized across five capabilities.

Batching review is only safe if the things per-prompt review was catching *cheaply* keep
running per-prompt. That is the whole design: the round is split into three tiers, two of which
stay per-prompt, and a set of triggers cuts a batch short the moment risk concentrates.

**What this protocol does not claim.** It does not remove the need for the phase Integrated
Verification, Hardening, Documentation and Closure prompts, nor for the Step 15 hardening
(Prompts 368–389) and Step 16 release/go-live (Prompts 390–412) sequences. Those exist to
establish publish-readiness and are explicitly out of scope for batching (§3.3). This protocol
buys build speed; it does not buy a shorter path to production.

## 2. The three tiers

| Tier | Cadence | Runs | Typical cost | Blocking |
|---|---|---|---|---|
| **A — Automated gates** | Every prompt | Mechanical scripts | 5–10 min | Yes |
| **B — Taxonomy self-check** | Every prompt | The implementing agent, against its own diff | 10–15 min | Yes |
| **C — Adversarial review + fix** | Every batch (≤ 5 prompts) | 4 parallel review lenses, then a fix pass, then independent re-verification | 45–90 min per batch | Yes |

### 2.1 Tier A — automated gates, every prompt

Run at the end of every prompt, before the prompt's commit:

```text
pnpm run typecheck
pnpm run lint
pnpm run db:test              # the new migration must apply; its own db-test file must pass
pnpm run test                 # full node:test suite
pnpm run git:check-paths
pnpm run security:check
```

`pnpm exec next build` is required per-prompt **whenever the prompt adds or changes any file
under `app/`, `components/`, or a `"use server"` module** — defect class C-16 in
`docs/standards/RECURRING_DEFECT_TAXONOMY.md` is invisible to `typecheck` and `lint`, and it
broke the build outright at Prompt 253. For a migration-only or docs-only prompt, `next build`
may defer to the batch close.

`pnpm run docs:check`, `data-classification:check`, `threat-model:check`, `standards:check` and
`security:audit` run at batch close (§5.5). A prompt that adds a data-classification-relevant
column runs `data-classification:check` in-prompt as well.

**A Tier A failure is not deferrable.** The prompt is not `COMPLETED` until Tier A is green or
the failure is proven pre-existing against a captured baseline and recorded in
`docs/runtime/ERROR_LEDGER.md`.

### 2.2 Tier B — taxonomy self-check, every prompt

Walk `docs/standards/RECURRING_DEFECT_TAXONOMY.md` §4 against your own diff and record the
result in the prompt's build log. This is the control that makes batching safe, and it is
mandatory. See that document §2 for how to run it.

### 2.3 Tier C — adversarial review and fix, every batch

Four review lenses run **in parallel** against the batch's combined diff, then one fix pass,
then independent re-verification by the orchestrating session. Detailed in §5.

## 3. Batch planning

### 3.1 Reading an operator range

When the operator authorizes a range — "lanjut prompt 257-266" — the agent **plans the batches
before writing any code** and states the plan in its first response:

```
Authorized range: 257-266
  Batch 1: 257, 258, 259, 260, 261   → build 5, then Tier C
  Batch 2: 262, 263, 264, 265, 266   → build 5, then Tier C
```

The plan names, for each batch: the prompts, their dependency order, which prompts carry a §3.2
trigger, and the intended batch-close commit point. If the range is not a multiple of five, the
final batch is short — never long.

**Five is a ceiling, not a quota.** A batch may be cut to 4, 3, 2 or 1 by any rule below. It may
never exceed 5.

### 3.2 Triggers that cut a batch short

The batch closes at the prompt where any of these first fires, and Tier C runs immediately —
even if only one prompt has been built:

1. **A Critical or High severity defect is found by anything** — Tier A, Tier B, the
   implementing agent's own testing, or an incidental observation.
2. **A prompt introduces a first-of-its-kind security mechanism**: at-rest encryption, a new
   anonymous or public entry point, a new external ingress or webhook, a new credential store.
   (Prompt 254 was this repository's first at-rest confidentiality mechanism; Prompt 251 opened
   its first anonymous entry point. Both produced High findings.)
3. **A prompt writes to finance posting, the RBAC evaluator, RLS tenant primitives, or auth.**
4. **A prompt requires a destructive migration**, which additionally requires explicit operator
   authorization under `AGENTS.md` and is never batched.
5. **A prompt's own Tier A cannot be made green inside that prompt.**
6. **The dependency graph forbids the split**: if prompt N+1 consumes a contract N defines and
   the two would land in different batches, either pull N+1 into the current batch (if ≤ 5) or
   cut the batch before N so the pair stays together. Never verify a consumer before its
   producer.

### 3.3 Prompt classes that are never batched

These run standalone with their own full Tier C, because they *are* review and batching them is
self-defeating:

- Phase Integrated Verification, Security/Financial Hardening, Documentation Handoff, and
  Closure Verification prompts (for Phase 6: Prompts 268–271).
- Every Step 15 hardening prompt (368–389).
- Every Step 16 release and go-live prompt (390–412).
- Every Step 17 final package validation prompt (413–430).
- Any WBS/runtime kickoff prompt (docs-only; it takes Tier A and B but needs no Tier C, and it
  does not consume a batch slot).

### 3.4 Adaptive batch size

The batch size is a feedback loop, not a constant:

- A batch whose Tier C finds **zero Critical/High** defects → next batch may be 5.
- A batch whose Tier C finds **one Critical/High** → next batch is at most 4.
- A batch whose Tier C finds **two or more Critical/High** → next batch is at most 3, and stays
  capped at 3 until a batch closes with zero Critical/High.

Record the size decision and its reason at the top of the next batch's plan. This is how the
cadence self-corrects if a phase turns out to be riskier than Phase 6 was.

### 3.5 The prompt files are not edited — and one clause is narrowed

All 430 prompt files in `docs/ai-agent-build-prompt-package/` remain valid exactly as written and
**none is modified by this protocol**. A capability prompt specifies *what* to build, *which*
files are allowed and forbidden, *which* gates apply, and *what* Done means. It does not specify
how often the adversarial review round runs — that was always convention, which is why changing
it needed `ADR-0021` rather than 174 file edits.

Verified across the package before adopting this protocol: §30 ("Commands to run") names the
gate set, not its cadence; §33's "mandatory automated/manual gates pass at one recorded
checkpoint" is satisfied by the batch close, which *is* one recorded checkpoint; §34 and §35 are
content and evidence requirements with no timing claim. Only one phase-6 prompt mentions
adversarial review at all — Prompt 269, the hardening prompt, which §3.3 already exempts from
batching.

**The single genuine conflict, and its resolution.** 166 capability prompts carry an identical
§36 clause:

> Only the execution index may release `<NEXT-TASK>` or another dependency-clean atomic task
> after this task is `VERIFIED`.

Written when `COMPLETED` and `VERIFIED` were reached in the same sitting. Under batching a prompt
holds `COMPLETED` until its batch's Tier C closes, so read literally no second prompt in a batch
could ever start. Resolved as `CON-015` in
`docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md`, which ranks above the
task prompt under `AGENTS.md` "Instruction precedence":

- **Within one batch** — a downstream prompt may be released on its upstream being `COMPLETED`.
- **Across a batch boundary** — §36 is unchanged. No prompt in batch N+1 begins until every
  prompt in batch N is `VERIFIED`.

The relaxation is exactly co-extensive with the batch — the same envelope `ADR-0021` accepted and
capped at five — and is further bounded by all-or-nothing batch verification and by the §3.2
trigger that cuts a batch wherever a dependency edge would separate a producer from its consumer.

**Do not extend this override to anything else in a prompt.** Allowed/forbidden paths, database
and API impact, access rules, acceptance criteria and Definition of Done are untouched. If a
future prompt is found to carry a second clause incompatible with this cadence, register it in
the conflict register in the checkpoint that finds it — never resolve it silently in the code.

## 4. Task states under batching

The state vocabulary is unchanged (`10_MASTER_AGENT_SYSTEM_PROMPT.md` §17). What changes is when
`VERIFIED` may be claimed:

| State | Meaning under this protocol |
|---|---|
| `IN_PROGRESS` | Implementation started |
| `COMPLETED` | Implementation done, **Tier A green, Tier B walked and recorded**. Adversarially unreviewed. |
| `VERIFIED` | The batch's Tier C review, fix pass, and independent re-verification are all complete, and this prompt survived them. |

**A batch is all-or-nothing.** No prompt in a batch reaches `VERIFIED` until the whole batch's
Tier C closes. If Tier C finds a defect in prompt 258 that requires a corrective migration, the
entire batch stays `COMPLETED` until the fix is applied and re-verified.

Never edit an applied migration to fix a batch finding. Add a corrective migration — the rule in
`AGENTS.md` is unchanged and batching does not relax it. This is why per-prompt commits matter
(§7): the corrective migration is a new, separately reviewable commit, not a rewrite.

## 5. Tier C — the batch review round

### 5.1 Inputs

The reviewers receive the combined diff of the whole batch, every prompt's build log, the batch
plan, and `docs/standards/RECURRING_DEFECT_TAXONOMY.md`. They receive each prompt's Tier B
record and are told explicitly that a Tier B clear is a claim to verify, not a result to trust.

### 5.2 The four lenses

Three lenses carry forward from the per-prompt convention; the fourth is new and exists because
batching creates exactly the risk it looks for.

1. **Spec-compliance.** Every requirement in each prompt's own source spec, traced to the code
   that satisfies it or to an explicit disclosure. Owns taxonomy classes C-15, C-18, C-20.
2. **Security, RLS, and tenant isolation.** Live-tested against a real disposable Postgres with
   forged and alternate-actor sessions — never by reading alone. Owns C-05, C-06, C-07, C-08,
   C-10, C-11, C-12, C-13, C-17.
3. **Correctness and concurrency.** Live-tested with real concurrent `psql` sessions. Owns
   C-01, C-02, C-03, C-04, C-09, C-14, C-19.
4. **Cross-prompt integration and data dependency** *(new)*. Owns the risk batching introduces:
   - Does each prompt actually compose against what the earlier prompts in this batch built, or
     against what it assumed they would build?
   - Are FK, lineage, versioning, and snapshot contracts consistent across the batch — one
     canonical root, no second store for the same entity?
   - Did a pattern copied from an earlier prompt in this batch carry a defect with it? *(This is
     the specific failure mode batching magnifies: the build's own history shows capabilities are
     built by mirroring the previous one's shape.)*
   - Does any prompt in the batch weaken, shadow, or silently widen a contract an earlier phase
     already had `VERIFIED`?
   Owns C-07, C-08, C-16, C-19, C-20.

### 5.3 Verification standard for a finding

Unchanged from the existing convention, and non-negotiable: a finding is **CONFIRMED** only when
re-derived against the live schema or live-reproduced. `CG-S10-ATW-032`'s disposition of 32
inherited claims — 20 confirmed, 7 already fixed by a later migration, 5 correct by design — is
the standing evidence for why. Never fix from a findings register directly.

### 5.4 Propagation sweep is part of the fix

Every confirmed finding is swept across **(a)** the rest of the batch and **(b)** the repository,
in the same fix pass. A finding fixed only at its discovery site is an incomplete fix. This
repository's own history is the argument: single findings later proved to span 20, 29, 33, 55,
74, and 91 sites.

When the sweep is mechanical, parse structure — do not grep. `CG-S10-ATW-032`'s inert-guard
sweep had to parse block nesting because a `raise exception` line contains the word `exception`,
and that is exactly what had hidden the defect. And never put a blanket `GRANT` inside a sweep
(taxonomy C-11).

### 5.5 Batch close: full gate suite, run fresh

After the fix pass, the orchestrating session **independently re-runs** the complete suite from
scratch — it does not accept the fix agent's self-report:

```text
pnpm run typecheck
pnpm run lint
pnpm run test
pnpm run db:test              # full suite, from scratch
pnpm exec next build
pnpm run docs:check
pnpm run security:check
pnpm run security:audit
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check
pnpm run git:check-paths
pnpm run git:check
```

Plus: **direct code reads of every Critical and High fix**, confirming each is genuinely present
and correctly shaped. Prompt 253's fix agent ended its session without a final report, and the
orchestrating session's own independent verification caught a build-breaking regression that fix
had introduced. Independent re-verification is not ceremony.

Every gate number goes in the batch close record. A gate that fails is either fixed, or proven
pre-existing against a captured baseline and registered in `docs/runtime/KNOWN_ISSUES.md` — never
silently carried.

### 5.6 Disposition of findings not fixed

A confirmed finding may be disclosed rather than fixed when it is genuinely outside the batch's
allowed-files scope or would require an architectural decision the batch has no mandate to make.
Every such finding is registered as a numbered issue in `docs/runtime/KNOWN_ISSUES.md` with
recorded reasoning. **No Critical or High finding may be left open uncontained** — it is either
fixed and re-verified, or fully disclosed in a tracked issue with its exposure stated.

## 6. Documentation under batching

Per prompt (written at the end of that prompt, not deferred):

- `docs/build-log/<phase>/<TASK-ID>.md` — implementation, decisions, Tier A results, **Tier B
  taxonomy walk**, disclosed limitations.

Per batch (written at batch close):

- A batch close section in the last prompt's build log, or a dedicated batch record, containing:
  the batch plan and any §3.2 trigger that fired, all four lenses' findings and disposition, the
  propagation sweep, the full fresh gate suite with exact numbers, the direct-code-read
  confirmations, and the §3.4 size decision for the next batch.
- `docs/runtime/CARGOGRID_BUILD_STATUS.md` — one checkpoint note per batch, not per prompt.
- `docs/runtime/TASK_LEDGER.md` and the phase execution index — every row in the batch moved to
  `VERIFIED` together.
- `docs/runtime/CHANGE_MANIFEST.md`, `KNOWN_ISSUES.md`, `ERROR_LEDGER.md` — as applicable.
- `docs/runtime/HANDOFF.md` — at batch close, so a fresh agent can resume from a batch boundary.
- `docs/standards/RECURRING_DEFECT_TAXONOMY.md` — **a new class for any novel defect the review
  found**, in this same checkpoint.

## 7. Git discipline

- **One commit per prompt.** Rollback granularity is per capability, not per batch. The commit
  message names the task ID and states `Tier A green, Tier B walked, adversarially unreviewed`.
- **One fix commit per batch**, naming the findings it closes.
- **Push at least at every batch close.** More often is fine and is safer in an ephemeral
  container. Nothing survives the container that is not pushed.
- The `AGENTS.md` pre-flight collision check (`ISS-2026-002`) runs **once per batch**, before the
  first prompt in the batch — not once per prompt.
- Branch naming, protected paths, and the never-rewrite-shared-history rule are unchanged; see
  `docs/git/GIT_STRATEGY.md`.

## 8. Parallelism

Batching lowers the review cost per prompt. Parallelism is the other lever, and it is bounded by
the dependency graph, which the phase execution index already records.

- **Implementation may run in parallel** only for prompts with no edge between them in that
  phase's dependency table. Prompts 257→258→259→260 (RFQ → comparison → approval → PO) are a
  strict chain and must run in order. Prompts in different workstreams often are not.
- **Two agents must never hold the same migration timestamp range or the same allowed-files
  set.** Assign disjoint file scopes in the batch plan, or run sequentially.
- **The four review lenses always run in parallel.** They are independent by construction.
- The `ISS-2026-002` single-writer discipline is unchanged: one authoritative branch per runtime
  step. Parallel *agents* are permitted; parallel *branches* against the same task range are not.

## 9. What has not changed

Everything in `AGENTS.md`, `docs/ai-agent-build-prompt-package/01-agent-governance/10_MASTER_AGENT_SYSTEM_PROMPT.md`,
and the ratified CPD/RPD register stands unchanged. In particular:

- Tenant isolation, RLS/RBAC, canonical data, financial correctness, migration safety, and the
  Supreme Admin disclosure are untouched.
- No gate may be disabled, weakened, or relabelled to obtain a green result.
- No applied migration may be edited.
- Pre-existing failures are separated from change-caused failures with baseline evidence.
- Completion requires evidence; a phase or product may never be labelled complete beyond the
  evidence actually obtained.
- A named operator range does not authorize the next range. Closing a batch does not authorize
  the next batch beyond the range the operator named.

Batching changes **when** the adversarial review runs. It changes nothing about **whether** the
code is correct, isolated, and evidenced before it is called `VERIFIED`.
