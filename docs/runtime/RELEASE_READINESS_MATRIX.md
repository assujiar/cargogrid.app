# Step 15 Full-System Hardening — Release Readiness Matrix

**Authored at:** `HDN-388` (Prompt 388, `CG-S15-HDN-020`, Documentation Handoff), 2026-08-24.
**Status:** Living document — updated by `HDN-389` (Closure Verification) and, if Step 16
begins, by whichever Step 16 checkpoint next changes any row here.

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
| 2 | No critical/high security defect | **PASS** | 0 open Critical anywhere (confirmed `HDN-387`, unchanged at `HDN-388`); open Highs are RLS/RBAC-coverage gaps with named owners (`HDN-BLK-016..018`, `022`, `024`), not live-exploitable bypasses of a shipped control |
| 3 | No unresolved financial integrity issue | **PASS** | `HDN-374` fixed the quote-tax-doubling and double-invoicing defects at the actual posting boundary; `HDN-BLK-016` (no reversing GL journal on settlement reversal) is open, High, not a live miscalculation — a missing corrective-entry capability, disclosed |
| 4 | No broken core E2E flow | **PASS** | `pnpm run test:e2e` 34/34 as of `HDN-381`; Safari/Firefox untested is a disclosed sandbox constraint (`ISS-2026-244`, `TRACKED_GAP`), not a broken flow |
| 5 | Migrations apply cleanly | **PASS** | `bash scripts/db-tests/run.sh` 230/230 files clean, 333 migrations, as of `HDN-387` (unchanged at `HDN-388`, no new migration this checkpoint) |
| 6 | Backup and restore tested | **PARTIAL** | `HDN-383` live-executed and measured schema replay (~44-46s) and a real `pg_dump`/`pg_restore` cycle (~11.6s), both 0 errors; Storage/Auth/hosted-project restore remains untested, structurally infeasible in this sandbox (`ISS-2026-255`/`HDN-BLK-030`, High, `TRACKED_GAP`) |
| 7 | DR rehearsal completed according to gate | **PARTIAL** | `HDN-384` live-rehearsed data-corruption and security-incident scenarios; major-outage/provider-failure scenario is tabletop-only, disclosed; session revocation confirmed inert (`ISS-2026-264`/`HDN-BLK-035`, High) |
| 8 | Monitoring and alerting active | **PARTIAL** | Real alert producers exist for dead-letter job failures (`HDN-382`) and 3 webhook-ingestion signature failures (`HDN-387`); most other failure producers remain unwired (`ISS-2026-249`/`HDN-BLK-027`, High, partially resolved) and no monitoring dashboard UI exists (`ISS-2026-250`/`HDN-BLK-028`, High) |
| 9 | Runbooks available | **PASS**, this checkpoint | 17 runbooks now exist under `docs/runbooks/` (14 pre-existing + `performance-capacity.md`, `on-call-ownership.md`, `deployment-migration-guard.md`, authored this checkpoint — see `docs/runbooks/README.md`); all 7 items of the `00_EXECUTION_INDEX.md` §11.4 checklist now have a current, evidence-backed home |
| 10 | No fake pass, hidden failure or disabled test | **PASS** | Every Step 15 checkpoint's own Tier A/B/C discipline is built around this; no test is skipped or disabled anywhere in the current suite (`pnpm run test` 5444/5444) |

**Read literally, gate 9 is the only one this checkpoint itself changes from `MISSING`/`PARTIAL`
to `PASS`.** Gates 6, 7 and 8 are genuinely `PARTIAL` — every gap behind that verdict is a
disclosed, owned, non-Critical finding, not a silent omission; none is fixable within a
documentation-handoff checkpoint's own charter.

---

## 2. Blocker tally (as of `HDN-388`; see `BLOCKER_LEDGER.md`'s own "Status as of `HDN-388`"
section for the authoritative live count)

| Severity | Open | Notes |
|---|---|---|
| Critical | **0** | Zero since `HDN-387`; unchanged |
| High | **17** | Down from 18 — `HDN-BLK-001` closed this checkpoint (ledger-text correction, its blocking dependency `HDN-BLK-023` resolved at `HDN-387`) |
| Medium | **6** | Unchanged — `HDN-BLK-004`'s text corrected this checkpoint, its own postgis-remainder (`ISS-2026-234`) stays genuinely open |

### 2.1 The 5 open High items with no §8.2 disposition — the load-bearing gap for `HDN-389`

