# Step 16 (Release Candidate and Go-Live) — Execution Index

**Prompt:** `CG-S16-RGL-001` (391, Release Go-Live WBS Runtime Kickoff)
**Runtime output of:** `docs/ai-agent-build-prompt-package/16-release-go-live/391_RELEASE_GO_LIVE_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Package document:** `CG-AABPP-RGL-391`, package version `0.17.0`
**Runtime state set by this checkpoint:** `RELEASE_GO_LIVE_IN_PROGRESS`
**Owner (every row, this build's standing convention):** Claude Code (runtime build agent)
**Short code:** `RGL` (per every Step 16 prompt file's own self-declared `CG-S16-RGL-*` ID)

> **This file is the resume contract.** It, not any operator message, routes the next
> session. A session that disagrees with a row here must correct the row, with evidence,
> before acting on the disagreement. This mirrors
> `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md`'s own standing convention.

> **This document is not a production, pilot, GA, or market-ready claim**, and nothing in
> Step 16 may become one before Prompt 412 (`CG-S16-RGL-022`) sets
> `RELEASE_GO_LIVE_VERIFIED` on real evidence. See §13.

---

## 1. Naming — two numbering schemes, deliberately not merged

Identical in shape to Step 15's own §1, and for the same reason: both schemes are fixed by
the package and neither can be renamed.

| Scheme | Form | Meaning |
|---|---|---|
| Lane / build log | `RGL-391` … `RGL-412` | **The prompt number.** Fixed by each prompt file's own `Runtime build log:` line — e.g. `392_RELEASE_CANDIDATE_FREEZE_PROMPT.md` names `RGL-392.md`, to be written in this directory. |
| Task ledger ID | `CG-S16-RGL-001` … `CG-S16-RGL-022` | **The sequential task number.** Fixed by each prompt file's own §1 / `Prompt ID:` line. |

`RGL-392` and `CG-S16-RGL-002` are the same task. No third scheme is introduced.

**Prompt 390 (`390_RELEASE_GO_LIVE_README.md`) is the package README, not a runtime task.**
It has no `CG-S16-RGL-*` ID and produces no build log — exactly as Prompt 368 stood to Step 15.
The operator range "prompt 390-412" therefore contains **22 runtime tasks**, `RGL-391`
through `RGL-412`, not 23.

---

## 2. Checkpoint freeze (Prompt 391 step 1)

| Field | Value |
|---|---|
| Repository root | `/home/user/cargogrid.app` |
| Branch | `claude/step-16-prompt-390-412-okbd6v` |
| HEAD at session start (this checkpoint's base) | `2670cb5849c2ab7b653fef586f51130eb54ef321` — merge of PR #67, `claude/step-15-hdn-369-kickoff-w6qren`, committed 2026-08-25T09:15:34+07:00 |
| Branch state at session start | **Zero commits ahead of `origin/main`.** The branch existed at `origin` and pointed at the same commit as `main`. This matters — see §9's disclosed Tier A failure |
| Worktree at session start | clean (`git status --short` empty before this checkpoint's first file was written) |
| Checkpoint date | 2026-08-25 (**Tuesday** — see §9.1, this matters for the fixture-flake class) |
| Release candidate identity | **Not yet frozen.** `RGL-392` owns freezing it. No tag exists in this repository (`git tag` empty); the candidate will be identified by commit SHA, not tag, unless `RGL-392` rules otherwise |
| Package manager / runtime | `pnpm@10.33.0`, `node@v22.22.2` (`package.json` `engines.node` `>=22.11.0`). `node_modules` did **not** exist at session start; `pnpm install --frozen-lockfile` this checkpoint (sandbox provisioning, not a repository change) |
| Local database | PostgreSQL 16.13 (Ubuntu). Not running at session start; `service postgresql start`, `apt-get update && apt-get install postgresql-16-postgis-3`, and a one-time local `postgres` role password matching `scripts/db-tests/run.sh`'s documented default were all required as sandbox provisioning (identical to `HDN-369`'s own provisioning, plus the `apt-get update` that `HDN-369` did not need — see §9.2) |
| Migration files | **333** under `supabase/migrations/`, latest `20260819000000_harden_release_blocker_triage_remediation.sql`. Unchanged from `HDN-389`'s own close |
| Live database | **`cargogrid.app` (`awdlicmwzdxquopwtcfd`), ap-northeast-1, PostgreSQL 17.6.1.155, `ACTIVE_HEALTHY`.** Verified live this checkpoint via the Supabase management API, not re-cited from Step 15 |
| Schema state | **[Corrected at `RGL-402`, 2026-08-25 — this row's original claim is stale, superseded mid-range by an out-of-sequence fix.]** `app` is still not exposed through the Data API directly (re-confirmed live: `information_schema.tables` for `table_schema='public'` returns only `spatial_ref_sys`, PostGIS's own table — zero `app` table reachable). But the *original* claim ("no `app` object is reachable over PostgREST") is no longer true in the way this row first meant it: the `RGL-BLK-002` Option 2 remediation (2026-08-25, out-of-sequence, before `RGL-004`) deliberately added 2,367 `public.*` security-mode-matched wrapper *functions*, one per externally-callable `app.*` function, so `app`'s functionality — never its raw tables — is now reachable via `/rest/v1/rpc/<wrapper_name>`, by design, with each wrapper's own grants mirroring its `app.*` counterpart's. `RGL-402` re-verified this live and found it holds (13 anon-executable `SECURITY DEFINER` functions, all individually accounted for: 5 are this build's own intentional unauthenticated webhook/tracking ingestion points, 5 are intentional pre-login tenant/locale/brand/IdP resolution reads, 3 are PostGIS's own stock `st_estimatedextent` overloads, unrelated and pre-existing; `public.ping()`, the canary from the Option 2 remediation, is still `service_role`-only, `anon`/`authenticated` both denied). Full re-verification: `docs/build-log/release-go-live/RGL-402.md`. |
| Feature flags | No runtime feature-flag service exists in this repository. Behaviour is gated by effective-dated database configuration rows, not flags. "Flag state" is therefore **not** a freezable axis here and is recorded as *absent* rather than left implicit. Every Step 16 prompt that names feature flags (`RGL-399`, `RGL-400`, `RGL-405`) must state this, not invent a flag plan |
| Deployed environment | **EXISTS — and this is a state change Step 15 never recorded. See §2.1.** |
| Phase 0–9 status | `PHASE_0_VERIFIED` … `PHASE_9_VERIFIED` all set |
| Step 15 status | **`FULL_SYSTEM_HARDENING_VERIFIED`, set 2026-08-24 at `CG-S15-HDN-021` (Prompt 389)** — the only prompt authorized to set it. Evidence: `docs/build-log/full-system-hardening/FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` |
| Step 17 | `NOT_STARTED`, and out of scope for every prompt in this range (§13) |

### 2.1 State-freeze correction — "no deployed environment" is stale, and the truth is load-bearing

`docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §2 froze, and §10 built an entire
structural constraint on:

> **Deployed environment: None.** No Vercel deployment, no CI-driven deploy pipeline, no real
> sign-in flow. The live Supabase project is a migrated database, **not** a running system.

**That is no longer true, and was already not true when Step 15 froze it.** Verified live this
checkpoint against the Vercel management API and by unauthenticated HTTP probe — not inferred,
and not re-cited from any prior document:

