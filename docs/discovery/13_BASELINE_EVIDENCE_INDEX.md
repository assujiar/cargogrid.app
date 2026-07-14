# 13 — Baseline Evidence Index

**Prompt:** `CG-S2-DISC-013` (`CG-AABPP-DISC-033` v0.3.0), output 2 of 2
**Runtime output of:** `docs/ai-agent-build-prompt-package/02-discovery/33_BASELINE_EVIDENCE_CAPTURE_PROMPT.md`
**Status:** `VERIFIED`

## Evidence schema

Each evidence ID below has: source document, evidence class (`OBSERVED` = read directly from tracked files; `EXECUTED` = a read-only command was run; `INFERRED` = derived from an absence pattern documented elsewhere; `UNAVAILABLE` = could not be produced safely), checkpoint, and a one-line description.

## Indexed evidence

| Evidence ID | Source | Class | Checkpoint | Description |
|---|---|---|---|---|
| EV-13-001 | `docs/discovery/01_REPOSITORY_INVENTORY.md` | `EXECUTED` | `d587445` | Repository topology, 455 tracked files, 100% Markdown + 1 sha256 |
| EV-13-002 | `ERROR_LEDGER.md` `ERR-2026-001` | `OBSERVED` | `d587445` | Prior-version corruption of EV-13-001's source file, detected and repaired |
| EV-13-003 | `docs/discovery/02_EXISTING_IMPLEMENTATION_AUDIT.md` | `INFERRED` | `d587445` | Zero platform/domain capability implemented, derived from EV-13-001's extension/manifest search |
| EV-13-004 | `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` | `EXECUTED` | `d587445` | No package manager/manifest/lockfile/CI exists |
| EV-13-005 | `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md` | `INFERRED` | `d587445` | No database/migration/schema exists; no live target contacted |
| EV-13-006 | `docs/discovery/05_ROUTE_MODULE_INVENTORY.md` | `EXECUTED` | `d587445` | No routing directory (`app/`, `pages/`, `src/`, `api/`) exists |
| EV-13-007 | `docs/discovery/06_SECURITY_BASELINE.md` | `INFERRED` | `d587445` | No security control implemented; no secret/credential found |
| EV-13-008 | `docs/discovery/07_TEST_QUALITY_BASELINE.md` | `EXECUTED` | `d587445` | No test/config/CI exists; baseline `UNKNOWN` |
| EV-13-009 | `docs/discovery/08_PERFORMANCE_BASELINE.md` | `UNAVAILABLE` | `d587445` | No measurable build/route/query exists; baseline `UNKNOWN` |
| EV-13-010 | `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` | `UNAVAILABLE` | `d587445` | No UI exists; baseline `UNKNOWN` |
| EV-13-011 | `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` | `OBSERVED` | `d587445` | `tes.md` (empty placeholder, `PH-001`); `docs/runtime/*` duplication (`PH-002`, mitigated) |
| EV-13-012 | `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` | `OBSERVED` | `d587445` | 9 consolidated register items, deduplicated across Prompts 22–30 |
| EV-13-013 | `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` | `OBSERVED` | `d587445` | `GREENFIELD`, High confidence, no dissent |

## Checksum/checkpoint information

All 13 discovery documents (01–12 plus this index and the execution index) carry a `.sha256` sidecar computed at write time. Table below reflects hashes **after** reconciling this branch with `main`'s `CG-S2-DISC-001-R1` (see §"Merge reconciliation" below): `01_REPOSITORY_INVENTORY.md` was replaced with `-R1`'s version; `02`, `05`, `10`, `11`, `12`, `14` were lightly edited to correct `KI-00X` references onto `-R1`'s `ISS-2026-00X` IDs and root-ledger paths onto `docs/runtime/`; `03`, `04`, `06`, `07`, `08`, `09` are unchanged.

