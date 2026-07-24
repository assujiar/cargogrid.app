# AI-Assisted Interaction Patterns

**Status: `DOCUMENTED_ONLY`, whole document.** No AI-generated content, suggestion, summary, or recommendation feature exists anywhere in this repository today (verified this checkpoint: no route, component, or backend capability references an LLM/AI provider, embedding, or generation call). This document fixes the binding interaction rules a future capability must satisfy *before* it ships, per this task's own instruction — it does not invent or schedule a specific AI feature (no roadmap prompt for one exists in `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md`'s phase list through Phase 9 by name; Phase 9 "Intelligence/Enterprise" is the most likely future home, not yet reached).

## Binding rule (this task's own instruction, restated as governance)

**AI output must never silently become authoritative business data.** Every pattern below exists to enforce that one rule at the interaction level.

## Patterns (specification only — no implementation)

| Pattern | Rule |
|---|---|
| AI suggestion | Rendered visually distinct from user-entered/system-computed data (a dedicated tone/border, never presented as if already committed) |
| AI summary | Always labeled as AI-generated; links back to its source records (never a summary with no traceable evidence) |
| AI-generated draft | Enters the same Draft state a human-authored draft would (`04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` §2's Create/Edit pattern) — never auto-published |
| AI recommendation | Presented with its confidence/evidence (see below), never as a bare directive |
| AI score | Numeric/categorical output always paired with the factors/evidence that produced it — never an opaque number |
| AI explanation | A human-readable rationale accompanies any score/recommendation/flag — "why" is not optional |
| Human approval | Every AI-generated change to canonical business data requires an explicit human approval action before it becomes authoritative — the same Approve/Reject pattern (`04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` §2) already governs human-proposed changes, applied identically here, not a separate weaker gate |
| Confidence indication | Never color-only (same non-color-status rule, `docs/standards/DESIGN_SYSTEM.md` §2.1) — a confidence level is a labeled value, not just a shade |
| Source and evidence | Every AI output that references underlying records links to them, resolved through the same RLS/field-masking a direct query would apply (`09_*.md` §7) — an AI feature is never a side channel around access control |
| Regeneration | Available without losing the prior version (audit trail of what was generated, when, and by which invocation — `09_*.md` §7's audit-disclosure principle extended to AI-originated changes) |
| Edit before apply | A human can edit AI output before it is applied — applying is never the only path from "generated" to "committed" |
| Reject suggestion | A first-class, frictionless action, logged the same as an accept (both are meaningful signal, not just the accept path) |
| Audit of AI-assisted actions | Every AI-assisted mutation is attributed and auditable exactly as a human-initiated one is (`AGENTS.md`'s audit/tenant/authorization rules apply without exception to an AI-originated call) — no "system" actor that evades the same audit discipline a human actor is held to |

No component, token, or route implements any of the above — this table is the acceptance checklist a future AI-feature checkpoint must satisfy, not a claim of present capability.