| Fact | Evidence |
|---|---|
| A Vercel project **`cargogrid-app`** exists (`prj_9ND1BsfbppHiqeKrSEldYh8xbC68`), team `saiki` (`saiki-tech`, `team_jYIRP8E0gAnewOGS5H7yD3BL`), framework `nextjs`, `nodeVersion` **`24.x`** | Vercel `get_project` |
| It is **Git-linked to `assujiar/cargogrid.app`** and auto-deploys: `main` → `target: production`, every other branch → preview | Vercel `list_deployments`; every listed deployment carries `githubDeployment: "1"` |
| The project was created **2026-08-10T06:29:46Z** — **13 days before `HDN-369` froze "no Vercel deployment"** | `createdAt: 1786343386408` |
| The current `main` HEAD `2670cb5` has a **`READY`, `target: production` deployment**, created **2026-08-25T02:15:38Z** | deployment `dpl_4vgM6mR6Y5xpA3UfGxsdY2WFCs4U` |
| Production aliases: `cargogrid-app.vercel.app`, `cargogrid-app-saiki-tech.vercel.app`, `cargogrid-app-git-main-saiki-tech.vercel.app` | Vercel `get_project` `domains` |
| Production is **publicly reachable with no authentication**. `GET /` → `302` → `/login` → **`200`**, real rendered Next.js HTML | `curl` this checkpoint, no credentials presented |
| Deployment protection: `passwordProtection` **off**; `ssoProtection` **on**, `deploymentType: all_except_custom_domains`; `trustedIps` **off** | Vercel `get_project_deployment_protection`. The production alias answered anonymously regardless — previews are gated, production is not |
| **Production is degraded.** `GET /api/health` → `200 {"status":"ok"}` (a liveness probe that touches nothing). `GET /api/ready` → **`503 {"status":"degraded","reason":["database_unreachable"]}`**. `GET /api/v1/status` → **`500`** | `curl` this checkpoint |
| **14 of the 20 most recent deployments are `ERROR`**, including a `target: production` build at `20a2cc9` on 2026-08-24T14:25:18Z — production was broken for ~12 hours and no Step 15 checkpoint noticed, because Step 15's own freeze said this environment did not exist | Vercel `list_deployments` |

**Why this is not a footnote.** Four separate consequences, each of which changes Step 16 work:

1. **Step 16's own non-negotiable gate is already defeated.** `390_RELEASE_GO_LIVE_README.md`
   states: *"No production deployment without recorded go decision."* A production deployment
   exists, is live, and no go decision was ever recorded — `RGL-404` has not run. The mechanism
   is still armed: **every future merge to `main`, including the merge that closes this very
   Step 16 range, auto-deploys production with no gate.** Registered as `RGL-BLK-001` (§8.3).
2. **A publicly-reachable, database-unreachable production app is the live public face of this
   product right now.** Registered as `RGL-BLK-002` (§8.3).
3. **Step 15 §10's "a migrated database is not a running system" constraint is partly
   obsolete.** Several Step 16 gates that Step 15 would have had to record as tracked gaps are
   now genuinely executable against a real running target. §10 below re-derives the posture
   table from the *current* facts rather than inheriting Step 15's.
4. **`ISS-2026-284` is registered** for the stale claim itself (§8.3) — the process defect is
   that a load-bearing environment fact drifted for 13 days across 21 `VERIFIED` checkpoints
   without any checkpoint re-verifying it against the provider.

**Deliberately not touched, per `AGENTS.md`'s append-only rule for `docs/runtime/`:** Step 15's
own build logs, ledgers and execution index. Those recorded what their authors observed at the
checkpoint they describe; rewriting them would corrupt the evidence trail. This section corrects
the **current-state** assertion and nothing else. `RGL-411` owns propagating the correction into
any *forward-looking* document that still asserts the old state.

### 2.2 What this repository does and does not have, stated once

Recorded here so no later lane has to rediscover it, and so no later lane can quietly assume
the opposite:

| Thing | State |
|---|---|
| Production environment | **One**, Vercel `cargogrid-app` production target, auto-deployed from `main`, publicly reachable, currently degraded |
| Staging environment | **None.** No separate Vercel project, no separate Supabase project, no separate database. Vercel *preview* deployments exist per branch (SSO-gated) but share nothing that makes them a staging tier |
| UAT environment | **None.** No environment, no UAT tenant, no UAT user accounts, no business acceptors identified anywhere in this repository |
| Databases | **One** live Supabase project, plus disposable local Postgres for `db:test`. There is no separate production/staging/UAT database — the single live project is whatever the deployed app points at |
| Real tenant data | **None known.** No Step 16 lane may assume this without proving it; `RGL-398` owns proving it |
| Real end users | **None known.** Same rule |
| CI deploy pipeline | **None.** `.github/workflows/ci.yml` has three jobs (`quality`, `db`, `e2e`) and no deploy step. Deployment is Vercel's own Git integration, entirely outside this repository's CI |
| CI `next build` gate | **Absent** — the pre-existing, documented gap Step 15 handed forward. `RGL-395` owns it |
| Release tag | **None.** `git tag` is empty |

---

## 3. Runtime entry verdict — **PASS, with two conditions recorded, not waived**

Prompt 391's entry gate: *"Do not begin unless `FULL_SYSTEM_HARDENING_VERIFIED` exists at the
active checkpoint and Step 16 has explicit runtime authority."* Plus step 2: *"Confirm no
unresolved critical/high hardening, tenant, RLS/RBAC, security, financial, API, storage,
performance, accessibility, observability, backup/restore, DR or migration blocker exists."*

**`FULL_SYSTEM_HARDENING_VERIFIED`: set.** Verified this checkpoint by direct read, not
re-citation:

- `docs/runtime/TASK_LEDGER.md` — `CG-S15-HDN-021` row, status `VERIFIED — sets
  FULL_SYSTEM_HARDENING_VERIFIED`, dated 2026-08-24.
- `docs/runtime/HANDOFF.md` — run-status line and §0, both stating the flag is set at
  `CG-S15-HDN-021`/Prompt 389.
- `docs/build-log/full-system-hardening/FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` — the exact
  closure artifact Prompt 391 requires, produced by the only prompt authorized to produce it.
- `docs/runtime/RELEASE_READINESS_MATRIX.md` §3 — all 6 of Step 15 §12's eligibility conditions
  `MET`, with 3 disclosed `PARTIAL` gate residuals.

**Explicit runtime authority: present.** The operator's own instruction for this session names
the exact range — "lanjut step 16 prompt 390-412" — and enumerates all 22 tasks `RGL-001`
through `RGL-022` by ID and name. This mirrors the fresh, separate, range-naming authorization
Step 15 required at `HDN-369`.

