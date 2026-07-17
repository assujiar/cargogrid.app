# CargoGrid Data Classification Foundation

**Established by:** `CG-S5-PH0-016` (Prompt 95 — Data Classification Foundation)
**Status:** Active — taxonomy, handling matrix, retention mapping, and a real registry/validation mechanism are implemented and tested against this repository's actual Phase 0 assets. No domain schema/API/UI field exists yet to classify beyond what Phase 0 already created (`scripts/env/schema.ts`'s one `secret`-classified variable) — every future `server/contracts/<domain>/` field is classified at the moment it is authored (§5's adoption gate), not retroactively invented here.

This document distills `docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md` §10 ("Data classifications," reproduced from Tech Arch §12.4, already `VERIFIED`) and §11 ("Retention and legal-hold implications," RPD-025) — not re-derived — plus this checkpoint's own addition: a **sensitivity-level** axis (public/internal/confidential/restricted/credential) that `02_*.md` §10's field-group table does not itself name, needed to satisfy Prompt 95 §16's "primary scope" and to give §22's "strongest applicable handling" rule something concrete to compare.

## 1. Two-axis model (disclosed construction, not silently invented)

`02_*.md` §10 fixes **6 field groups** (Cost/margin, Finance, Payroll, PII, Security, Support) each with a `Default` handling description in prose ("Hidden unless permission," "Restricted," "HR/payroll only," "Need purpose/role," "Masked always; never exported plain," "Platform security only") — but does not name an ordered severity scale those defaults sit on, which Prompt 95 §16/§22 require (a `public`/`internal`/`confidential`/`restricted`/`credential` scale, and a rule for resolving a data element that carries more than one sensitivity). **This checkpoint constructs that scale from `02_*.md` §10's own prose defaults**, ordered weakest → strongest, and maps each field group onto it — a disclosed synthesis, not an invented one:

| Level (weakest → strongest) | `02_*.md` §10 field group(s) mapped here | Rationale |
|---|---|---|
| `public` | *(none of the 6 named groups — reserved for data explicitly safe to expose with no permission check, e.g. a customer-portal tracking number)* | No `02_*.md` §10 field group defaults to unrestricted exposure; `public` exists as the floor of the scale, not because a group maps to it |
| `internal` | *(none of the 6 — reserved for ordinary tenant-scoped operational data with no elevated sensitivity: shipment status, non-financial customer fields)* | Same reasoning — `02_*.md` §10 only catalogues the *sensitive* groups; ordinary operational data is implicitly everything not in that table, and `internal` is its floor |
| `confidential` | Cost/margin ("Hidden unless permission"), PII ("Need purpose/role") | Both defaults require a permission/purpose check but are not restricted to one named role class the way Payroll/Finance are |
| `restricted` | Finance ("Restricted"), Payroll ("HR/payroll only"), Support ("Platform security only") | All three defaults name a specific, narrow authorized class, not merely "permission required" |
| `credential` | Security ("Masked always; never exported plain") | The only group `02_*.md` §10 marks as *always* masked with *no* export path at all — strictly stronger than "restricted to a role," so it is the ceiling of the scale |

## 2. Sensitivity levels and ordering (`scripts/data-classification/registry.ts`)

`SENSITIVITY_LEVELS = ["public", "internal", "confidential", "restricted", "credential"]`, totally ordered weakest → strongest. `strongest(levels)` implements Prompt 95 §22 verbatim ("multiple sensitivities resolve to the strongest applicable handling") — a data element carrying both a `pii` (confidential) and a `security_credential` (credential) property is handled at `credential`, the maximum, never averaged or the first-listed.

## 3. Categories (`02_*.md` §10, reproduced not re-derived)

`CATEGORIES = ["cost_margin", "finance", "payroll", "pii", "security_credential", "support"]`, each with a `CATEGORY_DEFAULT_LEVEL` per §1's mapping. A registry entry may declare a **stronger** level than its category's default (e.g. a specific PII field an SME determines needs `restricted` handling) but never weaker — `validateRegistry()` (§6) enforces this as a hard rule, matching Prompt 95 §25's "strongest-rule precedence" validation requirement.

## 4. Handling matrix — 8 policy dimensions (`02_*.md` §10, reproduced verbatim: "visibility, editability, maskability, exportability, printability, filterability, API exposure, audit requirement")

| Level | Visible by default | Editable | Maskable | Exportable | Printable | Filterable | API-exposable | Audit required |
|---|---|---|---|---|---|---|---|---|
| `public` | Yes | Per normal RBAC | No | Yes | Yes | Yes | Yes | No |
| `internal` | Yes (tenant-scoped) | Per normal RBAC | No | Yes | Yes | Yes | Yes | No |
| `confidential` | No — needs purpose/role | Per normal RBAC + purpose check | Yes | Only with explicit export permission | Only with explicit permission | Yes, scoped | Yes, field-masked by default | Yes |
| `restricted` | No — named role class only (§1) | Named role class only | Yes | Only with named-role export permission, logged | Only with named-role permission, logged | Only within named role's own scope | Only to the owning named role's authenticated context | Yes, privileged-access class |
| `credential` | Never (masked always, `02_*.md` §10) | System-managed rotation only (`ADR-0010`, `SECURITY_STANDARDS.md` §2) | Always, no unmask path | **Never** (`02_*.md` §10: "never exported plain") | Never | No | Never in a response body — reference/fingerprint only (`scripts/observability/logger.ts`'s `redact()` pattern) | Yes, every access |

This table is the binding target every Phase 1+ `server/contracts/<domain>/` field's classification resolves to — a field-level policy engine (Phase 1, `06_RLS_RBAC_WORKSTREAM.md` §4's field-level security layer) implements these 8 columns per field, it does not re-derive them.

## 5. Retention mapping (RPD-025, `02_*.md` §11, reproduced verbatim)

| Category | Retention class | Retention period | Note |
|---|---|---|---|
| `finance` | Finance/tax | 10 years | Journal, invoice, vendor bill, payment, settlement, tax documents (`02_*.md` §11) |
| `security_credential` | Audit/security | 7 years | The *audit trail of* credential access/rotation, not the credential value itself, which is never retained past rotation (§4's `credential` row) |
| `support` | Audit/security | 7 years | Support-access/impersonation logs (`02_*.md` §11's `AUD` platform primitive) |
| `cost_margin`, `pii` | Operational | Contract term + 90 days | Unless the specific field is itself finance/tax-classified (e.g. an invoiced cost) |
| `payroll` | **Disclosed gap, not silently assumed** | Treated as Finance/tax (10 years) by inference | RPD-025's "Applies to" column (`02_*.md` §11) does not explicitly itemize payroll records; Indonesia payroll/tax record-keeping norms (`AGENTS.md`: "Indonesia tax/payroll logic requires current, dated SME/legal evidence") make the 10-year Finance/tax class the safer assumption, but this is flagged here as needing confirmation at Phase 4 Finance's HRIS/payroll schema design (`ADR_REQUIRED`), not asserted as already-ratified |

`RPD-022`/RISK-004 (restated, `02_*.md` §11): Supreme Admin's absolute CRUD authority can defeat every retention class above — never presented as a guaranteed retention, in every document that states one (this one included).

## 6. Registry mechanism and validation (`scripts/data-classification/registry.ts`, `check-registry.ts`)

A `ClassificationEntry` (`id`, `category`, `level`, `owner`, `description`) is the atomic registered fact — one entry per known sensitive field/variable this repository actually has today. `validateRegistry(entries)` enforces (Prompt 95 §25):

1. Every entry has a non-empty `owner` (§18 audit requirement: "classification changes, owner ... are auditable" — an unowned entry is a validation failure, not a warning).
2. Every entry's `level` is `>=` its `category`'s `CATEGORY_DEFAULT_LEVEL` (§3's strongest-or-equal rule) — a `finance`-category entry declared `internal` is rejected.
3. No duplicate `id`.

`scripts/data-classification/check-registry.ts` (`pnpm run data-classification:check`, wired into CI) additionally cross-checks this repository's own real state: **every `secret`-classified variable in `scripts/env/schema.ts` has a matching `security_credential`/`credential` registry entry** — closing Prompt 95 §23's "unknown/conflicting/unowned classification blocks exposure" rule with a real, mechanical, CI-enforced gate today, not merely a documented intention. As of this checkpoint, this is exactly one variable (`SUPABASE_SERVICE_ROLE_KEY`) — registered in `scripts/data-classification/registry.ts`'s `PHASE_0_REGISTRY`.

## 7. Adoption gate for later prompts (Prompt 95 §20 task 4, binding)

Every Phase 1+ capability prompt that adds a `server/contracts/<domain>/` field, a `files` row's `classification` column value (`05_DATABASE_SCHEMA_WORKSTREAM.md` §"File metadata/quarantine"), a log/export/analytics field, or a new environment variable **must** add or reference a `ClassificationEntry` (§6) before that field ships — resolving its category (§3), confirming its level is at least its category's default (§3's rule), and naming an owner. A field with no registry entry is, per Prompt 95 §23's exception flow, blocked from exposure/export/logging until classified — this is the mechanical meaning of "no unresolved placeholder may pass" (§25) applied to data classification specifically. `check-registry.ts`'s env-variable cross-check (§6) is the first real instance of this gate; Phase 1's first `server/contracts/<domain>/` file extends the same script to cover contract fields, not a second, competing check.

## 8. What is `NOT_RUN` yet (named, not silently skipped)

| Item | Why not real yet | Owning future task |
|---|---|---|
| Field-level policy engine enforcing §4's 8-dimension matrix at query/API time | No schema/API exists | Phase 1 Platform Core, `06_RLS_RBAC_WORKSTREAM.md` §4 |
| `files.classification` column values wired to this registry | No `files` table exists yet | Phase 1, `05_*.md`'s file-metadata slice |
| Per-domain `server/contracts/<domain>/` registry entries | No contract exists yet | Each domain's own owning Phase 1+ prompt (§7's adoption gate) |
| Payroll retention class confirmation | No Finance/HRIS SME evidence exists yet (§5's disclosed gap) | Phase 4 Finance / Phase 7 HRIS |
