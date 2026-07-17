# ERROR_LEDGER.md

**Instance of:** `CG-AABPP-GOV-017`
**Instance version:** `0.2.0`
**Updated:** 2026-07-14T10:29:19+07:00
**Policy:** Record reproducible failures, failed gates, unsafe/unknown states, and recovery evidence. No secrets, tokens, or unredacted tenant data.

## 1. Error states and severity

Statuses: `OPEN`, `INVESTIGATING`, `ROOT_CAUSE_CONFIRMED`, `RECOVERY_IN_PROGRESS`, `RECOVERED`, `VERIFIED`, `ACCEPTED`, `SUPERSEDED`.

| Severity | Definition | Default effect |
|---|---|---|
| Sev-1/Critical | Tenant isolation, credential exposure, corrupt/imbalanced finance, destructive data loss, production outage, untrusted repo/DB | Stop affected work/release |
| Sev-2/High | Major flow unavailable, serious security/access defect, failed migration/restore, cross-module integrity failure | Block phase/release |
| Sev-3/Medium | Bounded defect or failed non-critical gate with safe workaround | Separate recovery task |
| Sev-4/Low | Minor tooling/docs/local issue without data/security impact | Track and schedule |

## 2. Error index

| Error ID | Task ID | Severity | Environment | Summary | Status | Root cause | Last good checkpoint | Owner | Record link |
|---|---|---|---|---|---|---|---|---|---|
| `ERR-2026-001` | `CG-S2-DISC-001-R1` | Sev-3/Medium | Repository / git `main` | Parallel-session merge corrupted the discovery baseline and duplicated persistent context | `RECOVERED` (verification VERIFIED) | Two concurrent agent branches ran Prompt 21 with no single-writer lock; merge concatenated both reports and both context sets | `d587445` | Runtime agent | this file §3 |
| `ERR-2026-002` | `CG-S3-ARCH-013..016`, `CG-S5-PH0-001..003` | Sev-2/High | Repository / GitHub PR #10 (was open, unmerged at detection) | A fully independent parallel session (branch `claude/sleepy-ride-4vxsk6`) redid Prompts 46–51, Phase 0 kickoff (80), and Prompts 81–82 with materially different content (different traceability item counts, different build-log directory convention) after diverging from the shared lineage at PR #8; its output sat in PR #10, not yet reconciled with this branch's (`agent/cargogrid-autonomous-build`) independent redo of the same range | `SUPERSEDED` by `ERR-2026-003` — **both PR #10 and PR #11 were subsequently merged into `main` without the operator ever recording a reconciliation decision here or in `HANDOFF.md`; see `ERR-2026-003`** | No enforced single-writer lock (`ISS-2026-002`) across scheduled/parallel routine invocations; two agent instances both continued the same autonomous build task from a shared ancestor without coordinating | `1802400` (this branch's HEAD at detection time) | Runtime agent / repo owner | this file §3 |
| `ERR-2026-003` | `CG-S3-ARCH-014..016`, `CG-S5-PH0-001..003` | Sev-1/Critical | Repository / `main`@`b7653cb` (and every branch cut from it since, including this one) | PR #10 and PR #11 were both merged into `main` (merge commits `a8a197f` then `b7653cb`) while `ERR-2026-002` was still `OPEN` and unresolved — no reconciliation decision was ever recorded. The merges did not conflict at the git level (each lineage inserted content the other side's history didn't touch line-for-line at the merge point), so git silently **concatenated** both divergent lineages' full deliverables into single files instead of reconciling them. Confirmed by direct inspection, not inference. | `RECOVERED` (2026-07-15) — operator authorized adoption of the internally-consistent Lineage A (607-item) copy; `docs/architecture/14..16_*.md` rewritten as single coherent documents, Lineage B duplicates removed, Prompt 82 re-verified against the 607 baseline. See §3 recovery record. | Same root cause as `ERR-2026-002` (`ISS-2026-002`, no enforced single-writer lock), compounded by merging both divergent PRs into `main` without performing the manual reconciliation `ERR-2026-002` explicitly said was required first | `origin/main`@`27389a4` (PR #8, last point both lineages agree) | Runtime agent / repo owner | this file §3 |
| `ERR-2026-004` | `CG-S6-PLT-002..017` (every capability from `PLT-105` onward) | Sev-1/Critical | Database / every migration from `20260716075355_create_tenants.sql` through `20260717090512_create_white_label.sql` (`PLT-105`..`117`) | PostgreSQL grants `EXECUTE` to the `PUBLIC` pseudo-role on every function by default at creation time; no migration in this repository's history ever revoked it. Because `PUBLIC` is implicitly held by every real role including `anon`, every function documented as "`service_role`-only" in its own migration's grant comment — `app.provision_tenant()`, `app.invite_user()`, `app.assign_role()`, every support-access/audit-trail/white-label mutation, 90+ functions total — was in fact directly callable by `anon` (unauthenticated) via PostgREST's standard RPC path in any real deployment. | `RECOVERED` (2026-07-17) — `supabase/migrations/20260717095000_revoke_default_public_function_execute.sql` revokes `EXECUTE` from `PUBLIC` on every existing `app`-schema function and sets `ALTER DEFAULT PRIVILEGES` so no future migration's functions receive it either; `PLT-118`'s own migration carries a redundant explicit revoke as the new standing per-migration convention. One real casualty found and fixed in the same migration: `app.mask_email()` (`PLT-114`) had relied on the `PUBLIC` default for `authenticated` callers via `app.users_directory`'s internal call to it — re-granted explicitly. Full db-test suite (all 14 files, 185 scenario groups) re-verified green after the fix; every capability's intended deliberately-broader grant (`app.query_audit_logs()`/`export_audit_logs()`/`evaluate_tenant_brand()`) confirmed unaffected. | No migration ever issued a `REVOKE EXECUTE ... FROM PUBLIC` statement; every prior capability's own "defense in depth" db-test checked `has_table_privilege` for tables only, never `has_function_privilege` for a function meant to be access-restricted, so the gap was never exercised by any test until `PLT-118`'s new custom-domain test suite happened to be the first to check it | `claude/lanjut-i0o5bt`@(commit prior to this checkpoint) | Runtime agent | this file §3, `docs/build-log/phase-01/PLT-118.md` |

