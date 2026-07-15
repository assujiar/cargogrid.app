# ADR-0003 — Runtime validation library for the environment schema

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: none pre-existing — new bounded decision raised and resolved this checkpoint   Owning phase/task: Phase 0 (`CG-S5-PH0-007`, Prompt 86, Environment Validation Foundation)

## Question

Prompt 86 requires a "typed schema" for environment-variable validation. `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` line 157 and `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` line 36/43 already name "Zod-or-equivalent" as the intended validator pattern for REST/GraphQL contract types (`server/contracts/<domain>/`, Phase 1+ scope). Which runtime validation library should this task adopt for the environment schema, and — since this is the first place any such library is actually installed — should that choice extend beyond just environment validation?

## Options

1. **Hand-rolled type guards.** No new dependency.
   - Trade-off: no declarative schema, no automatic type inference, cross-field rules and error aggregation would be reimplemented ad hoc — exactly the kind of thing a schema library exists to avoid duplicating per-project.
2. **Zod (SELECTED).** Declarative schemas with static type inference, already named by two existing architecture documents as the intended pattern for a different but related concern (API contract validation).
   - Trade-off: none material; it is a single, focused dependency (no transitive bloat), zero runtime dependencies of its own, and its adoption here is consistent with — not a new decision that could later conflict with — the already-ratified "Zod-or-equivalent" contract-validation pattern.
3. **Valibot / ArkType (or another alternative).** Newer, smaller-bundle competitors.
   - Trade-off: neither is named anywhere in the existing architecture documents; adopting one here would create a second validation-library precedent that `server/contracts/<domain>/` (Phase 1+) would then have to either match or diverge from, with no evidence-based reason to prefer either alternative over the already-named default.

## Decision

**Zod `4.4.3`** (current stable per the npm registry — verified this checkpoint, not asserted from memory). Adopted for the environment schema (`scripts/env/schema.ts`) now, and **recommended, not mandated**, as the same library for `server/contracts/<domain>/` request/response validation when Phase 1 reaches that slice — this ADR does not bind that future decision (a dedicated Phase 1 ADR should still confirm it against Phase 1's actual evidence), it only removes the "which schema library" question as an open unknown by establishing working precedent.

## Evidence

- `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` line 157: "request/response types and Zod-or-equivalent validators live in `server/contracts/<domain>/`."
- `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` line 36: "every mutation runs the same Zod-or-equivalent validator."
- Real, executed evidence this checkpoint: `npm view zod version` → `4.4.3` (current, non-prerelease); `pnpm add zod@4.4.3` installed cleanly into the already-validated toolchain from `ADR-0002`; `z.url()` and `z.enum()` (Zod 4's string-format and enum APIs) were verified working against real inputs before being relied upon in `scripts/env/schema.ts`; Zod's own issue objects were verified to never echo the rejected raw value (`safeParse` on an invalid URL produces `{ message: "Invalid URL" }`, no `received` field) — this is why `scripts/env/validate.ts` can safely surface Zod's `.message` strings directly in redacted error output.

## Consequences

- **DB/API/UI:** none now. Phase 1's `server/contracts/**` gets a working precedent, not a mandate.
- **Security:** positive — Zod's error objects don't leak rejected values, which is exactly the property `scripts/env/validate.ts` depends on for its "name the variable, never the value" redaction rule (Prompt 86 §24).
- **Performance:** negligible — one small, zero-dependency package; not measured as an SLA.
- **Migration/rollback:** trivial — `pnpm remove zod` plus reverting the two files that import it; nothing else in the repository depends on it yet.
- **Downstream impact:** Phase 1's `server/contracts/<domain>/` should default to Zod for consistency (recommendation, not a binding constraint on that future ADR); `PH0-091` (Testing Foundation) may reference this module as a real example of a Node-native-TS, dependency-light validation pattern.

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-86.md`; `README.md` "Environment variables"; `docs/adr/README.md` §6. Does not alter any CPD/RPD or any `docs/architecture/**` decision — it operationalizes the "Zod-or-equivalent" pattern those documents already named, for a Phase 0 concern (environment config) distinct from the Phase 1 concern (API contracts) they were describing.
