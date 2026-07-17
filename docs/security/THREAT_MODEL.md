# CargoGrid Initial Threat Model

**Established by:** `CG-S5-PH0-017` (Prompt 96 — Initial Threat Model)
**Status:** Active — an *initial*, Phase-0-scoped model tied to already-`VERIFIED` architecture, not a final or exhaustive one (Prompt 96's own naming, §33's "Initial threat model"). Refined incrementally as each Phase 1+ capability prompt ships real code (§6), and closed out at Phase 15 hardening's full penetration test (`docs/architecture/10_TESTING_WORKSTREAM.md` §8.2, §9 Phase 15 row).

This document does not invent a threat catalogue independent of what already exists — it applies the STRIDE lens and a reproducible risk rank to threats already named in `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` §10 (15-item negative-test matrix), `docs/architecture/10_TESTING_WORKSTREAM.md` §5.2 (18 `TI-*` tenant-isolation scenarios) and §5.3 (24 `FINTEST-*` financial-integrity scenarios), `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` §13 (API/webhook/job/integration test matrix), `docs/architecture/11_DEVOPS_WORKSTREAM.md` §7/§8 (storage/backup/DR), and this build's own `docs/discovery/06_SECURITY_BASELINE.md` (`SEC-2026-001`) and Phase 0 foundation work (`PH0-93`/`94`/`95`). The typed, tested register itself is `scripts/security/threat-model.ts` (`pnpm run threat-model:check`, wired into CI) — this document is its narrative, not a competing source of truth.

## 1. Scope, assets, actors

