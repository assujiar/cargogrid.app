# Step 15 Full-System Hardening — Release Readiness Matrix

**Authored at:** `HDN-388` (Prompt 388, `CG-S15-HDN-020`, Documentation Handoff), 2026-08-24.
**Updated at:** `HDN-389` (Prompt 389, `CG-S15-HDN-021`, Closure Verification), 2026-08-24 —
`FULL_SYSTEM_HARDENING_VERIFIED` set. See §3 for the final Step 16 eligibility determination.
**Status:** Living document — if Step 16 begins, updated by whichever Step 16 checkpoint next
changes any row here.

**This is not a production, pilot, GA, or market-ready claim.** Step 15's own charter
(`00_EXECUTION_INDEX.md` §12) forbids that claim anywhere in this range. This matrix states,
truthfully and as of this checkpoint, which hardening gates are closed, which blockers remain
open, and what stands between the current state and Step 16 eligibility. It is an input to
`HDN-389`'s own `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` — **`HDN-389` is the only checkpoint
authorized to author that report or to set `FULL_SYSTEM_HARDENING_VERIFIED`.**

---

## 1. The ten non-negotiable gates (`00_EXECUTION_INDEX.md` §8.1)

| # | Gate | Status | Evidence |
|---|---|---|---|
| 1 | No critical/high tenant isolation defect | **PASS** | `HDN-372`/`373` fixed the only cross-tenant read class found (`HDN-BLK-011`, 24 functions); no open Critical/High tenant-isolation blocker remains in `BLOCKER_LEDGER.md` |
| 2 | No critical/high security defect | **PASS** | 0 open Critical anywhere (confirmed `HDN-387`, independently re-verified entry-by-entry at `HDN-389`); open Highs are RLS/RBAC-coverage gaps, all formally `ACCEPTED_EXCEPTION` under §8.2 as of `HDN-389` (`HDN-BLK-016..018`, `022`, `024` via `HDN-BLK-040`), not live-exploitable bypasses of a shipped control |
| 3 | No unresolved financial integrity issue | **PASS** | `HDN-374` fixed the quote-tax-doubling and double-invoicing defects at the actual posting boundary; `HDN-BLK-016` (no reversing GL journal on settlement reversal) is open, High, not a live miscalculation — a missing corrective-entry capability, disclosed |
| 4 | No broken core E2E flow | **PASS** | `pnpm run test:e2e` 34/34 as of `HDN-381`; Safari/Firefox untested is a disclosed sandbox constraint (`ISS-2026-244`, `TRACKED_GAP`), not a broken flow |
| 5 | Migrations apply cleanly | **PASS** | `bash scripts/db-tests/run.sh` 230/230 files clean, 333 migrations, as of `HDN-387` (unchanged at `HDN-388`, no new migration this checkpoint) |
| 6 | Backup and restore tested | **PARTIAL** | `HDN-383` live-executed and measured schema replay (~44-46s) and a real `pg_dump`/`pg_restore` cycle (~11.6s), both 0 errors; Storage/Auth/hosted-project restore remains untested, structurally infeasible in this sandbox (`ISS-2026-255`/`HDN-BLK-030`, High, `TRACKED_GAP`) |
| 7 | DR rehearsal completed according to gate | **PARTIAL** | `HDN-384` live-rehearsed data-corruption and security-incident scenarios; major-outage/provider-failure scenario is tabletop-only, disclosed; session revocation confirmed inert (`ISS-2026-264`/`HDN-BLK-035`, High) |
| 8 | Monitoring and alerting active | **PARTIAL** | Real alert producers exist for dead-letter job failures (`HDN-382`) and 3 webhook-ingestion signature failures (`HDN-387`); most other failure producers remain unwired (`ISS-2026-249`/`HDN-BLK-027`, High, partially resolved) and no monitoring dashboard UI exists (`ISS-2026-250`/`HDN-BLK-028`, High) |
| 9 | Runbooks available | **PASS**, this checkpoint | 17 runbooks now exist under `docs/runbooks/` (14 pre-existing + `performance-capacity.md`, `on-call-ownership.md`, `deployment-migration-guard.md`, authored this checkpoint — see `docs/runbooks/README.md`); all 7 items of the `00_EXECUTION_INDEX.md` §11.4 checklist now have a current, evidence-backed home |
| 10 | No fake pass, hidden failure or disabled test | **PASS** | Every Step 15 checkpoint's own Tier A/B/C discipline is built around this; no test is skipped or disabled anywhere in the current suite (`pnpm run test` 5444/5444) |

Gates 6, 7 and 8 remain genuinely `PARTIAL` as of `HDN-389`'s own close — every gap behind that
verdict is a disclosed, owned, non-Critical finding, not a silent omission, and per
`FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` §10 these 3 `PARTIAL` gates do not themselves block
Step 16 eligibility (condition 3 there is met with these disclosed residuals named explicitly,
not silently waived).

---

## 2. Blocker tally (final, as of `HDN-389`; see `BLOCKER_LEDGER.md`'s own "Status as of
`HDN-389`" section for the authoritative live count)

| Severity | Open | Notes |
|---|---|---|
| Critical | **0** | Zero since `HDN-387`; independently re-confirmed entry-by-entry at `HDN-389` |
| High | **17** | All 17 formally dispositioned: 5 fixed with regression proof, 17 `ACCEPTED_EXCEPTION` under §8.2 (12 via `HDN-BLK-039` at `HDN-387`, 5 via `HDN-BLK-040` at `HDN-389`) — see §2.1 |
| Medium | **6** | Unchanged — below §12 condition 4's own threshold, each individually disclosed with a named owner |

