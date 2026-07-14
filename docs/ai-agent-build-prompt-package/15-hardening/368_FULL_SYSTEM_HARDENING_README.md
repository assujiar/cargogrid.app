# Step 15 — Full-System Hardening Prompt Package

**Package version:** `0.16.0`  
**Package document:** `CG-AABPP-HDN-368`  
**Directory:** `15-hardening/`  
**Runtime prerequisite:** `PHASE_9_VERIFIED`  
**Next phase unlocked by runtime closure:** Step 16 only after Prompt 389 verifies full-system hardening.

This package decomposes Step 15 into atomic AI-agent hardening prompts. It does not add product features and does not claim runtime implementation. Its purpose is to verify, attack, repair and document the integrated CargoGrid system before release-candidate and go-live prompts.

## Included source scope

Step 15 minimum scope:

- Full regression.
- Cross-module transactional integrity.
- Tenant isolation audit.
- RLS and RBAC audit.
- Financial integrity audit.
- Data lineage audit.
- API compatibility audit.
- Storage and signed URL audit.
- Security hardening.
- Performance and scalability.
- Accessibility.
- Browser/device compatibility.
- Observability.
- Backup/restore.
- Disaster recovery rehearsal.
- Data migration rehearsal.

## Non-negotiable gates

- No critical/high tenant isolation defect.
- No critical/high security defect.
- No unresolved financial integrity issue.
- No broken core E2E flow.
- Migrations apply cleanly.
- Backup and restore tested.
- DR rehearsal completed according to gate.
- Monitoring and alerting active.
- Runbooks available.
- No fake pass, hidden failure or disabled test.

## File map

| Prompt | File | Purpose |
| --- | --- | --- |
| 368 | `368_FULL_SYSTEM_HARDENING_README.md` | This package guide |
| 369 | `369_FULL_SYSTEM_HARDENING_WBS_RUNTIME_KICKOFF_PROMPT.md` | Runtime WBS/index kickoff |
| 370–385 | capability prompts | 16 atomic hardening prompts |
| 386 | `386_FULL_SYSTEM_HARDENING_INTEGRATED_VERIFICATION_PROMPT.md` | Cross-gate hardening verification |
| 387 | `387_RELEASE_BLOCKER_TRIAGE_REMEDIATION_PROMPT.md` | Blocker triage and bounded remediation |
| 388 | `388_FULL_SYSTEM_HARDENING_DOCUMENTATION_HANDOFF_PROMPT.md` | Documentation and Step 16 handoff |
| 389 | `389_FULL_SYSTEM_HARDENING_CLOSURE_VERIFICATION_PROMPT.md` | Independent hardening closure |

## Exact next command after Step 15 package validation

`LANJUT STEP 16`