## 3. Error record

### ERR-2026-001 — Parallel-session discovery merge corruption

| Field | Value |
|---|---|
| Detected by/date | Runtime agent (session b492y3) / 2026-07-14 |
| Severity/status | Sev-3/Medium / `RECOVERED` |
| Environment | Repository, branch `main` @ `d587445` |
| Related tasks/changes | `CG-S2-DISC-001` (both runs), `CG-S2-DISC-001-R1`, `CHG-2026-002` |

#### What happened

Two Claude sessions independently executed Runtime Step 2 / Prompt 21:
- Session A: branch `…-oanf5a`, PR #2 (`0097236`), checkpoint `53e3d4a` (before blueprint upload), context under `docs/runtime/` + root `AGENTS.md`.
- Session B (this): branch `…-b492y3`, PR #3 (`de2790d`), checkpoint `db1742c`, context at repo root.

Both merged into `main`. Merge commit `9278b9e` (into PR #3) resolved the `docs/discovery/01_REPOSITORY_INVENTORY.md` conflict by **concatenating** both reports (350 lines, two `## 1. Metadata` sections with contradictory checkpoints `db1742c`/438 vs `53e3d4a`/431), and left **two** competing persistent-context sets (root + `docs/runtime/`), violating GOV single-source-of-truth.

#### Evidence

- `git log --graph origin/main` shows PR #2 and PR #3 both merged; `9278b9e` merges main into b492y3.
- `grep -n '## 1. Metadata' docs/discovery/01_REPOSITORY_INVENTORY.md` → matches at lines 10 and 82 (two reports).
- `git ls-files` showed both root `CARGOGRID_*.md` and `docs/runtime/CARGOGRID_*.md`.
- No git conflict markers remained (silent concatenation), so no CI/tooling would have caught it.

#### Impact

- Discovery baseline unusable as a single artifact; downstream Prompt 22 blocked until reconciled.
- No secret exposure, no data mutation, no production/database impact (documentation-only repo).

#### Recovery (CG-S2-DISC-001-R1)

1. Restarted branch `…-b492y3` from `origin/main` (prior PR merged; branch fully merged → clean reset).
2. Chose `docs/runtime/` as the single canonical context location (CHG-2026-002); deleted the 6 duplicate root context files.
3. Rewrote `01_REPOSITORY_INVENTORY.md` as one coherent report anchored to `d587445` (blueprint-aware, 438 product/source baseline), regenerated `.sha256`.
4. Reconciled all `docs/runtime/*`; resolved session-A's ISS-2026-001 (sources now tracked); opened ISS-2026-002/003.
5. Logged this error and committed/pushed as a fresh change (new PR).

#### Verification

- `grep '## 1. Metadata'` on the rewritten inventory → single match.
- `git ls-files | grep -E '^(CARGOGRID_|TASK_LEDGER|ERROR_LEDGER|KNOWN_ISSUES|HANDOFF)'` → none at root (only `docs/runtime/`).
- Last trusted checkpoint `d587445` preserved; no merged history rewritten.

Status: `RECOVERED` — verification passed. Resume at `CG-S2-DISC-002`.

#### Recurrence (2026-07-14, merge with `claude/eloquent-mayer-s40hn4`)

A third branch, `claude/eloquent-mayer-s40hn4`, was cut from `main` at `d587445` before this reconciliation (`-R1`) had merged. It independently discovered the identical corruption (same file, same symptom) and resolved it the opposite way — root-level context kept canonical, `docs/runtime/*` marked superseded — while also completing Step 2 discovery Prompts 22–34 on top of that resolution. Merging that branch into `main` (now at `90129fc`, including `-R1`) reproduced the modify/delete conflict pattern this incident already describes. Resolution: kept `-R1`'s canonical-location decision (`docs/runtime/`), discarded the other branch's root-canonical choice, and re-homed its Step 2 discovery deliverables under this ledger set. No data was lost; both branches' substantive work (this reconciliation + the other branch's Prompts 22–34) is preserved. See `TASK_LEDGER.md` `CG-S2-DISC-002..014` and `CHANGE_MANIFEST.md` `CHG-2026-003`.