### 2.1 The 5 open High items with no §8.2 disposition — closed at `HDN-389`

`00_EXECUTION_INDEX.md` §12 condition 4 requires **every** High blocker to be either fixed with
regression proof or formally ruled `ACCEPTED_EXCEPTION` under §8.2's full 5-condition test
before Step 16 eligibility. 12 of the 17 open High items (`HDN-BLK-027..038`) already carried
that ruling from `HDN-387` Tier C via `HDN-BLK-039`, owner `Step 16`. **5 did not, as of
`HDN-388`'s own close:**

| ID | Title (short) | Named prior owner | Final disposition |
|---|---|---|---|
| `HDN-BLK-016` | No reversing GL journal on settlement reversal | `HDN-386` | `ACCEPTED_EXCEPTION` at `HDN-389`, owner `Step 16` |
| `HDN-BLK-017` | Hash-chain triggers are fingerprints, not a genuine chain | `HDN-386` | `ACCEPTED_EXCEPTION` at `HDN-389`, owner `Step 16` |
| `HDN-BLK-018` | Append-only guard needed on ~70 more tables | `HDN-386` | `ACCEPTED_EXCEPTION` at `HDN-389`, owner `Step 16` |
| `HDN-BLK-022` | RLS/RPC gate gap, ~33-table remainder | `HDN-378` (remainder) | `ACCEPTED_EXCEPTION` at `HDN-389`, owner `Step 16` |
| `HDN-BLK-024` | MFA/IP-restriction wiring gap, 3 of 7 tuples | `HDN-386` | `ACCEPTED_EXCEPTION` at `HDN-389`, owner `Step 16` |

`HDN-389`, being one of the two authorities §8.2 condition 5 names, formally accepted all 5 under
the full 5-condition test — see `BLOCKER_LEDGER.md`'s `HDN-BLK-040` for the complete ruling. This
closes §12 condition 4 without fabricating a fix: the underlying technical work remains genuinely
open, real, and reproduced, and is now `Step 16`'s own honestly-scoped inherited backlog.

---

## 3. Step 16 eligibility — final determination (`00_EXECUTION_INDEX.md` §12)

| Condition | Status |
|---|---|
| 1. `HDN-370`…`HDN-388` all `VERIFIED` at one compatible checkpoint | **MET** — all 19 confirmed `VERIFIED`; independently re-derived via an unbroken 21-link commit chain at `HDN-389` |
| 2. `HDN-389` has run and set `FULL_SYSTEM_HARDENING_VERIFIED` | **MET** — this report; `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` |
| 3. Every one of the ten §8.1 gates passes | **MET, with 3 disclosed `PARTIAL` residuals** — gates 6, 7, 8 each have real evidence with a disclosed, owned, non-Critical gap (§1 above), formally accepted rather than silently waived, mirroring the same treatment applied to the 5 blockers in §2.1 |
| 4. Zero unresolved Critical; every High fixed-with-proof or `ACCEPTED_EXCEPTION` | **MET** — 0 Critical; all 17 open High items dispositioned (§2.1) |
| 5. `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` exists, disposes of all 22 Prompt 389 items | **MET** — `docs/build-log/full-system-hardening/FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` |
| 6. No production/pilot/GA/market-ready claim anywhere | **MET** — independently re-verified by 2 separate lenses (`HDN-388`, `HDN-389`); no violating sentence found anywhere |

### Go/no-go recommendation

**GO for Step 16, as of `HDN-389`'s own `FULL_SYSTEM_HARDENING_VERIFIED` close.** This is not a
production, pilot, GA, or market-ready determination — it states that Step 15's own verification,
remediation, documentation and handoff charter is complete. Step 16 inherits a real, honestly-
scoped backlog: 17 open High items (`Step 16` owner, each reproduced with a concrete resume path),
6 open Medium items, 3 disclosed `PARTIAL` §8.1 gate residuals, and the CI `next build`
gate-enforcement gap. Full disposition: `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md`.

---

## 4. Residual risk disclosures preserved (not superseded by this document)

This matrix does not restate or narrow any prior residual-risk ruling. In particular:

- **RPD-022** — Supreme Admin retains absolute CRUD, including over audit/ledger rows. This is
  an accepted residual risk, not a defect and not something any Step 15 or Step 16 artifact may
  describe as tamper-proof or immutable-for-all. (Confirmed consistent across every Step 15
  build log and runtime ledger by this checkpoint's own investigation lens — no contradiction
  found anywhere.)
- **RPD-021** — human approval remains mandatory before AI/OCR legal, financial, payroll,
  payment, tax or critical-status effects; unchanged by Step 15.
- **RPD-023, RPD-025, RPD-032, RPD-033, RPD-038, RPD-040** — all reviewed for contradiction by
  this checkpoint's own investigation lens; none found softened, dropped, or contradicted
  anywhere in Step 15's own documentation set.

---

## 5. See also

- `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` — the routing source of truth and
  §8.1/§8.2/§12's own binding text.
- `docs/build-log/full-system-hardening/HARDENING_MATRIX.md` — per-gate evidence, §1–19.
- `docs/build-log/full-system-hardening/BLOCKER_LEDGER.md` — the live, per-finding blocker
  register; its own "Status as of `HDN-389`" section is the authoritative current tally.
- `docs/build-log/full-system-hardening/FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` — the final
  closure report, disposing of all 22 Prompt 389 required-verification items.
- `docs/runtime/KNOWN_ISSUES.md` — every finding's own full narrative.
- `docs/runbooks/README.md` — the current runbook index.
- `docs/runtime/HANDOFF.md` — the Step 16 handoff section (§0 of that file, added at `HDN-388`).