| Document | SHA-256 |
|---|---|
| `01_REPOSITORY_INVENTORY.md` | `8eaae04d3fadb241a51639150bb926988546309ecc562389dda44ae4126a428a` (from `CG-S2-DISC-001-R1`) |
| `02_EXISTING_IMPLEMENTATION_AUDIT.md` | `93c64f7ea4f3cccada6af0815a66a00d6fd98ad586d720cb83309e657ae3522f` |
| `03_TOOLCHAIN_DEPENDENCY_BASELINE.md` | `4a386e9843c20971f1a4a191f17645e9345dcd03e5e3b98137ef3fc0ba15d90a` |
| `04_DATABASE_MIGRATION_BASELINE.md` | `61fe47233d1e576b48b35c9a79307aa59f1890e2f53a4f2ea01f6444efff75ea` |
| `05_ROUTE_MODULE_INVENTORY.md` | `135088b35110d6e6115176a1e90ae8dd9ce1d14ea89af8d4bc4235c398abf53d` |
| `06_SECURITY_BASELINE.md` | `b5f7faa90bba0b6d80b69fe8b77d63b5e542587d4b4e6b3b69ad3844ab32bc1b` |
| `07_TEST_QUALITY_BASELINE.md` | `8520af7cb963527c386700057e6cdae65a0fbc1b21b10910c9006fbf3c6c2f5a` |
| `08_PERFORMANCE_BASELINE.md` | `c8c12bb82ae7dc73b69dd6e1c1607d3302546765fe0c013aaed731ddfdd48955` |
| `09_ACCESSIBILITY_UX_BASELINE.md` | `d6c33999e6c4a1e34db0d9c4b419f37c526be666b2b167dde7943f2062759c0a` |
| `10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` | `9660697efe53635733a9cba4eb194178e2e61b250556f26e620df97bec0b7175` |
| `11_TECHNICAL_DEBT_RISK_REGISTER.md` | `9b21b4e6dbb12682e4e61cc63666d928b178795821d9802a05942b0da6848e34` |
| `12_GREENFIELD_BROWNFIELD_DECISION.md` | `1262bd2c6bed026ffe6d3d0ab866014fef15c124a51215a9f4a7716473acff20` |

### Merge reconciliation

This branch (`claude/eloquent-mayer-s40hn4`) was cut before `main`'s `CG-S2-DISC-001-R1` reconciliation merged. Both independently fixed the same Prompt-21 corruption with opposite canonical-context decisions. Reconciling: `-R1`'s `docs/runtime/` canonical location was kept; this branch's Step 2 discovery deliverables (Prompts 22–34) were kept and re-homed under it. Full detail: `docs/discovery/14_STEP2_CLOSURE_REPORT.md` §13, `docs/runtime/CHANGE_MANIFEST.md` `CHG-2026-003`.

## Redaction record

Only one redaction class applies across all Step 2 evidence: the git remote URL's embedded credential segment (`http://REDACTED@127.0.0.1:41729/...`). No other secret, token, personal data, sensitive business data, signed URL, or internal endpoint was encountered at any point in Prompts 21–33, because no such content exists in a 100%-Markdown, application-free repository.

## Limitations

- Prompts 28 and 29 (performance, accessibility) produced no `MEASURED`/`TESTED` evidence class — only `UNAVAILABLE`/`NOT_FOUND` — because no application exists to measure or test. This is a scope limitation of the checkpoint, not a gap in this evidence-capture task.
- Prompt 30's marker search (TODO/FIXME/etc.) was deliberately scoped to filenames, not full-text content, to avoid false positives from the prompt package's own reference material discussing these terms conceptually (documented in `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md`).

## Contradictions

One contradiction was found and resolved: the two divergent copies of Prompt 21's output (see EV-13-002) claimed different checkpoints and branch names in a single file. Resolved by full rewrite at the current checkpoint; both prior branches are ancestors of the resolved checkpoint, so no evidence was discarded, only reconciled.

No other contradiction (count mismatch, classification conflict, or unexplained worktree change) was found across Prompts 21–33.

## Missing evidence

None required for Step 2 closure. RISK-008 (`tes.md` deletion) and RISK-009 (`.gitignore` timing) are intentionally deferred to Phase 0 and are not missing evidence — they are correctly-scoped future work.

## Stale-evidence rules

Any Step 2 document whose cited checkpoint (`d587445`) no longer matches `git rev-parse HEAD` at the time it is read must be treated as `STALE` and re-verified before being relied upon, per the rule already stated in each document's §1/§0 checkpoint section.

## Cross-reference health

All 13 discovery documents cite the same checkpoint (`d587445`) and branch (`claude/eloquent-mayer-s40hn4`). All internal cross-references (e.g. Prompt 31 citing Prompt 30's `PH-001`/`PH-002`, Prompt 32 citing Prompts 22–31) resolve to real IDs in the cited documents — verified by direct comparison while authoring this index.

## Completion gate

All Step 2 evidence is indexable from a fresh context via this file and `00_EXECUTION_INDEX.md`. No sensitive value is present. The one contradiction found is resolved and explained. Persistent records (`CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, `HANDOFF.md`) are reconciled in the same checkpoint (see `CHANGE_MANIFEST.md`). This task does **not** declare `RUNTIME_DISCOVERY_VERIFIED` — that determination belongs to Prompt 34.

Output hash: `docs/discovery/13_BASELINE_EVIDENCE_INDEX.sha256`. Next eligible prompt: `CG-S2-DISC-014` — Step 2 Closure Verification.