This is not logged as a new Error ID — it is the same root cause (`ISS-2026-002`) manifesting a second time, which is itself evidence that `ISS-2026-002` needs an *enforced* fix, not just a documented one.

### ERR-2026-002 — Full-lineage parallel-session divergence (Step 3 tail + Phase 0 kickoff/081/082)

| Field | Value |
|---|---|
| Detected by/date | Runtime agent, this session / 2026-07-15 |
| Severity/status | Sev-2/High / `OPEN` |
| Environment | Repository; branches `agent/cargogrid-autonomous-build` (this branch) and `claude/sleepy-ride-4vxsk6`; GitHub PR #10 (open, unmerged, targets `main`) |
| Related tasks/changes | `CG-S3-ARCH-013..016`, `CG-S5-PH0-001..003`, `CHG-2026-016..020` |

#### What happened

Two independent agent sessions both continued the CargoGrid autonomous build routine from the same shared ancestor (`origin/main`@`27389a4`, the PR #8 merge point, Prompt 45) and diverged:

- **This branch** (`agent/cargogrid-autonomous-build`): rebased forward onto `origin/main`@`824b548` (PR #9, Prompt 48) at session start, then executed Prompts 49, 50, 51 (`docs/architecture/14_*.md`–`16_*.md`), Phase 0 kickoff (Prompt 80, `docs/build-log/phase-00/00_*.md`), and Prompt 81 (`docs/build-log/phase-00/PH0-81.md`) — commits `69dbbc1`…`1802400`, current HEAD.
- **`claude/sleepy-ride-4vxsk6`** (a separate, independently-running session): continued directly from `27389a4` without the PR #9 rebase, independently executing Prompts 46, 47, 48, 49, 50, 51, Phase 0 kickoff (80), Prompt 81, **and Prompt 82** — commits `18c6a35`…`6068e62`. Opened GitHub PR #10 ("agent: adopt requirement traceability baseline (CG-S5-PH0-003, Prompt 82)") targeting `main`, created 2026-07-14T23:44:54Z — **15 seconds after** PR #9 merged into `main`, confirming near-simultaneous parallel execution rather than sequential handoff.

The two lineages' outputs for the *same* task IDs materially differ in content, not just prose: e.g. this branch's `14_REQUIREMENT_PHASE_TRACEABILITY.md` traces 607 source items; the other branch's Prompt 82 build log states its adopted traceability baseline has 401 items. Both branches also used different Phase 0 build-log directory conventions for the same task (`docs/build-log/phase-00/PH0-81.md` on this branch vs. `docs/build-logs/CG-S5-PH0-002_source_alignment_context_bootstrap.md`, the older plural convention, on the other branch).

#### Evidence

- `git log --oneline origin/claude/sleepy-ride-4vxsk6 -10` shows the independent commit sequence `6068e62`…`18c6a35`, none shared with `agent/cargogrid-autonomous-build` past `27389a4`.
- `git merge-base origin/claude/sleepy-ride-4vxsk6 origin/main` → `27389a4` (PR #8). `git merge-base agent/cargogrid-autonomous-build origin/main` → `824b548` (PR #9). Confirms the two branches diverged from different points and neither is an ancestor of the other.
- GitHub `list_pull_requests` (this session): PR #10, `state: open`, `head: claude/sleepy-ride-4vxsk6`@`6068e62`, `base: main`@`d7b695d`, created `2026-07-14T23:44:54Z` — **not merged**, no CI/review action taken on it by this session.
- `git show --stat 0bb208b` / `6068e62` (the other branch's Prompt 81/82 commits) confirm materially different file paths and content from this branch's equivalent commits.

#### Impact

- No data loss, no secret exposure, no production/database impact (both lineages are documentation-only).
- **Real impact:** two non-reconcilable, independently-numbered versions of `CG-S3-ARCH-014..016` and `CG-S5-PH0-001..003` now exist. If PR #10 is merged into `main` independently of this branch (or vice versa), a future merge between the two lineages will silently duplicate or conflict — the same failure pattern as `ERR-2026-001`, at much larger scale (9 commits / 3+ full documents vs. one file).
- Continuing to advance *either* branch further compounds the eventual reconciliation cost. This session therefore halts further prompt execution on discovery of this state rather than proceeding into Prompt 82.

#### Recovery — NOT YET PERFORMED, requires operator decision

This is **not** resolved by this session. Per this routine's own instruction to stop on conflicting repo state and record a blocker rather than resolve it unilaterally (picking a branch/PR to keep is a significant, hard-to-reverse, shared-state decision), recovery requires an explicit operator choice between:

1. **Adopt this branch** (`agent/cargogrid-autonomous-build`, current HEAD `1802400`) as authoritative; close PR #10 without merging; the other branch's Prompt 82 work (`claude/sleepy-ride-4vxsk6`) is discarded (it re-derives content already produced independently on this branch through Prompt 81, plus one additional prompt, 82, not yet done here).
2. **Adopt PR #10's lineage** (`claude/sleepy-ride-4vxsk6`, includes Prompt 82) as authoritative; reset `agent/cargogrid-autonomous-build` to match; this branch's Prompts 49–51/80/81 work is discarded in favor of the other lineage's equivalent (already-complete) versions.
3. **Reconcile manually** — compare both lineages' Prompt 49–51/80–82 outputs field-by-field (similar to the `CG-S2-DISC-001-R1` precedent, `ERR-2026-001` above) and produce a merged, single authoritative version, documenting which facts/numbers from each lineage were kept and why.

No option is safe for an autonomous agent to select without operator input — option 1 or 2 discards real completed work either way, and option 3 requires judgment about which lineage's specific factual claims (e.g., 607 vs. 401 traced items) are correct.

Status: `SUPERSEDED` by `ERR-2026-003` (below) — the situation this record describes (an unreconciled open PR) no longer exists; both PRs were merged, but without ever performing the reconciliation this record said was required. The corruption that resulted is now tracked as a distinct, more severe error.

### ERR-2026-003 — Post-divergence merge corruption (PR #10 + PR #11 both merged into `main` without reconciliation)

| Field | Value |
|---|---|
| Detected by/date | Runtime agent, this session / 2026-07-15 |
| Severity/status | Sev-1/Critical / `OPEN` |
| Environment | Repository; `main`@`b7653cb`; every branch cut from `main` after that commit, including this run's branch `agent/cargogrid-autonomous-build` (recreated from `origin/main` this session, since the old same-named branch's lineage is now fully contained in `main`) |
| Related tasks/changes | `CG-S3-ARCH-014..016`, `CG-S5-PH0-001..003`, `CHG-2026-016..022` |

#### What happened

`ERR-2026-002` (above) recorded that two divergent lineages — this repo's `agent/cargogrid-autonomous-build` branch and the independent `claude/sleepy-ride-4vxsk6` branch (PR #10) — had each independently redone Prompts 46–51 (Step 3 closure) and Phase 0 Prompts 80–82, producing materially different content for the same task IDs (e.g. 607 vs. 401 traced requirement items), and explicitly said this required an **operator** decision among three reconciliation options before either branch resumed.

Before any such decision was recorded, both PRs were merged into `main` by the repository owner directly on GitHub:
1. `a8a197f` — merged PR #10 (`claude/sleepy-ride-4vxsk6`) into `main`.
2. `b7653cb` — merged PR #11 (`agent/cargogrid-autonomous-build`, which had itself merged `main` at `b777bb2`, picking up PR #10's content) into `main`.

Neither merge produced git conflict markers, because each lineage's edits landed as pure insertions relative to the merge base rather than overlapping line-for-line edits. Git therefore auto-resolved both merges by **concatenating** the two lineages' full content, one after another, inside the same files — not a reconciliation, a literal duplication.

#### Evidence

- `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` (1,465 lines) contains **two** complete copies of the document back-to-back: `## 1. Scope and method` appears at line 29 *and* line 760. The first copy states `**Total traced items** | **607**` (line 662); the second states counts against a `401` total (line 1396, "Percentage of 401 total traced items").
- `docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md` and `docs/architecture/16_STEP3_CLOSURE_REPORT.md` show the identical pattern — each has two `## 1.` sections (`grep -c '^## 1\.'` → 2 in both files).
- `docs/runtime/HANDOFF.md`, `docs/runtime/CARGOGRID_BUILD_STATUS.md`, and `docs/runtime/TASK_LEDGER.md` similarly contain multiple stacked, mutually contradictory "current checkpoint" sections/rows (different branch names, different task statuses, different "Active blockers" fields) from both lineages, appended rather than reconciled.
- `git show --stat a8a197f` and `git show --stat b7653cb` confirm each merge purely *added* lines to these files (no deletions), consistent with silent concatenation rather than resolution.
- `git log --graph --oneline` confirms both `d7b695d` (PR #9) → `a8a197f` (PR #10) → `b7653cb` (PR #11) landed sequentially on `main`, and that `ERR-2026-002`/`HANDOFF.md` §7 "Handoff accepted by/date: PENDING (operator)" was never updated to reflect an actual decision.

#### Impact

- The Step 3 closure claim (`RUNTIME_ARCHITECTURE_VERIFIED`, `docs/architecture/16_*.md`) and the Phase 0 traceability baseline (`CG-S5-PH0-003`, `docs/architecture/14_*.md`) that many downstream Phase 0 capability prompts (`PH0-084` onward) are supposed to build on are **not currently a single trustworthy artifact** — they are two incompatible drafts concatenated into one file, with contradictory totals (607 vs. 401 traced items) and no indication which is authoritative.
- No secret exposure, no data mutation outside `docs/**`, no production/database impact (still a documentation-only repository).
- Continuing Phase 0 execution (`PH0-084` onward) on top of this corrupted baseline would compound the problem and make eventual reconciliation harder, exactly as `ERR-2026-002` warned.

#### Recovery — performed 2026-07-15 (operator-authorized, Lineage A adopted)

**Operator decision (recorded in `HANDOFF.md` §1):** adopt **Lineage A** (option 1) as the single authoritative version of `docs/architecture/14..16_*.md`. The decision was reached after a fresh evidence-based re-analysis comparing both concatenated copies against the primary source (`00-control/05_REQUIREMENT_COVERAGE_MATRIX.md`) and the originating prompts (49–51):

- **Lineage A's 607-item total is internally self-consistent:** `14_*.md` §24.1 by-source table sums to 607, and §24.4 by-state table (568 `COVERED` + 20 `ACCEPTED_RISK` + 15 `EXTERNAL_VERIFICATION` + 4 `PARTIAL_BLOCKED` + 0 `NOT_COVERED`) also sums to 607.
- **Lineage B's 401-item total is internally inconsistent:** its own parenthetical breakdown formula summed to 469 and its by-state row summed to 385 — three different "totals" in one document, an arithmetic defect, not a methodological difference. Lineage B's copy of `16_*.md` additionally contained a raw git-diff artifact pasted as a section heading (`## claude/sleepy-ride-4vxsk6...origin/claude/sleepy-ride-4vxsk6`).
- Both lineages' per-catalogue counts agree where they overlap (194 explicit requirements, 92 assumptions, 13 package-gap IDs, 60 conflict-register rows); the 401 was the same catalogues mis-totalled, not a narrower scope. Adopting Lineage A loses no correct requirement mapping.

**Recovery steps performed:**
1. `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` truncated to its Lineage A copy (lines 1–739, ending §28); Lineage B duplicate (former lines 740–1465) removed.
2. `docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md` truncated to Lineage A (lines 1–290); Lineage B duplicate removed.
3. `docs/architecture/16_STEP3_CLOSURE_REPORT.md` truncated to Lineage A (lines 1–190); Lineage B duplicate + git-diff artifact removed. Closure state `RUNTIME_ARCHITECTURE_VERIFIED` preserved.
4. Prompt 82 (`CG-S5-PH0-003`) re-verified against the authoritative 607-item baseline; new log `docs/build-log/phase-00/PH0-82.md` written; discarded Lineage B log `docs/build-logs/CG-S5-PH0-003_requirement_traceability_baseline.md` (401-based) removed.
5. Phase 0 build logs standardized on the prompt-package-prescribed singular path `docs/build-log/phase-00/PH0-NN.md`; the plural Lineage B Phase 0 duplicates (`CG-S5-PH0-001_*`, `CG-S5-PH0-002_*`, `CG-S5-PH0-003_*`) removed to eliminate the duplicate source of truth. Trusted Step 2 `docs/build-logs/CG-S2-*` logs retained (unaffected, closed).

#### Verification

- `grep -c '^## 1\. Scope and method'` → 1 in each of `14/15_*.md`; `grep -c '^## 1\.'` → 1 in `16_*.md`.
- `grep -c 401` → 0 in all three files; `grep -c 607` → 5 in `14_*.md` (all consistent).
- `grep -c '^## claude/sleepy-ride'` → 0 in `16_*.md`.
- No secret exposure, no data mutation outside `docs/**`.

Status: `RECOVERED`. Next runtime work resumes at `CG-S5-PH0-004` (Prompt 83) against the reconciled, non-corrupted baseline.

### ERR-2026-004 — Every `service_role`-only database function has been directly callable by `anon` since `PLT-105`

| Field | Value |
|---|---|
| Detected by/date | Runtime agent, this session / 2026-07-17, while authoring `PLT-118` (Custom Domain) |
| Severity/status | Sev-1/Critical / `RECOVERED` |
| Environment | Database / every migration `20260716075355_create_tenants.sql` through `20260717090512_create_white_label.sql` |
| Related tasks/changes | `CG-S6-PLT-002` through `CG-S6-PLT-014` (`PLT-105`..`117`, every capability that created a `service_role`-only function); fixed by `CG-S6-PLT-015` (`PLT-118`) |

#### What happened

PostgreSQL's `CREATE FUNCTION` grants `EXECUTE` to the pseudo-role `PUBLIC` by default, unless a migration explicitly revokes it. `PUBLIC` is implicitly held by every real role, including `anon` and `authenticated`. No migration from `PLT-105` (the first real migration in this repository) through `PLT-117` ever issued a `REVOKE EXECUTE ... FROM PUBLIC` statement. Every function any of those migrations' own grant comments documented as "`service_role`-only" — `app.provision_tenant()`, `app.invite_user()`, `app.assign_role()`, `app.request_support_access()`/`approve_support_access()`/`deny_support_access()`/`revoke_support_access()`, `app.capture_audit_event()`, `app.supreme_admin_mutate_audit_log()`/`_delete_audit_log()`, every `PLT-117` white-label mutation, and more — was therefore directly callable via PostgREST's RPC path by `anon`, with no session, no JWT, and no prior authentication of any kind, in any real Supabase deployment.

Because every mutation function in this repository takes an explicit actor-identity parameter (`p_actor_auth_user_id`/`p_requester_auth_user_id`) rather than deriving it from `auth.uid()` — by design, since the application server is meant to authenticate the real session itself and call these functions only with `service_role` credentials — the practical effect of the missing `REVOKE` was a complete authorization-boundary bypass: any caller could invoke any mutation and supply *any* UUID as the actor parameter, and every internal `app.is_supreme_admin()`/`app.is_support_grant_authority()` check would honor whichever identity the call claimed, not who was actually connected.

#### Evidence

- Direct query against a fully-migrated disposable database: `select has_function_privilege('anon', 'app.provision_tenant(text, text, text, text, jsonb)', 'EXECUTE');` → `t`, confirmed before any fix was applied.
- A full enumeration (`select p.oid::regprocedure from pg_proc p join pg_namespace n ... where has_function_privilege('anon', p.oid, 'EXECUTE')`) returned 90+ functions across the entire `app` schema, essentially the complete function inventory through `PLT-117`.
- No prior db-test file in this repository's history ever called `has_function_privilege(...)` against a function meant to be restricted — every capability's own "defense in depth" test checked only `has_table_privilege` for tables (which correctly defaults to no `PUBLIC` grant). `PLT-118`'s new `scripts/db-tests/custom-domain.sql` is the first test to check function-level privilege for a restricted function, and its assertion against `app.list_tenant_domains()` failed immediately, surfacing the gap.

#### Impact

- Every write-capable capability shipped in this repository to date (`PLT-105` through `PLT-117`) was affected identically — this is not specific to any one capability's own logic, and no capability's business logic itself is defective.
- No live/production/deployed environment exists yet for this repository (`docs/discovery/04_DATABASE_MIGRATION_BASELINE.md`, still greenfield) — the exposure window was real at the database-grant level but had no live Supabase project/PostgREST endpoint to actually reach yet, disclosed as a mitigating (not exculpatory) fact.
- No secret exposure, no data mutation, no tenant data actually touched by this defect itself — this record is about a privilege-boundary gap that was found and closed before any live environment existed to exploit it.

#### Recovery — performed 2026-07-17

1. `supabase/migrations/20260717095000_revoke_default_public_function_execute.sql`: `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` (removes the `PUBLIC` ACL entry from every function existing as of `PLT-117`, without touching any role-specific grant already issued to `service_role`/`authenticated`/`anon`) and `ALTER DEFAULT PRIVILEGES IN SCHEMA app REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (closes the gap prospectively for every future migration applied by the same role).
2. One real casualty found by re-running the full existing db-test suite after the revoke, fixed in the same migration: `app.mask_email()` (`PLT-114`) had relied on the `PUBLIC` default for `authenticated` callers via `app.users_directory`'s internal call to it (a function call's `EXECUTE` check is evaluated against the querying role, not a view's owner, unlike table/RLS access) — re-granted explicitly to `authenticated`/`service_role`.
3. `PLT-118`'s own migration (`20260717103015_create_custom_domain.sql`) carries a redundant, explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement as defense-in-depth, adopted as the new standing per-migration convention going forward (an explicit, directly-provable statement in each migration's own text, not solely reliance on the session-scoped default-privilege setting).

#### Verification

- Full `pnpm run db:test` re-run after the fix: all 14 test files, 185 total scenario groups, `ALL PASSED`.
- Direct re-check: `has_function_privilege('anon', 'app.provision_tenant(...)', 'EXECUTE')` → `f`; `has_function_privilege('authenticated', 'app.mask_email(text)', 'EXECUTE')` → `t`; `has_function_privilege('anon', 'app.evaluate_tenant_brand(uuid)', 'EXECUTE')` → `t` (the one deliberately-broader grant, confirmed preserved).
- Every capability's own db-test file (`PLT-105` through `PLT-117`) re-verified green, unchanged, after the fix — zero behavioral regression to any function's logic or intended accessibility.

Status: `RECOVERED`. Full detail: `docs/build-log/phase-01/PLT-118.md`.

## 4. Notes

Prevention: run each runtime Step 2–onward prompt on **one** authoritative branch only; do not open parallel agent sessions on the same runtime step (tracked as ISS-2026-002 — now demonstrated twice). Use the full error-record template from `01-agent-governance/17_ERROR_LEDGER_TEMPLATE.md` for future entries.