**Pre-flight collision check (`ISS-2026-002`, `AGENTS.md` "Required pre-flight"): PASS,
executed, not skipped.** GitHub API, this checkpoint: **0 open pull requests**; 47 branches
enumerated and read; **no branch other than this one carries any `RGL-*` / Prompt 390-412
work**. `claude/step-15-hdn-369-kickoff-w6qren` is fully merged (PR #67, `2670cb5`). This is
the check this repository's history records being skipped 5 times, causing `ERR-2026-001..003`.

### 3.1 Condition 1 — the 17 open High blockers are *accepted*, not *absent*

Prompt 391 step 2 asks for "no unresolved critical/high blocker". The honest answer:

- **0 Critical open.** Independently re-confirmed at `HDN-387` and again entry-by-entry at
  `HDN-389`.
- **17 High open, every one of them formally `ACCEPTED_EXCEPTION`** under
  `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §8.2's full 5-condition test —
  12 via `HDN-BLK-039` at `HDN-387`, 5 via `HDN-BLK-040` at `HDN-389`. **The named owner on
  every one of those 17 acceptances is `Step 16`.**
- **6 Medium open**, individually owned, below Step 15's own closure threshold.

So there is **no *unresolved* Critical/High blocker** in §8.2's sense, and the entry gate is
met. But "resolved" here means *ruled on*, not *fixed* — the underlying technical work is
genuinely open. **`RELEASE_READINESS_MATRIX.md` §3 says so in those words**, and this checkpoint
does not soften it.

**The distinction Step 16 must not blur, stated once and binding on every lane below:** those
17 acceptances were granted against **Step 15's closure bar** — "is Step 15's verify/repair/
document charter complete?". They were **not** granted against a **production go-live bar**.
`RGL-404` (Go/No-Go Report) must re-rule every one of the 17 against the production bar on its
own authority and its own evidence. **Inheriting a Step 15 acceptance as a Step 16 go decision
would be exactly the "casual risk acceptance" Prompt 394 §5 exists to prevent.** Registered as
a standing constraint, not advice: §8.2 condition 4 below.

### 3.2 Condition 2 — the environment fact in §2.1 changes the entry picture, and is recorded before any lane starts

Step 16's entry gate does not ask about deployment state, so §2.1 does not block entry. It does
change what entry *means*: this range does not begin from "nothing is deployed". It begins from
"an ungated production deployment is already live and degraded". Both facts are registered as
`RGL-BLK-001`/`RGL-BLK-002` at §8.3 **before** any lane runs, so no later lane can present them
as its own discovery, and `RGL-404` cannot reach a go decision without dispositioning them.

### 3.3 Condition 3 — the Tier A baseline is red, and `RGL-392` must freeze it that way

This checkpoint's own baseline run found a **real, previously-unregistered product defect** that
fails `bash scripts/db-tests/run.sh` for 3 hours of every 24 (§9.4, `RGL-BLK-004`). The suite did
not print `ALL PASSED`; 27 of 230 test files never ran.

**This does not block entry**, and saying it did would be the wrong call: Prompt 391's completion
gate turns on whether a *mandatory prerequisite* is missing, and the prerequisite —
`FULL_SYSTEM_HARDENING_VERIFIED` with its closure artifact — is present and verified. A defect
found *by* Step 16's own baseline is not a missing prerequisite; it is precisely the input
`RGL-394` (Defect Triage) exists to process.

**What it does bind:** `RGL-392` must freeze a **red** test matrix and say so. A release candidate
frozen against a "230/230" figure carried forward from Step 15 would be a fabricated baseline —
the exact failure mode `RC_FROZEN` exists to prevent. `RGL-395` may not certify the CI gate, and
`RGL-404` may not reach a go decision, while `RGL-BLK-004` is open.

**And the CI gate is red too** — for at least 30 consecutive runs since 2026-08-10, with 196 of
230 database test files never executing in CI at all (§9.5, `RGL-BLK-005`). The same reasoning
applies and the same conclusion follows: it is a defect found *by* Step 16's own baseline, not a
missing prerequisite, so entry stands — but no lane may report a CI gate as passing on the
strength of a local run.

**Verdict: `READY`.** `RGL-392` is `READY`; `RGL-393` … `RGL-412` are `BLOCKED` on their own
sequential upstream (§5).

---

## 4. Release states (Prompt 391 step 4)

Fixed by Prompt 391 step 4 and `390_RELEASE_GO_LIVE_README.md`'s "Runtime states". No state is
invented and none is renamed.

| State | Meaning | Set by |
|---|---|---|
| `RC_FROZEN` | The release candidate checkpoint, dependency set, schema state, test matrix and change window are frozen and immutable | `RGL-392` only |
| `UAT_READY` | A UAT environment exists, is loaded with valid non-real data, and evidence capture is prepared | `RGL-400` only |
| `UAT_ACCEPTED` | Named business acceptors have signed off the critical end-to-end flows | `RGL-400`; **requires a human acceptor — no agent may set this** (§7.2) |
| `GO_DECIDED` | A go decision is recorded with evidence, residual risk, approvals and named authority | `RGL-404` only |
| `PRODUCTION_DEPLOYED` | Production carries the approved candidate, deployed under the approved change window | `RGL-405` only |
| `POST_DEPLOYMENT_VALIDATED` | Production passed health, data, tenant, finance, API, file, job, observability and user-visible checks | `RGL-406` only |
| `HYPERCARE_ACTIVE` | Hypercare is running with intake, routing, monitoring, escalation and communication live | `RGL-408` only |
| `PIR_COMPLETE` | The post-implementation review is complete | `RGL-409` only |
| `RELEASE_GO_LIVE_VERIFIED` | Every mandatory Step 16 gate passes and no unresolved critical/high blocker remains | **`RGL-412` only** — no other prompt in this range may set it |
| `NO_GO` | Release or production go-live must not proceed | `RGL-404` or `RGL-412` |
| `ROLLED_BACK` | Deployment or candidate state returned to a trusted checkpoint | `RGL-407` |

Plus the two range-level states this document uses for its own bookkeeping:
`RELEASE_GO_LIVE_IN_PROGRESS` (set by this checkpoint) and `RELEASE_GO_LIVE_BLOCKED` (set by any
lane that hits a missing mandatory prerequisite, per Prompt 391's completion gate).

**A state that was not actually reached is never recorded as reached.** `PRODUCTION_DEPLOYED` in
particular is **not** satisfied by §2.1's pre-existing auto-deployment: that deployment carries
no approved candidate and no go decision. See `RGL-BLK-001`.

---

## 5. The WBS (Prompt 391 step 3)

22 rows. Owner is Claude Code (runtime build agent) on every row — this build's standing
convention. Dependency is **hard and sequential** unless stated: Step 16 is on `AGENTS.md`'s
**never-batch** list ("Never batch … Step 16 release (390–412) … prompts"), so **each lane runs
solo with its own full Tier A + Tier B + Tier C round**. Batch size is 1, always, for all 22.

Environment column uses §10's posture vocabulary. "Evidence" is the runtime build log every
prompt's own header fixes; additional required outputs are named where the prompt names them.

| # | Task ID | Lane | Capability | Dep | Environment / posture | Evidence | Approval gate | Rollback | State |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `CG-S16-RGL-001` | `RGL-391` | Release Go-Live WBS Runtime Kickoff | `CG-S15-HDN-021` | Repository only | this file | none (kickoff may not approve anything) | `git revert` this commit | **`COMPLETED`** this checkpoint |
| 2 | `CG-S16-RGL-002` | `RGL-392` | Release Candidate Freeze | 1 | Repository only | `RGL-392.md` | **`RC_FROZEN` set** for `RC-2026.08.25-1` | `git revert`; re-freeze | **`COMPLETED`**, Tier C pending |
| 3 | `CG-S16-RGL-003` | `RGL-393` | No-New-Feature Rule | 2 | Repository + GitHub | `RGL-393.md` | gate verdict **`PARTIAL`** | `git revert` | **`COMPLETED`**, Tier C pending |
| 4 | `CG-S16-RGL-004` | `RGL-394` | Defect Triage | 3 | Repository + ledgers | `RGL-394.md`, `RELEASE_DEFECT_LEDGER.md` | severity rulings binding on `RGL-404` | `git revert` | **`READY`** |
| 5 | `CG-S16-RGL-005` | `RGL-395` | Full CI Gate | 4 | CI (real) + local | `RGL-395.md` | none | `git revert` | **`COMPLETED`** |
| 6 | `CG-S16-RGL-006` | `RGL-396` | Clean Database Rebuild | 5 | Disposable Postgres (real) | `RGL-396.md` | none | disposable target; nothing to roll back | **`COMPLETED`** |
| 7 | `CG-S16-RGL-007` | `RGL-397` | Migration Validation | 6 | Disposable Postgres (real) + live schema read-only | `RGL-397.md` | none | disposable target | **`COMPLETED`** |
| 8 | `CG-S16-RGL-008` | `RGL-398` | Seed Validation | 7 | Disposable Postgres (real) + live project read-only | `RGL-398.md` | none | disposable target | **`COMPLETED`** |
| 9 | `CG-S16-RGL-009` | `RGL-399` | Staging Deployment | 8 | **No staging tier exists** — see §7.1 | `RGL-399.md` | none | Vercel instant rollback (preview only) | **`COMPLETED`** (operator-accepted gap, §3.4 addendum) |
| 10 | `CG-S16-RGL-010` | `RGL-400` | UAT Deployment | 9 | **No UAT tier, no acceptors** — see §7.2 | `RGL-400.md` | `UAT_READY`; `UAT_ACCEPTED` **needs a human** | n/a | **`COMPLETED`** (operator-accepted gap, §3.4 addendum) |
| 11 | `CG-S16-RGL-011` | `RGL-401` | Smoke Test | 10 | Live production URL (real) + local Playwright | `RGL-401.md` | none | n/a (read-only probes) | **`COMPLETED`** |
| 12 | `CG-S16-RGL-012` | `RGL-402` | Penetration Test Evidence | 11 | Live production URL + live Supabase (real, read-only/negative) | `RGL-402.md` | none | n/a | **`COMPLETED`** (operator-accepted external-pentest gap, §3.4 addendum) |
| 13 | `CG-S16-RGL-013` | `RGL-403` | Performance Evidence | 12 | Disposable Postgres + live URL (real) | `RGL-403.md` | budgets may force `NO_GO` | n/a | **`COMPLETED`** |
| 14 | `CG-S16-RGL-014` | `RGL-404` | Go/No-Go Report | 13 | Repository (decision artifact) | `RGL-404.md`, `GO_NO_GO_REPORT.md` | **sets `GO_DECIDED` or `NO_GO`** | decision reversible by a later dated ruling | **`GO_DECIDED`** (after the operator's own `RGL-BLK-001` + tracked-gap overrides; see `GO_NO_GO_REPORT.md`'s own addenda) |
| 15 | `CG-S16-RGL-015` | `RGL-405` | Production Deployment | 14 | Vercel production (real) — **gated on 14** | `RGL-404.md` §12A (no separate `RGL-405.md` — recorded as an addendum) | `PRODUCTION_DEPLOYED` | Vercel instant rollback — see §11.2, target updated at `RGL-407` | **`PRODUCTION_DEPLOYED`** (2026-08-27, PR #69, commit `c11c616`; production has since advanced through 8 further Track B batch merges, most recently `c77d479`) |
| 16 | `CG-S16-RGL-016` | `RGL-406` | Post-Deployment Validation | 15 | Live production (real) | `RGL-404.md` §12A (no separate `RGL-406.md` — recorded as an addendum) | `POST_DEPLOYMENT_VALIDATED` | triggers `RGL-407` on failure | **`POST_DEPLOYMENT_VALIDATED`** (2026-08-27; re-confirmed live at `RGL-407`, 2026-08-28, against the current production state) |
| 17 | `CG-S16-RGL-017` | `RGL-407` | Rollback Decision | 16 | Repository + Vercel/Supabase (real) | `RGL-407.md`, `docs/runbooks/deployment-rollback.md` (serves this row's own planned `ROLLBACK_DECISION_TREE.md` name — see §12) | authority-bound | is the rollback path | **`VERIFIED`** — no rollback indicated |
| 18 | `CG-S16-RGL-018` | `RGL-408` | Hypercare | 17 | Repository + live monitoring | `RGL-408.md`, `docs/runbooks/hypercare.md` | `HYPERCARE_ACTIVE` (evidence-backed; escalation-ladder staffing `NOT_YET_STAFFED`, disclosed) | n/a | **`VERIFIED`** — no active incident found |
| 19 | `CG-S16-RGL-019` | `RGL-409` | Post-Implementation Review | 18 | Repository | `RGL-409.md` | `PIR_COMPLETE` | n/a | **`PIR_COMPLETE`** — delivery/quality/data/performance/adoption/support/incidents reviewed; improvement backlog consolidated; `ISS-2026-284` addressed |
| 20 | `CG-S16-RGL-020` | `RGL-410` | Release Go-Live Integrated Verification | 19 | All of the above, one lineage | `RGL-410.md`, `RELEASE_READINESS_MATRIX.md` update | none | `git revert` | **`VERIFIED`** — all gates re-run fresh at one checkpoint; one mixed-checkpoint drift found and reconciled (`BLOCKER_LEDGER.md`) |
| 21 | `CG-S16-RGL-021` | `RGL-411` | Release Go-Live Documentation Handoff | 20 | Repository | `RGL-411.md` | none | `git revert` | **`VERIFIED`** — release notes authored, all reconciliation items checked current, Step 17 eligibility blocker (`RGL-BLK-001`) named explicitly in `HANDOFF.md` |
| 22 | `CG-S16-RGL-022` | `RGL-412` | Release Go-Live Closure Verification | 21 | Independent re-verification of all | `RGL-412.md`, `RELEASE_GO_LIVE_CLOSURE_REPORT.md` | **sets `RELEASE_GO_LIVE_VERIFIED` or a closure state** | `git revert` | **`RELEASE_GO_LIVE_PARTIALLY_COMPLETE`** — all 20 required-verification items disposed of explicitly. **Step 17 later made `ELIGIBLE`, same day, by explicit operator override addendum** (§13 above, `RELEASE_GO_LIVE_CLOSURE_REPORT.md`'s own addendum) — `RGL-BLK-001`'s mechanism remains unfixed, only its disposition changed |

### 5.1 Dependency graph

Strictly linear, `1 → 2 → … → 22`. No parallelism is authorized anywhere in this range, for
three independent reasons, any one of which is sufficient:

1. `AGENTS.md` "Execution cadence" lists Step 16 (390–412) under **Never batch**.
2. Each prompt's own header states *"Do not begin until Prompt 391 marks this task `READY`"*,
   and §36's "only the execution index may release `<NEXT>` … after this task is `VERIFIED`"
   clause applies unnarrowed here — `CON-015`'s within-batch relaxation is scoped to batches,
   and this range has none.
3. The content genuinely serializes: a go decision (`RGL-404`) that predates its own evidence
   (`RGL-395`…`403`) is not a decision, and a production deployment (`RGL-405`) that predates
   its go decision is precisely `RGL-BLK-001`.

### 5.2 Release candidate identity — frozen at `RGL-392`

**`RC-2026.08.25-1`**, candidate commit `9d8a71daf060b46d34d183b53e598578d6833c68`. Its
*shippable content* (everything outside `docs/`) is byte-identical to `568be15` (`HDN-387`) —
verified, not assumed. No release tag exists or was created; creating one would imply a promotion
decision only `RGL-404` may make. Dependency-set, schema and test-matrix hashes: `RGL-392.md`
§1–§4.

**The frozen test matrix is RED**, and is frozen red. Full detail `RGL-392.md` §4.

### 5.3 Release-candidate lineage rule

Every lane from `RGL-392` onward cites evidence produced **at or after** the frozen candidate
and against **one** compatible checkpoint. `RGL-410` and `RGL-412` must reject mixed-checkpoint
evidence outright — the same rule Step 15 §11.1 imposed on `HDN-386`/`HDN-389`, and for the same
reason.

---

## 6. Environment matrix (Prompt 391 step 5)

Derived from live provider state this checkpoint (§2.1), not from
`docs/architecture/11_DEVOPS_WORKSTREAM.md`'s target-state design. Where the design names a
tier that does not exist, the row says so.

| Axis | Local | Preview (Vercel) | Staging | UAT | Production |
|---|---|---|---|---|---|
| Exists? | **Yes** | **Yes** — per-branch, automatic | **No** | **No** | **Yes** |
| Host | developer machine | Vercel `cargogrid-app` | — | — | Vercel `cargogrid-app`, `target: production` |
| URL | `127.0.0.1:3000` | `cargogrid-<hash>-saiki-tech.vercel.app` | — | — | `cargogrid-app.vercel.app` (+2 aliases) |
| Trigger | manual | push to any non-`main` branch | — | — | **push/merge to `main`, automatic, ungated** (`RGL-BLK-001`) |
| Database | disposable local Postgres 16.13 | *unset or shared — unproven, `RGL-399` owns proving it* | — | — | **unreachable from the app** (`/api/ready` 503, `RGL-BLK-002`) |
| Secrets | `.env.local`, typed by `scripts/env/schema.ts`, validated by `pnpm run preflight` | Vercel project env (contents not read by this checkpoint) | — | — | Vercel project env (contents not read by this checkpoint) |
| `CARGOGRID_ENV` | `local` | *unproven* | — | — | *unproven* — `RGL-399` owns proving it, since `scripts/env/validate.ts` enforces a loopback/non-loopback symmetry against this value |
| Migrations | `bash scripts/db-tests/run.sh`, 333 applied to a fresh DB each run | — | — | — | **applied out-of-band** to the live Supabase project; no deploy-time migration step exists anywhere |
| Feature flags | none exist (§2) | none | — | — | none |
| Observability | none | Vercel build/runtime logs | — | — | Vercel runtime logs; in-app alerting partial (`HDN-BLK-027`/`028`) |
| Access control | n/a | **SSO-gated** | — | — | **public, unauthenticated** |
| Backup | n/a | n/a | — | — | Supabase-managed; restore path `PARTIAL` (`HDN-BLK-030`) |
| Support/comms | n/a | n/a | — | — | **none defined** — `RGL-408` owns it |

**Secrets discipline for every Step 16 lane.** No lane may read, echo, screenshot, or paste a
provider credential, service-role key, signed URL or Vercel environment-variable *value* into
any build log, ledger or commit. Environment variables are referenced **by name and presence
only**. `pnpm run security:check` is a Tier A gate on every lane precisely so a slip is caught
mechanically, not by good intentions. This is Prompt 412 required-verification item 19, and it
is a Tier B walk item from `RGL-392` onward, not a closing check.

---

## 7. The three gates that cannot be honestly executed as written, stated before any lane starts

Prompt 391 step 6 requires the no-go policy up front; §22 of every capability prompt requires an
alternative flow when a gate has no real subject. Naming these now prevents the far worse
outcome of a lane discovering it mid-execution and improvising a claim.

### 7.1 `RGL-399` Staging Deployment — no staging tier exists

There is no staging Vercel project, no staging Supabase project, no staging database, no
staging URL. Vercel **preview** deployments are per-branch, SSO-gated, and — unproven but
likely — point at the *same* single Supabase project as production. A preview deployment is
therefore a **substitute** for a staging tier, and a poor one: it does not isolate data, so
"deploy to staging and exercise it" cannot be done without touching the same database
production uses.

**Authorized postures for `RGL-399`, and no others:** (a) execute against a preview deployment
with the substitution and its exact limits disclosed, after first *proving* what database the
preview points at; or (b) record a **tracked gap** with owner, the exact missing infrastructure,
and the stated risk. **Fabricating a staging deployment record, or relabelling the production
deployment as staging, is prohibited.**

### 7.2 `RGL-400` UAT Deployment / `UAT_ACCEPTED` — no acceptor exists, and no agent may substitute for one

There is no UAT environment and, more fundamentally, **no named business acceptor anywhere in
this repository**. Prompt 412 required-verification item 8 demands UAT acceptance for
lead-to-cash, shipment-to-billing, finance, WMS, portal, loyalty, ticket and tenant-isolation
flows.

**`UAT_ACCEPTED` is a human business sign-off. This agent cannot produce one, and must not
simulate one.** An agent-run end-to-end pass is evidence that the flow *works*; it is not
evidence that a business *accepts* it. Conflating them would be the single most damaging false
claim available in this range.

**Authorized posture for `RGL-400`:** prepare and document everything an acceptor would need —
environment plan, representative non-real data, roles, scenario catalogue, evidence-capture
method — set `UAT_READY` if and only if that is genuinely true, and record `UAT_ACCEPTED` as a
**tracked gap requiring a named human**, escalated to the operator. `RGL-404` and `RGL-412` must
treat a missing `UAT_ACCEPTED` as an **open go-live gate**, not a formality.

### 7.3 `RGL-405` Production Deployment — the deployment already happens, ungated

The honest work here is **not** "execute a production deployment": production already
auto-deploys from `main`. The work is to bring that path under the control Step 16's own
non-negotiable gate requires — i.e. disposition `RGL-BLK-001` — and only then record a
deployment against an approved candidate and a recorded go decision.

**A `PRODUCTION_DEPLOYED` state may not be back-dated onto the pre-existing
`dpl_4vgM6mR6Y5xpA3UfGxsdY2WFCs4U` deployment.** That deployment predates the candidate freeze
and every go decision.

---

## 8. Defect severity, no-go policy, and accepted-risk handling (Prompt 391 step 6)

### 8.1 Severity model

Sourced from `390_RELEASE_GO_LIVE_README.md`'s "Non-negotiable gates" and Prompt 394 §5. A
finding's severity is set by **impact if it reached a real tenant**, never by how hard it is to
fix.

| Severity | Definition | Go-live effect |
|---|---|---|
| **Sev-1 / Critical** | Tenant isolation breach, authentication/authorization bypass, financial mis-posting, data loss or corruption, migration failure, no working rollback, or a production outage | **Absolute no-go.** Never accepted, never risk-accepted, at any authority |
| **Sev-2 / High** | A core business flow broken with no workaround; a security control absent where a shipped feature implies it; performance outside an agreed budget; a support/monitoring gate absent at go-live | **No-go unless** formally accepted under §8.2 **by `RGL-404` against the production bar** |
| **Medium** | A non-core flow degraded, a workaround exists, or a disclosed coverage gap with a named owner | Does not block; must be disclosed in `RGL-404` and `RGL-412` |
| **Low** | Cosmetic, documentation, or an already-owned tracked gap | Does not block; listed |

### 8.2 Accepted-risk handling — five conditions, all required

Mirrors `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §8.2 exactly, with
condition 5 re-pointed at this range's own authorities and condition 4 added by this checkpoint
for the reason §3.1 gives.

An accepted risk is valid only when **all five** hold. Anything less is an unowned blocker:

1. Severity is **High or below** — a Critical/Sev-1 is never accepted.
2. An **explicit written ruling** exists stating why the risk is accepted, what was considered
   and rejected, and what the compensating control is.
3. A **named owner** and a named future task carry it.
4. **If the item is an inherited Step 15 `ACCEPTED_EXCEPTION`, the ruling states explicitly
   that it was re-examined against the production go-live bar and why it still holds there.**
   A Step 15 acceptance is never carried into a Step 16 go decision by reference alone (§3.1).
5. It is accepted at **`RGL-404` or `RGL-412` only** — never by the lane that found it, and
   never by this kickoff.

**A gate that could not be run is not a passing gate.** It is a tracked evidence gap with an
owner, an exact missing command or missing infrastructure, and a stated risk. **"Not triggered"
is never reported as "verified", and "not deployable here" is never reported as "deployed".**

### 8.3 Blocker ledger — opened by this checkpoint

The live register is `docs/build-log/release-go-live/BLOCKER_LEDGER.md` (created this
checkpoint). Three entries exist at kickoff. **This checkpoint registers them; it does not and
may not rule on them** (§8.2 condition 5).

| ID | Severity (proposed) | Summary | Owner |
|---|---|---|---|
| `RGL-BLK-001` | **Critical (release governance)** | Production auto-deploys from `main` with no go/no-go gate, defeating Step 16's own non-negotiable gate. Already fired at least twice; still armed for every future merge | `RGL-404`, mechanism work at `RGL-405` |
| `RGL-BLK-002` | **High** | Production is publicly reachable, unauthenticated, and degraded — `/api/ready` 503 `database_unreachable`, `/api/v1/status` 500 | `RGL-399` (root-cause the env), `RGL-406` (validate the fix) |
| `RGL-BLK-003` | **High (inherited, aggregate)** | The 17 Step 15 `ACCEPTED_EXCEPTION` High items, accepted against Step 15's closure bar with owner `Step 16`, have not been re-ruled against a production bar | `RGL-404`, per §8.2 condition 4 |
| `RGL-BLK-004` | **High** | `_calc_vendor_kpi_rate_validity`'s denominator collapses to zero for sub-24-hour windows, contradicting its own documented guarantee and failing `db:test` for 3 hours of every 24. Found live by this checkpoint's own baseline (§9.4) | `RGL-394` |
| `RGL-BLK-005` | **Critical (release-gate integrity)** | **CI has been red on `main` for at least 30 consecutive runs since 2026-08-10.** The `db` job aborts at test file **34 of 230**, so **196 database test files have never run in CI** — every RLS, tenant-isolation, RBAC and financial-posting assertion they carry is unenforced. Root cause: `pg_read_file()` reads the *server's* filesystem, but the race helper writes to the *client's* — identical locally, different in CI's Docker service container. Found by querying the Actions API (§9.5) | `RGL-395` |

Plus one process finding registered in `docs/runtime/KNOWN_ISSUES.md`, not a release blocker:

| ID | Severity | Summary |
|---|---|---|
| `ISS-2026-284` | Medium | A load-bearing environment fact ("no deployed environment") drifted for 13 days across 21 `VERIFIED` checkpoints because no checkpoint re-verified it against the provider. §2.1 |

---

## 9. Baseline gate status at this checkpoint

Run fresh this session on the frozen tree. Exact results, including the day the suite ran —
never a carried-forward figure.

| Gate | Result | Notes |
|---|---|---|
| `pnpm install --frozen-lockfile` | **clean**, exit 0 | No lockfile drift |
| `pnpm run typecheck` | **0 errors** | |
| `pnpm run lint` | **0 errors / 337 warnings** | Identical class and identical count to Step 15's own closure baseline — unchanged by this checkpoint |
| `pnpm run test` | **5443 / 5444 pass, 1 fail** | **Disclosed, not hidden — see §9.1.** The one failure is the known checkpoint-state-dependent `checkWorktreeCollision` class |
| `bash scripts/db-tests/run.sh` | **FAILED — 202 / 230 files passed, 1 failed, 27 never ran** | **A real, previously-unregistered product defect, found by this run — see §9.4 and `RGL-BLK-004`.** `ALL PASSED` was never printed. Step 15's "230/230" figure is **not** carried forward |
| `pnpm exec next build` | **clean**, exit 0, 249 route entries | Run to establish the baseline for the range, not because this checkpoint touches `app/` |
| `pnpm run docs:check` | **passed** | link resolution, canonical files, ADR index, HANDOFF/TASK_LEDGER coherence |
| `pnpm run security:check` | **passed** | No secret-shaped pattern in any tracked file |
| `pnpm run standards:check` | **passed** | No suppression-governance violation |
| `pnpm run git:check-paths` | **passed** | 0 files checked at the time of the run (pre-commit, clean tree) |
| **CI (GitHub Actions), `main` @ `2670cb5`** | **FAILED — and has failed on all 30 most recent runs since at least 2026-08-10** | **§9.5, `RGL-BLK-005`.** Checked against the Actions API, which no prior checkpoint did. `quality` and `e2e` pass; `db` aborts at test file **34 of 230**, leaving 196 files unenforced in CI |
| `check-commit-message.ts` | **passed** on this checkpoint's commit; **fails on every recent checkpoint commit** | §9.6 |

### 9.1 The one Tier A failure, disclosed in full

```
not ok 2 - the current branch is reported as diverged from origin/main
  location: 'scripts/git/check-worktree-collision.test.ts:36:3'
  error: 'expected claude/step-16-prompt-390-412-okbd6v to have commits ahead of origin/main'
```

**Root cause, verified not assumed:** the test asserts against this repository's *real* git
state. At the moment it ran, this branch had **zero commits ahead of `origin/main`** (§2), so
the assertion is factually correct in reporting no divergence — the test is right and the tree
is simply at a pre-commit state. It resolves the moment this checkpoint's own commit exists.

**This is a known, registered class, not a new defect.** The identical failure was disclosed at
the Phase 8 kickoff, the Phase 9 kickoff, and `HDN-369` (Step 15 kickoff, §9 of that document's
own baseline table). Re-verified green after this checkpoint's commit — see §9.3.

**It is not treated as "pre-existing, therefore ignorable".** It is a real design weakness in
the test (it couples a unit test to transient repository state) and is the reason
`ISS-2026-002`'s own guard behaves differently pre- and post-commit. `RGL-395` (Full CI Gate)
owns deciding whether that coupling is acceptable for a release gate, since a CI run on a
freshly-branched PR hits exactly this state.

### 9.2 Day-of-week disclosure (mandatory every checkpoint in this range)

Carried forward from Step 15 §9's own standing requirement, because the underlying fixture-flake
class is unchanged and unfixed.

This checkpoint ran on **Tuesday 2026-08-25**, local time UTC+07:00.

| Issue | Trigger dimension | Exercised? |
|---|---|---|
| `ISS-2026-135` (`hris-shift-roster-scheduling.sql`) | day-of-week | **Yes — Tuesday. Did not fire** |
| `ISS-2026-103`/`115` (`hris-overtime-timesheet.sql`, fixed) | day-of-week | **Yes — Tuesday. Did not fire** |
| `ISS-2026-077` (`hris-leave-permit-business-trip.sql`) | wall-clock **and** day-of-week | **Partly** — the day half was in play; the wall-clock half was uncontrolled |
| `ISS-2026-154` (`hris-attendance.sql`) | ~1-hour real-UTC window after each day's 21:00 UTC boundary | **Not controlled for** — the suite ran outside it, but this checkpoint did not pin the clock |

**Verdict: the class was `PARTIAL`ly exercised.** A green suite on one Tuesday is not evidence
of day-independence. Every following lane in this range must repeat this distinction
explicitly; `RGL-395` owns whether a release gate may depend on a suite with this property.

### 9.3 Post-commit gate re-run

Recorded in `RGL-391.md` §7, after this checkpoint's commit exists — the only point at which the
§9.1 class can be honestly re-tested.

### 9.4 The `db:test` failure — a real defect, found by this baseline, not inherited

**This is the most consequential technical finding of this checkpoint, and it is a genuine
product defect rather than a fixture problem.** Full entry: `RGL-BLK-004` in
`docs/build-log/release-go-live/BLOCKER_LEDGER.md`. In short:

`app._calc_vendor_kpi_rate_validity` builds its denominator as
`generate_series(window_start::date, (window_end - interval '1 day')::date, interval '1 day')`.
For a sub-24-hour window that expression can produce an **empty** series, so `window_days = 0`,
so `is_computable = false` — **contradicting the function's own `comment on function`, which
guarantees "window_days is always > 0"**. A real caller asking for a short intraday window
silently gets "no data" instead of the real 0% the design promises.

Empirically evaluated across all 24 hours on the live local Postgres this checkpoint: the
denominator collapses to `0` at hours **01, 02 and 03** of the session timezone, and is `1`
otherwise. The suite ran at **02:32 UTC**, inside that band, and the assertion at
`scripts/db-tests/procurement-vendor-performance.sql:978` failed.

**Three consequences that bind the rest of this range:**

1. **Step 15's `230/230 ALL PASSED` cannot be carried forward.** It was true at the hour it ran.
   The suite is not hour-independent, which is exactly what Step 15's own §9 day-of-week
   disclosure kept warning about. §9.2's `PARTIAL` verdict is not a formality.
2. **`run.sh` aborts the whole suite** (`set -euo pipefail`), so a single hour-dependent failure
   hides the state of **27 test files that never ran**, and leaves the disposable database
   undropped. `RGL-395` owns whether a release gate may behave this way.
3. **Not fixed here.** Pre-existing (migration dated 2026-07-30), and `AGENTS.md` restricts this
   kickoff to task-caused failures; Prompt 391's charter is zero code, zero migration. Owner
   `RGL-394`.

### 9.5 The CI gate has been red for 30 consecutive runs, and nobody looked

**This is the most serious integrity finding of the checkpoint.** Full entry: `RGL-BLK-005`.
Found by querying the GitHub Actions API — not by reading `.github/workflows/ci.yml`, which is
what every prior checkpoint did.

**Every one of the 30 most recent CI runs failed**, `push` and `pull_request` alike, continuously
from at least **2026-08-10** through the current `main` HEAD `2670cb5` (run 114, conclusion
`failure`). During that same window 21 Step 15 checkpoints reported green gate suites.

**Both things are true, and the distinction is the whole finding: the gates were green
*locally*; the *CI* gate — the one Prompt 412 item 4 actually requires — was red the entire
time.** Nothing in the reporting chain distinguished "I ran the suite on my machine" from "the
repository's release gate passed", so the difference stayed invisible.

**Current root cause, diagnosed exactly.** Only the `db` job now fails (`quality` and `e2e` pass,
so `HDN-386`'s lockfile fix genuinely worked):

```
psql:scripts/db-tests/advanced-tms-wms-outbound.sql:850: ERROR:
  could not open file "/tmp/cargogrid-wms-outbound-race-a.out": No such file or directory
```

`wms-picking-concurrency-helper.sh` runs via psql's `\!` on the **client** and writes to the
client's `/tmp`; the assertion reads it back with **`pg_read_file()`, which reads the *server's*
filesystem**. Same host locally → passes. Docker service container in CI → the file is genuinely
not there. This is the **inverse** of the CI-mirrors-hosted property Step 15 §2.2 made a standing
constraint — the same class of divergence, sitting in the test harness the whole time.

**Why it is Critical and not merely a broken test.** `advanced-tms-wms-outbound.sql` is **file 34
of 230**, and `run.sh` uses `set -euo pipefail`:

> **196 of 230 database test files have had zero CI enforcement for the entire window** — every
> migration-integrity, RLS, tenant-isolation, RBAC and financial-posting assertion they carry.

A gate that runs 15% of its suite and dies, while every report says `230/230 ALL PASSED`, is
functionally a disabled test suite. **No product defect is proven by this** — those 196 files pass
locally, and the WMS concurrency guarantee itself is proven (only the loser's-output assertion
fails, after the winner/confirmation/movement assertions all pass). The defect is that the release
gate this range depends on has been non-functional for weeks. Owner `RGL-395`; binding severity
ruling `RGL-394`.

**Consequence for this range, binding:** `RGL-395` cannot certify the CI gate, and `RGL-404`
cannot reach a go decision, until CI is genuinely green on the release candidate — and "genuinely"
means verified against the Actions API, not against a local run.

### 9.6 A second, smaller CI-convention drift, disclosed with it

`scripts/git/check-commit-message.ts` enforces `docs/git/GIT_STRATEGY.md` §1.2's documented
subject-line convention, `agent: <verb> <description> (<task-id>, Prompt <n>)`, and CI runs it on
every PR head commit. **Every recent checkpoint commit fails it** — verified directly against
`3fe4bf6` (`HDN-389`), `00403cb` (`HDN-388`) and `568be15` (`HDN-387`), each rejected with
*"subject line must match `agent: <verb> <description>`"*.

This checkpoint's own first commit had the same shape and was **amended to comply** before
anything was pushed — following the repository's own written convention is correct regardless of
what recent history did. The drift itself is recorded rather than propagated, and is a `RGL-395`
input: either the convention is real and history drifted from it, or the convention is stale and
`GIT_STRATEGY.md` §1.2 should be amended deliberately. **Not registered as a separate blocker** —
it is a sub-case of `RGL-BLK-005`'s "nobody was reading CI" root cause, and folding it in is
more honest than inflating the count.

---

## 10. Execution posture — re-derived from current facts, replacing Step 15 §10

Step 15 §10's constraint ("a migrated database is not a running system") was correct for what
its author could see, and is now **partly obsolete** (§2.1). Restated for the facts that
actually hold:

| Posture | Meaning | Valid? |
|---|---|---|
| **Executed** | Really run against a real target, results observed firsthand | Yes — always preferred |
| **Executed against a substitute** | Run against the disposable database, a Vercel preview, or the live migrated project, with the substitution and its exact limits stated | Yes, **only** when the substitution is disclosed in the same sentence as the result |
| **Tracked gap** | Cannot be run here; recorded with owner, the exact missing command or infrastructure, and the stated risk | Yes — and it is **not** a pass |

**What changed in Step 16's favour:** a real running application now exists at a real public
URL. `RGL-401` (smoke), `RGL-402` (pen-test evidence), `RGL-403` (performance) and `RGL-406`
(post-deployment validation) can therefore be **Executed** against a genuine target, where Step
15 would have had to record tracked gaps. Each of those lanes must actually do so rather than
inherit Step 15's pessimism.

**What has not changed:** there is still no staging tier (§7.1), no UAT tier or acceptor
(§7.2), no deploy-time migration step, and no CI deploy pipeline. Those remain tracked gaps and
no lane may quietly upgrade them.

**A caution that applies to every lane using the live target.** The single live Supabase project
is, as far as this checkpoint can tell, *the same database production points at*. **No Step 16
lane may mutate live project data.** Anything schema- or data-affecting runs against a
disposable database. `RGL-397`, `RGL-398`, `RGL-402` and `RGL-403` must each state their target
explicitly before executing — the same discipline Step 15 imposed on `HDN-383`/`384`/`385`.

---

## 11. Test strategy, rollback, communication, hypercare and PIR plans

### 11.1 Test strategy

- **Baseline first, always.** Every lane re-establishes the Tier A baseline on its own tree
  before changing anything, so regression and pre-existing failure can be told apart with proof
  (`AGENTS.md`: "Separate pre-existing failures with baseline evidence").
- **Every repair carries a regression test**, or an explicit documented reason one is impossible.
- **Negative tests are mandatory** wherever a control is claimed: cross-tenant, denied role,
  expired grant, replayed idempotency key, revoked session, malformed payload, unauthenticated
  production request.
- **Never** disable, skip, quarantine, or weaken a test, lint rule, typecheck, RLS policy or
  validation to make a gate pass. This is Prompt 412 required-verification item 4.
- **Mixed-checkpoint evidence is invalid** at `RGL-410` and `RGL-412` (§5.3).

### 11.2 Rollback plan (Prompt 391 step 8; `RGL-407` owns the full decision tree)

| Scope | Mechanism |
|---|---|
| Any Step 16 checkpoint | `git revert` the checkpoint's single commit. One commit per prompt is the standing rollback granularity |
| A repair migration | Additive and reversible by design; a forward-fix migration, **never** an edit of an applied file |
| A production deployment | **Vercel instant rollback** to a prior `READY` production deployment. The current one, `dpl_5HVE4jExwWFQrRGw3Xva4uQGSKZd` at `d343eb7` (Track B Batch 7's own merge — the prior `target: production` deployment before Batch 8's own `c77d479`), is the standing rollback target, `isRollbackCandidate: true` confirmed live at `RGL-407` (2026-08-28) — superseding the `dpl_4vgM6mR6Y5xpA3UfGxsdY2WFCs4U`/`2670cb5` value this table previously carried, itself stale since `RGL-405` |
| The live database | **No Step 16 lane mutates live project data** (§10). Schema restore path is `PARTIAL` — `HDN-BLK-030`, untested for Storage/Auth/hosted-project |
| Last known good checkpoint | `c77d479` (merge of PR #77, Track B Batch 8) as of `RGL-407` |

**Known limit, disclosed now rather than discovered at `RGL-407`:** a Vercel rollback reverts
*application code only*. It cannot revert an applied database migration, because no deploy-time
migration step exists (§6) — migrations are applied out-of-band. A candidate that ships both a
code change and a migration therefore has **no single-action rollback**. `RGL-405` and `RGL-407`
must plan for that explicitly. **`RGL-407`'s own resolution**: `docs/runbooks/deployment-
rollback.md` (new) makes this explicit as its own §4.1 closing note — a Vercel-only rollback that
leaves a newer schema in place must be checked for backward-compatibility with the reverted code,
or the schema issue must be forward-fixed first (§4.2 of that runbook), rather than assuming a
single Vercel action is ever sufficient when a migration shipped in the same release.

### 11.3 Communication plan (Prompt 391 step 5/8)

| Audience | Channel | Owner | Status |
|---|---|---|---|
| Operator | this session's chat + `docs/runtime/HANDOFF.md` | every lane | **active** |
| Future runtime agent | this file + `HANDOFF.md` + the per-lane build logs | every lane | **active** |
| Business acceptors | **none exist** (§7.2) | `RGL-400` | **tracked gap** |
| End users / tenants | **none exist and no channel is defined** | `RGL-408` | **tracked gap** |
| On-call | `docs/runbooks/on-call-ownership.md` | `RGL-408` | exists as a document; no rota is staffed |

No lane may invent a customer-communication record for an audience that does not exist.

### 11.4 Hypercare plan (owner `RGL-408`, real artifact: `docs/runbooks/hypercare.md`)

Every required element from this section's own original skeleton is now addressed, honestly:
incident intake path and support tier/routing model (reuses `on-call-ownership.md` §5, unchanged);
monitoring and alert destinations (§3 of the new runbook — live-checked this checkpoint, 5
historical error groups confirmed non-recurring since 2026-08-25, zero new incident); adoption
tracking (confirmed correctly empty — no real tenant onboarded yet); known-issue publication
(`docs/runtime/KNOWN_ISSUES.md` itself, 102 items, continuously maintained); RCA process (reuses
`on-call-ownership.md` §5's own binding requirement, unchanged). **Escalation ladder with named
humans remains genuinely empty — `NOT_YET_STAFFED`, a real, disclosed, human-only gap this session
cannot close (no tool available can hire, assign, or roster a person into an on-call rotation),
matching this section's own original honest framing rather than papering over it.**

### 11.5 PIR plan (owner `RGL-409`, real artifact: `docs/build-log/release-go-live/RGL-409.md`)

Every required coverage element from this section's own original skeleton is now addressed: delivery
(19 of 22 WBS lanes complete, 0 dropped without a recorded disposition), quality (backlog 147 → 102
across 8 Track B batches, 0 Critical/6 High remaining, a derived origin-phase breakdown), data
(`ISS-2026-300` migration-ledger drift carried forward, not silently dropped), performance (`RGL-403`
evidence plus `ISS-2026-297` carried forward), adoption (confirmed still empty), support (two
Track-C staffing gaps named), incidents (zero this range), and a consolidated improvement backlog
with owners. **`ISS-2026-284` (§8.3) is addressed directly** (`RGL-409.md` §10) — not as a new fix,
but as a process defect closed by the demonstrated practice of re-verifying live state at every
checkpoint since it was found, exactly the mitigation a PIR is meant to confirm took hold.

---

## 12. Runbook checklist (owner `RGL-411`, evidence produced by the lane named)

Step 15 closed its own §11.4 checklist and left `docs/runbooks/README.md` as the authoritative
index (17 runbooks). Step 16's additional needs:

| Runbook | Current state | Lane that must produce/refresh its evidence |
|---|---|---|
| Release/cutover runbook | **does not exist** | `RGL-405` |
| Rollback decision tree | **exists**: `docs/runbooks/deployment-rollback.md` (new, `RGL-407`, 2026-08-28) — this row's own planning name, `ROLLBACK_DECISION_TREE.md`, is served by that file rather than a separately-named one, keeping one canonical runbook directory per this repository's own established naming-reconciliation convention (`ISS-2026-262`'s own precedent: the built equivalent under a different, more consistent name, not a missing file). Real Vercel rollback mechanics verified live; end-to-end execution honestly marked `NOT_YET_REHEARSED` (the file's own §7) | `RGL-407` |
| Hypercare / go-live support | **exists**: `docs/runbooks/hypercare.md` (new, `RGL-408`, 2026-08-28) — a real point-in-time hypercare check performed; escalation-ladder human staffing honestly marked `NOT_YET_STAFFED` | `RGL-408` |
| `docs/runbooks/deployment-migration-guard.md` | exists (`HDN-388`); has not been reconciled against the fact that a real deploy pipeline now exists | `RGL-405` |
| `docs/runbooks/on-call-ownership.md` | exists (`HDN-388`); every name slot is empty | `RGL-408` |
| `docs/runbooks/performance-capacity.md` | exists (`HDN-388`); no budget has been measured against a real deployed target | `RGL-403` |

---

## 13. Step 17 eligibility criteria and the release boundary

**No Step 17 final-validation work is performed anywhere in Prompts 391–412.** Step 16 freezes,
verifies, deploys, validates, supports and reviews. It does not validate the package.

**No production-ready, market-ready or GA claim may be made by any prompt in this range**
before `RGL-412`, and `RGL-412` may make one only on real evidence for every source-defined gate
(Prompt 412 required-verification item 18). This restates, and does not weaken, RPD-001/034/036
and Step 15 §12 condition 6.

Step 17 becomes eligible only when **all** hold:

1. `RGL-392` … `RGL-411` are all `VERIFIED` at one compatible release-candidate lineage.
2. `RGL-412` has run and set **`RELEASE_GO_LIVE_VERIFIED`**. **Prompt 412 is the only task
   authorized to set a Step 16 completion flag.**
3. Every non-negotiable gate in `390_RELEASE_GO_LIVE_README.md` passes — including *"no
   production deployment without recorded go decision"*, which `RGL-BLK-001` currently defeats.
4. Zero unresolved Critical/Sev-1. Every High/Sev-2 is either fixed with regression proof or is
   an accepted exception meeting all five conditions of §8.2 — **condition 4 included**, which
   means no inherited Step 15 acceptance passes by reference.
5. `RELEASE_GO_LIVE_CLOSURE_REPORT.md` exists in this directory and disposes of **all 20** of
   Prompt 412's required-verification items explicitly — each `PROVEN`,
   `PROVEN-with-disclosed-residual`, or explicitly ruled on. **Silence on an item is a closure
   defect.**
6. `RELEASE_GO_LIVE_VERIFIED` is not asserted as a GA/market-ready claim beyond what the
   evidence supports.

**If `UAT_ACCEPTED` cannot be obtained (§7.2), `RGL-412` may not silently drop Prompt 412 item
8.** It must rule explicitly — `RELEASE_GO_LIVE_PARTIALLY_COMPLETE`, `RELEASE_GO_LIVE_BLOCKED`,
or `RELEASE_GO_LIVE_NO_GO` — and say why. That is the honest outcome, and it is available.

**Addendum, 2026-08-28, after `RGL-412` closed at `RELEASE_GO_LIVE_PARTIALLY_COMPLETE`.** The
operator gave a fresh, explicit instruction extending the existing `RGL-404.md` §7 override to
cover condition 3 above, not only Step 16's own proceed decision — full record:
`RELEASE_GO_LIVE_CLOSURE_REPORT.md`'s own "Step 17 eligibility" addendum. `RGL-BLK-001`'s mechanism
remains genuinely unfixed; only its disposition changed. **Step 17 is now `ELIGIBLE`** — condition 3
is met by explicit operator risk-acceptance; conditions 1/4/5/6 were already met by `RGL-412`'s own
body, and condition 2 is treated as met on the same basis the closure report's own addendum states
(`RGL-412` ran and set a legitimate Step 16 completion flag per Prompt 412's own five defined
closure states, `RELEASE_GO_LIVE_PARTIALLY_COMPLETE` among them — condition 2's own literal text
anticipated only the clean `VERIFIED` outcome, not the range's own explicitly-provided alternative
states).

---

## 14. This checkpoint's own record

**Task:** `CG-S16-RGL-001` (Prompt 391). **State: `COMPLETED`** — first round. Tier C review
(4 independent adversarial lenses) is required before `VERIFIED`, per `AGENTS.md`'s never-batch
rule for this range.

**Scope discipline:** zero code, zero migration, zero schema change. This checkpoint writes
documentation and ledger rows only, exactly as `HDN-369` did for Step 15.

**Files written:**

- `docs/build-log/release-go-live/00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` (this file, new)
- `docs/build-log/release-go-live/BLOCKER_LEDGER.md` (new)
- `docs/build-log/release-go-live/RGL-391.md` (new — this checkpoint's own build log)
- `docs/runtime/TASK_LEDGER.md` (22 rows appended)
- `docs/runtime/CARGOGRID_BUILD_STATUS.md`, `CHANGE_MANIFEST.md`, `KNOWN_ISSUES.md`,
  `HANDOFF.md` (updated)

**Post-commit gate re-run** — recorded in `RGL-391.md` §7, including the §9.1 re-test that can
only be run once this checkpoint's commit exists.

**Next eligible prompt: `RGL-392` (`CG-S16-RGL-002`, Release Candidate Freeze)** — `READY`,
after this checkpoint's Tier C round closes `VERIFIED`.