`00_EXECUTION_INDEX.md` §12 condition 4 requires **every** High blocker to be either fixed with
regression proof or formally ruled `ACCEPTED_EXCEPTION` under §8.2's full 5-condition test
before Step 16 eligibility. 12 of the 17 open High items (`HDN-BLK-027..038`) already carry that
ruling, made at `HDN-387` Tier C via `HDN-BLK-039`, owner `Step 16`. **5 do not:**

| ID | Title (short) | Named prior owner | Owner's own checkpoint status |
|---|---|---|---|
| `HDN-BLK-016` | No reversing GL journal on settlement reversal | `HDN-386` | `VERIFIED`, closed |
| `HDN-BLK-017` | Hash-chain triggers are fingerprints, not a genuine chain | `HDN-386` | `VERIFIED`, closed |
| `HDN-BLK-018` | Append-only guard needed on ~70 more tables | `HDN-386` | `VERIFIED`, closed |
| `HDN-BLK-022` | RLS/RPC gate gap, ~33-table remainder | `HDN-378` (remainder) | `VERIFIED`, closed |
| `HDN-BLK-024` | MFA/IP-restriction wiring gap, 3 of 7 tuples | `HDN-386` | `VERIFIED`, closed |

Per §8.2 condition 5, a ruling may be made **only** at `HDN-387` or `HDN-389` — never by the
lane that found a finding, and (per this checkpoint's own charter) never by `HDN-388`, a
documentation-handoff lane with no fix or acceptance authority of its own. `HDN-387` is closed.
**`HDN-389` is therefore the only remaining checkpoint that can close this gap** — either by
seeing one or more of these 5 items fixed with regression proof, or by formally ruling them
`ACCEPTED_EXCEPTION` under the full 5-condition test, with a real named owner and future task
(mirroring `HDN-BLK-039`'s own treatment of the other 12). This is not a new gap this checkpoint
discovered — it existed identically the moment `HDN-387` closed — but no prior checkpoint's own
ledger synthesis had stated it this explicitly as a single, named, closeable punch list.

---

## 3. Step 16 eligibility — explicit statement (`00_EXECUTION_INDEX.md` §12)

| Condition | Status |
|---|---|
| 1. `HDN-370`…`HDN-388` all `VERIFIED` at one compatible checkpoint | **PENDING** — `HDN-370`..`387` (19 checkpoints) confirmed `VERIFIED`; `HDN-388` itself becomes `VERIFIED` only at this checkpoint's own Tier C close |
| 2. `HDN-389` has run and set `FULL_SYSTEM_HARDENING_VERIFIED` | **NOT STARTED** — `HDN-389` is the next eligible prompt after this one closes |
| 3. Every one of the ten §8.1 gates passes | **NOT MET** — 3 of 10 (gates 6, 7, 8) are `PARTIAL`, each for disclosed, owned, non-Critical reasons (§1 above) |
| 4. Zero unresolved Critical; every High fixed-with-proof or `ACCEPTED_EXCEPTION` | **NOT MET** — 0 Critical (met); 5 open High items have neither disposition (§2.1 above) |
| 5. `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` exists, disposes of all 22 Prompt 389 items | **NOT MET** — does not exist yet; it is `HDN-389`'s own deliverable, not `HDN-388`'s |
| 6. No production/pilot/GA/market-ready claim anywhere | **MET** — confirmed by this checkpoint's own investigation lens; no violating sentence found anywhere in `docs/build-log/full-system-hardening/` or `docs/runtime/` |

### Go/no-go recommendation

**NO-GO for Step 16, as of `HDN-388`.** This is expected and by design — `HDN-389` has not yet
run, and per condition 2 above, only `HDN-389` may set the completion flag. The honest, complete
punch list `HDN-389` inherits from this checkpoint is narrow and named: (a) formally dispose of
the 5 un-ruled High items (§2.1); (b) author `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md`,
disposing of all 22 required-verification items of its own Prompt 389 charter; (c) confirm gates
6/7/8's own `PARTIAL` status is each an acceptable, disclosed residual rather than a blocking
gap, or escalate any that is not. Nothing found by this checkpoint's own investigation requires
new code, a new migration, or reopening any already-`VERIFIED` checkpoint's own work.

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
  register; its own "Status as of `HDN-388`" section is the authoritative current tally.
- `docs/runtime/KNOWN_ISSUES.md` — every finding's own full narrative.
- `docs/runbooks/README.md` — the current runbook index.
- `docs/runtime/HANDOFF.md` — the Step 16 handoff section (§0 of that file, added at `HDN-388`).