**Scope:** Phase 0 architecture and Phase 1+ planned surfaces (no application code exists yet, `docs/discovery/05_ROUTE_MODULE_INVENTORY.md`) — this model covers what the *ratified architecture* will expose once built, so it is actionable before Platform Core implementation begins (Prompt 96 §5's own stated business value), not a report on code that does not exist.

**Assets** (reproduced from `docs/standards/DATA_CLASSIFICATION_STANDARDS.md` §1–§3, not re-derived): the 6 field-group categories (`cost_margin`, `finance`, `payroll`, `pii`, `security_credential`, `support`) and their 5-level sensitivity scale; tenant document files (`05_DATABASE_SCHEMA_WORKSTREAM.md` §"File metadata/quarantine"); the append-only audit/security log tables (`05_*.md` §6); the one real credential this repository has today (`SUPABASE_SERVICE_ROLE_KEY`, `scripts/data-classification/registry.ts`'s `PHASE_0_REGISTRY`).

**Actors** (reproduced from `06_RLS_RBAC_WORKSTREAM.md`, already `VERIFIED`): tenant internal users (branch/role-scoped), customer portal users, tenant admins, Supreme Admin (RPD-022's disclosed absolute-CRUD exception), support engineers (time-bound elevated access), external API/OAuth/webhook callers, background jobs, and third-party integrations.

## 2. Trust boundaries

Reproduces `docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md` §10's 7-layer access chain verbatim, the binding trust-boundary sequence every flow crosses: **tenant isolation (RLS) → module entitlement → RBAC action → scope permission → field-level security → lifecycle permission (status) → document/file access (signed URL)**, ending in an audit event where required. Each `THREAT_REGISTER` entry (§3) names which of these layers its threat would cross if the layer's control were missing or misimplemented.

## 3. Methodology (Prompt 96 §21/§22, reproducibility per §25)

`scripts/security/threat-model.ts`'s `THREAT_REGISTER` assesses **likelihood** and **impact** against the *planned* architecture as if built without its named control — the only way a pre-implementation threat model is actionable, since nothing is exploitable today (no code exists, `docs/discovery/06_SECURITY_BASELINE.md`). `computeRiskRank()` is a deterministic lookup table (not a naive likelihood×impact product, which would understate a low-likelihood/catastrophic-impact threat below "critical" — disclosed and fixed in the function's own comment) chosen so that an already-Critical-rated source item (e.g. `TI-001`, `06_*.md` test #13's malware-scan gate) computes to at least `high`, consistent with — not contradicting — the severity already established in `10_TESTING_WORKSTREAM.md` §5.2/§5.3. Multiple applicable STRIDE categories per threat resolve additively (a threat tagged both `tampering` and `information_disclosure` needs both controls, not the stronger-only one) — a different rule from `docs/standards/DATA_CLASSIFICATION_STANDARDS.md` §2's "strongest wins" rule, because these are two different problems: classification picks *one* handling level for *one* data element, while a single threat can legitimately require *multiple, independent* controls.

## 4. Threat register (condensed — full fields in `scripts/security/threat-model.ts`)

| ID | Area | STRIDE | Likelihood | Impact | Rank | Control status | Owner |
|---|---|---|---|---|---|---|---|
| `THR-001` | tenants | Info. disclosure, elevation | medium | critical | **critical** | planned_phase1 | Architecture/Security |
| `THR-002` | tenants | Tampering | medium | critical | **critical** | planned_phase1 | Architecture/Security |
| `THR-003` | access | Elevation | low | critical | high | planned_phase1 | Architecture/Security |
| `THR-004` | admin | Repudiation, tampering | medium | high | high | gap_disclosed | Product/Governance |
| `THR-005` | access | Elevation | medium | medium | medium | planned_phase1 | Architecture/Security |
| `THR-006` | apis | Elevation | medium | high | high | planned_phase1 | Backend/Security |
| `THR-007` | apis | Elevation, info. disclosure | medium | medium | medium | planned_phase1 | Backend/Security |
| `THR-008` | apis | Denial of service | medium | medium | medium | planned_phase1 | Backend/DevOps |
| `THR-009` | jobs | Denial of service | medium | medium | medium | planned_phase1 | Backend/DevOps |
| `THR-010` | jobs | Elevation | low | high | medium | planned_phase1 | Backend/Security |
| `THR-011` | files | Tampering, info. disclosure | low | critical | high | planned_phase1 | Backend/Security |
| `THR-012` | files | Info. disclosure | low | critical | high | planned_phase1 | DevOps/Security |
| `THR-013` | integrations | Spoofing, repudiation | medium | high | high | planned_phase1 | Backend/Security |
| `THR-014` | integrations | Info. disclosure, elevation | medium | medium | medium | **existing** | DevOps/Security |
| `THR-015` | finance | Tampering | low | critical | high | planned_phase1 | Finance/Security |
| `THR-016` | finance | Repudiation | low | medium | low | **existing** | Product/Governance |
| `THR-017` | finance | Info. disclosure | medium | medium | medium | planned_phase1 | Backend/Security |
| `THR-018` | operations | Info. disclosure | medium | medium | medium | gap_disclosed | DevEx |
| `THR-019` | operations | Info. disclosure | low | critical | high | **existing** | DevOps/Security |
| `THR-020` | operations | Denial of service | low | high | medium | **existing** | DevOps |
| `THR-021` | ui | Tampering | medium | high | high | planned_phase1 | Frontend/Security |
| `THR-022` | ui | Spoofing, tampering | medium | high | high | planned_phase1 | Frontend/Security |
| `THR-023` | operations | Tampering, DoS | medium | critical | **critical** | planned_phase1 | DB Engineer/QA |
| `THR-024` | operations | Tampering, DoS | medium | critical | **critical** | planned_phase1 | DevOps |
| `THR-025` | admin | Elevation | low | critical | high | planned_phase1 | Backend/Security |

**Summary (reproduced by `pnpm run threat-model:check`'s own output, not hand-counted):** 25 entries — 4 `critical`, 11 `high`, 9 `medium`, 1 `low`. 4 entries have an **existing** control this build has already implemented and tested (`THR-014`, `THR-016`, `THR-019`, `THR-020` — `PH0-93`/`94`'s observability/security-baseline work); 2 entries are **disclosed, accepted gaps** (`THR-004`'s RPD-022 exception, `THR-018`'s `ISS-2026-007` dependency-audit gap) rather than false "resolved" claims; the remaining 19 are **planned for Phase 1+**, each naming its owning workstream document, not fabricated as already mitigated.

## 5. Critical-risk entries (§21 "Main flow": credible threat maps to owned control/task)

The 4 `critical`-ranked entries (`THR-001`, `THR-002`, `THR-023`, `THR-024`) all share one property: each is **already fully specified** by a `VERIFIED` architecture document's binding control (RLS policy family and negative test #1/`TI-001` for `THR-001`; server-derived-only `tenant_id` and `TI-003` for `THR-002`; the mandatory clean-rebuild-**and**-upgrade migration test pair for `THR-023`; the joint storage-and-metadata restore-validation rule for `THR-024`) — none is an unowned or contradictory path (Prompt 96 §23's exception-flow trigger), so none blocks Phase 0 closure. Each is correctly `planned_phase1`, not fabricated as already mitigated with no code to back the claim (§25: "no control is credited without evidence/plan").

## 6. Accepted risks (Prompt 96 §24, restated verbatim across every governance document — not reinterpreted here)

- **RPD-022** (Supreme Admin absolute CRUD): compensating control is the mandatory audit-trail entry (negative test #9) and consistent disclosure (`THR-004`, `THR-016`) — never presented as prevented.
- **RPD-031/037** (contract-silent recovery is best effort): no RPO/RTO guarantee is implied by this threat model's `THR-023`/`THR-024` entries — they name the *test coverage gap*, not a breach of a recovery commitment that was never made.
- **RPD-034/036** (direct GA, no external pilot, zero-critical-defect gate): every `planned_phase1` entry in §4 must close (or reach an explicit, Security-Lead-approved risk acceptance per `docs/architecture/10_TESTING_WORKSTREAM.md` §8.2's severity-based exit criteria) before the Go/No-Go decision this RPD pair governs — restated as a forward pointer, not re-litigated.

## 7. Update triggers and monitoring (§20 task 4)

This register is updated, not replaced, when: (a) a Phase 1+ capability prompt ships the code a `planned_phase1` entry describes — that entry's `controlStatus` moves to `existing` with real evidence (a build log, a passing negative test) cited, matching how `THR-014`/`THR-016`/`THR-019`/`THR-020` are already evidenced; (b) a new attack surface is architected (new integration category, new file type, new public API) — a new entry is added, never silently folded into an existing one; (c) a real incident occurs — its post-incident record (`docs/runbooks/*.md` §6/§7 pattern) feeds back into this register's likelihood/impact, not a separate untracked note. `docs/standards/OBSERVABILITY_STANDARDS.md` §1's "Security events" dashboard and the Cross-tenant-policy-test-failure Sev1 alert are the live monitoring signals this register's tenant-isolation entries (`THR-001`–`003`, `THR-025`) will bind to once Phase 1 wires them (currently `NOT_RUN`, `docs/standards/OBSERVABILITY_STANDARDS.md` §7).

## 8. Validation (Prompt 96 §25/§28 — real, not merely documented)

`pnpm run threat-model:check` (`scripts/security/threat-model.ts`) proves: (1) no duplicate threat ID; (2) every entry has a non-empty owner and control description; (3) every entry's STRIDE category set is non-empty and valid; (4) `computeRiskRank()` is reproducible and monotonic in both dimensions (proven by exhaustive pairwise tests, not spot-checked); (5) no `critical`-ranked entry lacks an owner/control (the mechanical form of §23's exception-flow rule). All 25 real entries pass every check today.
