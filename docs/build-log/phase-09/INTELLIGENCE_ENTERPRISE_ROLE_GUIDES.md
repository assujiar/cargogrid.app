# Phase 9 (Intelligence, Automation and Enterprise Expansion) Role Guides

**Produced by:** `CG-S14-IAE-038` (Prompt 366 — Intelligence, Automation and Enterprise Documentation Handoff), per Prompt 366 §31's own documentation-update list, mirroring `docs/build-log/phase-07/HRIS_TICKETING_ROLE_GUIDES.md` and `docs/build-log/phase-08/CUSTOMER_PORTAL_LOYALTY_ROLE_GUIDES.md`'s own structure two phases up.

**Companion document:** `docs/build-log/phase-09/INTELLIGENCE_ENTERPRISE_RUNBOOKS.md` — scenario-based diagnosis/resolution for when something has already gone wrong. This document answers a different question: for a given real Phase 9 authority tier, what real RBAC module:action tuple do they need, what can they do with it, what can they NOT do even with it, and what does a given error actually mean.

**How to use this document:** each section names the real, live, `VERIFIED` RPC surface and the exact module:action tuple gating it — never an aspirational or planned surface. Every capability cited is drawn directly from its owning build log (`docs/build-log/phase-09/IAE-330.md` through `IAE-365.md`) or a direct read of the owning migration. Where a role's authority is narrower than it might look — or, in several places this phase, was found to be accidentally WIDER than intended and had to be tightened by a Tier C review — that history is stated explicitly rather than smoothed over.

**Sanitization:** every tenant code, actor label, and figure below is fictional and deterministic, drawn from each capability's own already-sanitized db-test fixtures. No raw credential, secret, or private URL appears anywhere in this document.

**Standing, repository-wide facts every role guide below assumes:**
- **No live scheduler exists anywhere in this repository.** Every "recurring"/"scheduled"/"automated" mechanism named below is a real, callable, tested RPC with zero live cron/poller behind it (`ISS-2026-015`, standing, disclosed, unchanged by Phase 9).
- **No live MFA enrollment/verification UI or step-up enforcement exists yet.** The real MFA governance layer (`IAE-027`) is correct and independently tested, but `app.assert_current_step_up_authorization` has zero live callers anywhere in this repository today, including this same migration's own high-risk functions (`IAE-355.md` §8) — do not describe any action below as "requiring a fresh MFA verification" in practice; none currently do.
- **Every Phase 9 module reuses the SAME repository-wide RBAC evaluator, `app.evaluate_permission`** (`supabase/migrations/20260716104519_create_rbac_evaluator.sql`), and every module's own actions were seeded by direct `INSERT` into the pre-existing, open `app.entitlement_modules`/`app.permissions` registry (never a schema migration adding a new enum value) — mirroring the exact technique `IAE-007`'s own `INTHUB` seeding first established this phase.
- **No REST/GraphQL HTTP route exists for any Phase 9 capability named below except the real `/api/v1` gateway (`IAE-009`/`010`/`011`).** Every other route below is a Server Component/Action calling the `server/queries/`/`server/mutations/` layer, which calls the RPC directly.

---

## 1. Reporting and Analytics — Viewer and Configurator (`REP` module)

**What `REP` is, precisely:** a real, pre-existing Platform Core module (`PLT-106`/`PLT-111`, Phase 1) with `View`/`Export`/`Print`/`Configure` actions, seeded from the very first migration but **never consumed by any Phase 1-8 capability** — `IAE-002` (Reporting Engine, Prompt 330) is the module's first real user, and every reporting/dashboard/analytics capability since reuses it as the shared "configuring a cross-domain reporting artifact" authority (`IAE-331.md` §2 item 1).

**Entry points:** `app/(tenant)/[tenantSlug]/reports` (the cross-domain Report Library, `IAE-002`), `.../dashboards` (`IAE-003`), `.../saved-views` (`IAE-004`), `.../analytics` (`IAE-005`), `.../scheduled-reports` (`IAE-006`). All five reuse `resolveCommercialAccessForRequest`, the same domain-agnostic access gate — "any active, non-`customer_user`-layer tenant member may open the page," with `REP:Configure` gating the actual mutations server-side.

**`REP:View`** — a plain, non-privileged read tier. **No live Phase 9 RPC currently gates a read specifically on bare `REP:View`** — every read path this phase built instead relies on RLS's own "active tenant member, excluding the `customer_user` layer" predicate directly (e.g. `app.tenant_dashboards`'/`app.report_type_versions`' own SELECT policies), or on ownership (`app.list_saved_report_views` — any tenant member sees their OWN saved views regardless of any `REP` grant, plus every `tenant`-shared view). Holding `REP:View` alone is a real, valid role-administration state, just one that predates any Phase 9 RPC checking it directly.

**`REP:Configure`** — the real gate on every mutation this workstream added:

| Task | Real RPC | Notes |
|---|---|---|
| Publish a new report-definition version (parameter schema, source function) | `app.publish_report_type_version` | **Supreme-Admin-only**, not `REP:Configure` — reports are a product-feature catalogue, not a tenant-authored config object (`IAE-330.md` §2 item 4); no interactive UI, by design |
| Create/edit/publish/rollback a tenant dashboard | `app.create_tenant_dashboard_draft`/`add_dashboard_widget`/`remove_dashboard_widget`/`publish_tenant_dashboard_version`/`rollback_tenant_dashboard` | `REP:Configure`-gated; a widget always binds to an existing, active `app.report_types` code — never a raw SQL shape |
| Create/update/delete a `tenant`-SHARED saved view | `app.create_saved_report_view`/`app.update_saved_report_view`/`app.delete_saved_report_view` | `REP:Configure`-gated **only for `sharing_scope='tenant'`** — a `private` view needs nothing beyond ordinary, non-`customer_user`-layer tenant membership (`IAE-332.md` §2 item 4) |
| Register/refresh a materialized analytics view | `app.register_analytics_view`/`app.refresh_analytics_view` | **Supreme-Admin-only** — a refresh is a single, cross-tenant, shared-infrastructure operation, never a per-tenant action (`IAE-333.md` §2 item 5) |
| Create/pause/resume/archive/run a scheduled report; add/remove a recipient | `app.create_scheduled_report`/`app.set_scheduled_report_status`/`app.add_scheduled_report_recipient`/`app.remove_scheduled_report_recipient`/`app.run_scheduled_report` | All `REP:Configure`-gated |
| Cancel a still-queued report export | `app.cancel_report_run` | Requester OR `COM:Export` OR `REP:Export` (widened after a Batch 1 Tier C finding that hardcoded only `COM:Export` — a `REP:Export`-only holder previously had no override-cancel path at all, `IAE-330.md` §13 Finding 12) — the **one** place this workstream ALSO recognizes a second module (`COM`), for backward compatibility, never narrowed |

**Common errors and what they mean:**
- `report_unsafe_parameters` — a run/export omitted a `required: true` parameter the report type's CURRENT published version declares, or supplied one of the wrong `jsonb` type. Every pre-Phase-9 report code has an intentionally empty `parameter_schema` (`{}`) and accepts an arbitrary parameter bag unchanged — this error can only fire for a report whose schema has been genuinely published with real required fields.
- `report_run_not_found` on `cancel_report_run` — covers BOTH a genuinely missing run id and a real, cross-tenant one; a same-tenant colleague who is neither the requester nor holds `COM:Export`/`REP:Export` instead gets a distinguishable `insufficient_authority` (no cross-tenant enumeration risk, but no same-tenant leak-avoidance need either).
- `automation_rule_publish_content_changed`-style staleness is NOT a concern here — saved views instead surface `isStale` as a non-blocking UI flag (comparing the view's own stamped `report_type_version_id` against the report's current version) that still lets the view run; the underlying report's own live parameter validation is the real gate.
- `scheduled_report_not_active` — attempting to run a `paused`/`archived` schedule; resume via `set_scheduled_report_status` first.
- A materialized-view refresh returning `reconciled=false` is not necessarily a defect — see the companion runbooks document, runbook 1, for the disclosed race this can reflect.

**What this role can NEVER do, even holding `REP:Configure`:** publish a new report-type DEFINITION version (Supreme-only), register or refresh the shared analytics materialized view (Supreme-only), or bypass a scheduled report's own LIVE per-run recipient reauthorization (every recipient is re-checked against real, current tenant membership at run time, never merely at add time, regardless of who configured the schedule).

---

## 2. Automation and Integration Configurator (`INTHUB` module)

**What `INTHUB` is, precisely:** a real module ratified in `docs/architecture/01_MODULE_DEPENDENCY_MAP.md` §2.1 ("Integration Hub, automation rules, public/customer/vendor API, webhooks, n8n," Prompts 335-341) and first seeded by `IAE-007` (Automation Rule Engine) — the single authority tier spanning the Automation Rule Engine, Integration Hub, and every non-AI provider adapter this phase built (Prompts 342-346 each compose `IAE-008`'s own connection primitives directly, never a per-adapter parallel credential store).

**`INTHUB:Configure`** gates every mutation across this whole workstream:

| Domain | Real RPC | Notes |
|---|---|---|
| Automation rules | `app.create_automation_rule`/`app.set_automation_rule_definition`/`app.dry_run_automation_rule`/`app.request_automation_rule_publish_approval`/`app.decide_automation_rule_publish_approval`/`app.publish_automation_rule_version`/`app.set_automation_rule_status` | Publish is gated by a REAL, separate approval step (the Platform Approval Engine, `PLT-123`, via a domain-scoped proxy) — a rule can never publish itself, even for an `INTHUB:Configure` holder who authored the draft |
| Integration connections | `app.create_integration_connection`/`app.update_integration_connection_config`/`app.rotate_integration_connection_credential`/`app.set_integration_connection_status`/`app.record_integration_health_check` | The raw credential is never readable by ANY `INTHUB:Configure` holder through any RPC — only rotatable (write-only) |
| Webhook endpoints | `app.register_webhook_endpoint`/`app.rotate_webhook_secret`/`app.disable_webhook_endpoint`/`app.reenable_webhook_endpoint` (PLT-129, unmodified) plus `app.send_test_webhook_delivery`/`app.replay_webhook_delivery` (`IAE-012`, staff-only) | The signing secret is likewise write-only after initial registration |

**`INTHUB:View`** — read tier for `app.list_webhook_endpoints_for_tenant`, `app.list_webhook_deliveries_for_tenant`, `app.list_webhook_event_types`, and the Integration Hub's own connection/health-history reads.

**`register_integration_adapter`/`register_n8n_allowlisted_action` are Supreme-Admin-ONLY, never `INTHUB:Configure`** — adding a brand-new adapter TYPE to the catalog, or a brand-new permission scope to n8n's own allowlist, is a platform-catalogue decision, structurally distinct from configuring an already-registered adapter's own tenant connection (`IAE-336.md` §2 item 6 — a real, self-caught grant correction before commit, since the function's own `is_supreme_admin` check validates the CLAIMED actor, never the calling session, unless the grant itself is restricted to `service_role`).

**The n8n dual-gate model — the clearest concrete illustration of `INTHUB:Configure`'s own real limits (`IAE-341.md`):** `app.create_n8n_connector` (staff-only: `tenant_admin` layer or Supreme) requires EVERY requested scope to pass TWO independent gates — (a) present on the small, Supreme-curated `app.n8n_action_allowlist` (seeded with only `OPS:View`/`PRC:View`/`TKT:View`/`TKT:Create`/`INTHUB:View` — deliberately excluding every Approve/Delete/Override/financial scope), AND (b) already held by the creating actor's own current RBAC (delegated, unmodified, to `app.create_api_key`). A staff member requesting a fictional or deliberately-excluded scope (e.g. `TKT:Delete`) is rejected with `n8n_scope_not_allowlisted` BEFORE their own RBAC is even consulted — holding `INTHUB:Configure` does not itself expand what n8n may be trusted with; the allowlist is a genuinely separate, Supreme-controlled ceiling.

**Common errors and what they mean:**
- `automation_rule_publish_approval_mismatch` — an approved request is bound to a DIFFERENT rule's draft than the one being published; a genuinely stale approval also now correctly blocks publish since a `md5` content hash frozen at approval time is re-verified against the draft's CURRENT content (`automation_rule_publish_content_changed`, added after a live-reproduced Critical finding that a draft could be approved, then silently swapped for entirely different, never-reviewed actions before publishing — `IAE-335.md` §13 Finding 2).
- `automation_action_workflow_instance_not_found` on a fired rule's own `transition_workflow` action — folds a genuinely missing instance AND a real cross-tenant one into the identical error, after a live-reproduced Critical finding that a dual-tenant-membership actor could fire tenant A's own rule against tenant B's own real workflow instance with zero tenant filter (`IAE-335.md` §13 Finding 1).
- `n8n_scope_not_a_real_permission`/`n8n_scope_not_allowlisted` — the two distinct rejection reasons for a bad n8n scope; the first means the scope string does not even match a real, currently-registered `app.permissions` code, the second means it is real but not on the curated allowlist.
- `integration_connection_not_found` — folds a genuinely missing connection and a real cross-tenant one identically.
- `webhook_delivery_not_replayable` — attempting to replay a delivery that is not currently `dead_letter` (including a delivery a concurrent replay already moved out of that state — see the companion runbooks document, runbook 2, for the concurrency history here).

**What this role can NEVER do, even holding `INTHUB:Configure`:** register a brand-new integration ADAPTER type or a brand-new n8n allowlist SCOPE (both Supreme-only); publish an automation rule version without a genuinely separate, matching approval; read the raw value of any integration credential or webhook signing secret through any RPC (both are write-only by construction).

---

## 3. AI Reviewer and Approver (`AI` module — `Create`/`View`/`Approve`)

**What `AI` is, precisely:** a brand-new module registered by `IAE-019` (AI Governance Provider Boundary, Prompt 347) — the governance FOUNDATION every downstream AI-assisted capability (OCR, predictive ETA, optimization, fraud/risk, forecasting/recommendation, AI-assisted quotation — Prompts 348-353) builds on, mirroring what `INTHUB` is for provider integrations. Provider CONNECTION setup itself deliberately stays under the pre-existing `INTHUB:Configure` — this module governs only the request/outcome/approval evidence layer.

**The three tiers, deliberately distinct, live-proven to be enforced as three SEPARATE gates, not merely three names for one grant (`IAE-347.md` §7):**

| Action | Real RPC | Notes |
|---|---|---|
| `AI:Create` | `app.get_ai_governed_dispatch_info`, `app.request_ai_governed_action` | The entry point every downstream capability calls BEFORE dispatching to the AI provider — rejects a blank `feature_code` and any secret-shaped key in the CALLER-authored prompt payload |
| `AI:View` | `app.list_ai_governed_requests_for_tenant` | Read-only visibility into the evidence ledger, filterable by `feature_code` |
| `AI:Approve` | `app.decide_ai_output_approval` | A GENUINELY SEPARATE action from `AI:Create` — a rep who can request/create an AI-assisted output cannot also decide its own required human approval unless SEPARATELY granted `AI:Approve` |

**`app.request_ai_output_approval` is reachable by any `AI:Create`/`AI:View` holder** (it is a request, not a decision) — but it can only ever be requested for a request that has already reached `status='succeeded'` (`ai_governed_request_not_succeeded`), and only once a tenant has genuinely published its own `approval:ai_output_acceptance` config version via the Platform Approval Engine (`ai_output_acceptance_approval_not_configured` otherwise — this is a real tenant-configuration precondition, not a bug).

**`record_ai_governed_request_outcome` is `service_role`-only** — no human ever calls this directly; it is the real dispatch client's own outcome-recording call, and its own atomic pending-only transition is exactly what a live-reproduced Critical concurrency finding closed (see the companion runbooks document, runbook 3).

**Common errors and what they mean:**
- `ai_governed_request_secret_shaped_key` — a credential-shaped key name (e.g. `bank_account_number`) in a PROMPT payload; this rejects outright, since prompt content is caller-authored. The identical shape in an OUTPUT payload instead REDACTS the value rather than rejecting — a real, deliberate asymmetry (output is provider-controlled, untrusted content whose evidence should never be entirely lost over one plausible-looking key name, `IAE-347.md` §13).
- `ai_governed_request_not_pending` — the atomic outcome-recorder's own guard; a losing concurrent caller gets this, never a silent overwrite.
- `ai_output_approval_wrong_domain` — `decide_ai_output_approval` refuses to decide a foreign-domain approval step by name, never a generic "decide any step" bypass.
- `insufficient_authority` from `decide_ai_output_approval` almost always means the caller holds `AI:Create`/`View` but not the separate `AI:Approve` tier — this is the intended, load-bearing separation this section names, not a misconfiguration to "fix" by granting the caller everything.

**What this role can NEVER do, structurally, regardless of any grant combination:** cause AI output to autonomously write to any domain table — no function anywhere in this migration or its downstream consumers grants INSERT/UPDATE/DELETE authority to AI output itself; every domain effect still runs through that domain's own, unmodified, human- or system-initiated RPC, with the AI governance ledger as evidence only, never as the write path itself.

---

## 4. Enterprise IAM Administrator (`IAM` module — `Configure`/`View`)

**What `IAM` is, precisely:** a brand-new module registered by `IAE-026` (Enterprise IAM: SSO/SAML/OAuth/SCIM, Prompt 354) — the first Group 7 capability, and the first Phase 9 capability with no AI provider dispatch of any kind. Connection CRUD for the underlying IdP integration itself stays under the pre-existing `INTHUB:Configure` (an SSO connection is still, structurally, an Integration Hub connection) — every genuinely IAM-SPECIFIC action (domain claims, claims resolution, activation, SCIM, reads) is gated on `IAM:Configure`/`IAM:View` instead.

| Task | Real RPC | Notes |
|---|---|---|
| Request/verify/activate/disable an email-domain SSO claim | `app.request_enterprise_sso_domain_claim`/`app.verify_enterprise_sso_domain_claim`/`app.activate_enterprise_sso_domain_claim`/`app.disable_enterprise_sso_domain_claim` | `IAM:Configure`-gated; anti-takeover partial unique index on `email_domain` while claimed prevents a second tenant from claiming the same domain |
| Test-resolve a claims payload against a connection | `app.resolve_enterprise_sso_claims` | `IAM:Configure`-gated administrative claims-test tool; the ONLY mechanism that produces the `matched` evidence row `activate_enterprise_idp_connection` requires |
| Activate an IdP connection for live login | `app.activate_enterprise_idp_connection` | `IAM:Configure`-gated (a real, corrected requirement — see below) **AND** the underlying `app.set_integration_connection_status`'s own `INTHUB:Configure` requirement — a caller needs BOTH grants |
| Provision/deprovision a SCIM identity link | `app.provision_scim_identity` | `IAM:Configure`-gated; a real deactivate/reactivate enforcement (composing `app.revoke_auth_identity`/the newly-added `app.reactivate_auth_identity`); a genuinely new external identity with no matching platform user is disclosed-rejected, never fabricated |
| Read connections/domain claims/login attempts/SCIM events | `app.list_enterprise_idp_connections_for_tenant`/`app.list_enterprise_sso_domain_claims_for_tenant`/`app.list_enterprise_sso_login_attempts_for_tenant`/`app.list_scim_provisioning_events_for_tenant` | `IAM:View`-gated |

**The dual-gate on activation is a real, corrected fix — worth stating explicitly since it changes who could previously do this.** The original implementation validated the test-before-enforcement lockout precondition, then delegated the actual status flip ENTIRELY to `app.set_integration_connection_status` (`IAE-008`, unmodified), which checks only `INTHUB:Configure`. Live-reproduced at Group 7's own Tier C review: any actor holding ONLY the broadly-held, generic `INTHUB:Configure` permission — with ZERO `IAM` grant of any kind — could activate enterprise SSO login for a tenant (`IAE-354.md` §13, a real segregation-of-duties bypass). **A tenant's generic integration administrator no longer suffices alone; enabling live SSO login is now, correctly, an identity/IAM decision requiring `IAM:Configure` specifically, in addition to whatever the underlying connection status change separately still requires.**

**Common errors and what they mean:**
- `enterprise_idp_no_verified_test_login` — the structural lockout guard; run `app.resolve_enterprise_sso_claims` first to produce a genuine `matched` row.
- `no_matching_platform_identity` from `provision_scim_identity` — a genuinely new external identity with no `app.users` row to link; minting a brand-new platform identity requires the external Supabase Admin API, outside this capability's own scope — this is a disclosed rejection, not a defect.
- `iam_domain_claim_token_mismatch` — the caller-supplied observed TXT value does not match the stored verification token.

**What this role can NEVER do, even holding `IAM:Configure`:** perform an actual live OIDC token-exchange or SAML-assertion signature verification (no such protocol client exists in this repository — `resolve_enterprise_sso_claims` operates only on an already-extracted, already-verified claims payload); mint a genuinely new platform identity via SCIM (disclosed-rejected, not built); activate an IdP connection without also separately holding whatever `app.set_integration_connection_status` itself still requires.

---

## 5. Enterprise Security Administrator (`SEC` module — `Configure`/`View`/`Approve`)

**What `SEC` is, precisely:** a module first registered by `IAE-027` (Enterprise MFA and Session Controls, Prompt 355) and reused, unchanged, by `IAE-028` (IP Restriction and Network Access, Prompt 356) — the third and final Group 7 "Enterprise Security" capability to share it. Both capabilities follow the identical shape: a `Configure`-gated request/administer action, a genuinely SEPARATE, higher-tier `Approve`-gated decision action, and a `View`-gated read.

| Domain | `SEC:Configure` | `SEC:Approve` | `SEC:View` |
|---|---|---|---|
| MFA policy/step-up | `app.set_mfa_tenant_policy`, `app.get_or_create_mfa_tenant_policy` (§ note below) | — | `app.get_or_create_mfa_tenant_policy`, `app.list_mfa_step_up_challenges_for_tenant` |
| Session/device control | `app.revoke_user_session` (self or another identity), `app.revoke_all_actor_sessions` | — | `app.list_user_sessions_for_tenant` |
| MFA exception (break-glass) | `app.request_mfa_exception` | `app.approve_mfa_exception` (self-approval structurally forbidden) | `app.list_mfa_exceptions_for_tenant` |
| IP allowlist enforcement | `app.set_ip_allowlist_enforcement_mode`, `app.add_ip_allowlist_entry`, `app.revoke_ip_allowlist_entry` | — | `app.get_or_create_ip_allowlist_policy`, `app.list_ip_allowlist_entries_for_tenant`, `app.list_ip_access_evaluations_for_tenant` |
| IP allowlist emergency bypass | `app.request_ip_allowlist_bypass` | `app.approve_ip_allowlist_bypass` (self-approval structurally forbidden) | `app.list_ip_allowlist_bypass_grants_for_tenant` |

**A real, self-caught fix worth knowing about `get_or_create_mfa_tenant_policy`/`get_or_create_ip_allowlist_policy`:** both were originally a bare `p_tenant_id`-only bootstrap with no actor/authority parameter at all — any authenticated identity of ANY tenant could read, and silently bootstrap a real row for, another tenant's own policy (`IAE-355.md` §13, caught by `rbac-enforcement.sql`'s own drift gate). Fixed by splitting each into an internal-only `_get_or_create_*` bootstrap primitive (no grant to anyone) plus a new, actor-gated public wrapper requiring `SEC:View`. If a colleague reports these functions now require an extra `actorAuthUserId` argument that an older integration doesn't pass, this is the corrected, intended shape.

**Self-approval is structurally forbidden at TWO layers for both break-glass mechanisms (`app.mfa_exceptions_no_self_approval`, and `IAE-028`'s own equivalent CHECK constraint) — a hard database constraint, not merely application logic.** A raw-SQL bypass attempt against either is independently rejected by the constraint itself, live-proven in each capability's own db-test.

**Emergency lockout guards mirror the IAM lockout guard exactly:** `app.set_ip_allowlist_enforcement_mode` rejects moving straight to `enforced` with zero active allowlist entries (`ip_allowlist_no_active_entries`) — add at least one real entry first, exactly as SSO activation requires at least one real `matched` test resolution first.

**Common errors and what they mean:**
- `mfa_exception_self_approval_forbidden`/the IP-bypass equivalent — structurally blocked, no workaround exists by design.
- `mfa_exception_not_approved`/`mfa_exception_expired` — a used or expired exception cannot be replayed; request a genuinely new one.
- `mfa_exception_target_not_tenant_member` — the named target identity has no active membership in the tenant at all.
- `ip_allowlist_no_active_entries` — the emergency lockout guard on enforcement-mode escalation.

**What this role can NEVER do, even holding both `SEC:Configure` and `SEC:Approve`:** approve their own MFA exception or IP-allowlist bypass request (structurally blocked at the CHECK-constraint level, independent of RBAC); rely on any live MFA step-up enforcement actually running today — `app.assert_current_step_up_authorization` exists and is correct, but nothing in this repository calls it yet, including this module's own highest-risk actions.

---

## 6. Monitoring and Retention Administrator (`MON`/`RET` modules)

**`MON`** (`View`/`Edit`/`Configure`) is a brand-new module registered by `IAE-030` (Enterprise Monitoring and Observability, Prompt 358) — Prompt 358's own "Reliability" workstream, distinct from `IAM`/`SEC`, and deliberately not a forced reuse of either.

| Task | Real RPC | Gate |
|---|---|---|
| Define/update an SLO | `app.set_slo_definition` | `MON:Configure` (tenant-scoped) or Supreme-Admin-only (platform-wide, `tenant_id` null) |
| Configure an alert route | `app.set_alert_route` | `MON:Configure` or Supreme-Admin-only |
| Ingest a raw telemetry signal | `app.record_observability_signal` | `service_role` only — system-to-system, numeric-only ingestion, no human caller |
| Raise a deduplicated incident | `app.raise_observability_alert` | `service_role` only — a trusted internal dispatcher |
| Acknowledge/resolve an incident | `app.acknowledge_incident`/`app.resolve_incident` | `MON:Edit` or Supreme-Admin-only |
| Read incidents/routes/timeline | `app.list_incidents_for_tenant`/`app.list_alert_routes_for_tenant`/`app.get_incident_timeline` | `MON:View` or Supreme-Admin-only |
| Read the real, platform-wide job-queue backlog | `app.compute_job_queue_backlog` | **Supreme-Admin-only** — `app.jobs` is not tenant-scoped for this reading, so this is a genuinely cross-tenant metric; a real, self-caught fix before this migration was ever committed, having originally shipped with no actor/authority parameter at all (`IAE-358.md` §7) |

**`app.observability_signals` stores ONLY a numeric metric value plus an opaque `source_type`/`source_reference` string — never a raw payload.** This is a structural property of the schema, not a redaction step that could be forgotten — do not expect free-text/PII-shaped telemetry to ever appear here, by design.

**A NULL `tenant_id` incident/signal is a genuinely platform-wide, cross-tenant event (e.g. a shared queue backing up) — Supreme-Admin-visible only**, mirroring the "no other layer sees across tenants" discipline this repository already established everywhere else.

**`RET`** (`View`/`Configure`/`Approve`) is a brand-new module registered by `IAE-031` (Data Retention and Archival, Prompt 359).

| Task | Real RPC | Gate |
|---|---|---|
| Set a tenant's own retention-days override | `app.set_retention_policy` | `RET:Configure` (tenant-scoped) or Supreme-Admin-only (platform-wide) |
| Place a legal hold | `app.request_legal_hold` | `RET:Configure` — the LOWER bar |
| Release a legal hold | `app.release_legal_hold` | `RET:Approve` — a genuinely separate, HIGHER bar, since releasing is what allows deletion to proceed |
| Request an archive (dry-run or real) | `app.request_retention_archive` | `RET:Configure` |
| Read policies/holds/archive requests | `app.list_retention_policies_for_tenant`/`app.list_legal_holds_for_tenant`/`app.list_retention_archive_requests_for_tenant` | `RET:View` |

**The retention-days default resolver is deliberately `service_role`-only.** `app.resolve_retention_days` takes a bare `p_tenant_id` with no actor parameter and is granted to `service_role` alone (not `authenticated`) — a real, self-caught-then-drift-gate-caught fix, since any authenticated identity of any tenant could otherwise have probed another tenant's own retention override (`IAE-359.md` §13). This mirrors the identical `resolve_tenant_deployment_type`/`resolve_tenant_region`/`resolve_latest_dr_restore_status` shape named in the companion runbooks document §0.

**Self-release on a legal hold is structurally forbidden at two layers** (`legal_holds_no_self_release` CHECK constraint plus an explicit `legal_hold_self_release_forbidden` application error) — the identical pattern every other break-glass mechanism in Phase 9 follows.

**Common errors and what they mean:**
- `blocked_within_retention` — the record has not yet reached its own class's retention floor; this is correct enforcement, not something to override.
- `blocked_legal_hold` — an active hold blocks archival unconditionally, regardless of age; see the companion runbooks document, runbook 6, for the real, already-closed Critical bypass history here.
- `legal_hold_not_active` — attempting to release an already-released hold.
- `incident_not_open` — attempting to re-acknowledge or re-resolve an already-resolved incident.

**What this role can NEVER do:** release their own legal hold, even holding both `RET:Configure` and `RET:Approve`; read another tenant's own `app.resolve_retention_days` override directly (the function itself refuses `authenticated` entirely); expect physical archival/deletion to happen as a direct side effect of `request_retention_archive` — it only enqueues a real `app.jobs` row and stops there, with no worker built yet to consume it.

---

## 7. Dedicated Deployment and DR Administrator (`DEPLOY`/`SUP` modules)

**`DEPLOY`** (`View`/`Configure`/`Approve`) is a brand-new module registered by `IAE-032` (Dedicated Enterprise Deployment, Prompt 360) and reused, unchanged, by `IAE-033` (Multi-Region and Data Residency, Prompt 361) — both are "Enterprise Deployment" epics, and the second checkpoint introduces no materially distinct actor-facing authority scope of its own.

| Task | Real RPC | Gate |
|---|---|---|
| Request dedicated-deployment qualification | `app.request_dedicated_deployment_qualification` | `DEPLOY:Configure` |
| Approve qualification | `app.approve_dedicated_deployment_qualification` | `DEPLOY:Approve` — genuinely separate; self-approval structurally forbidden (`tenant_deployment_records_no_self_approval` CHECK + `deployment_self_approval_forbidden`) |
| Advance provisioning status | `app.set_deployment_provisioning_status` | `DEPLOY:Configure`; a real, ordered transition graph — no skipping stages |
| Set an environment-isolation reference | `app.set_deployment_environment_ref` | `DEPLOY:Configure`; stores a reference STRING only, never a real secret |
| Request/approve a non-default region assignment | `app.request_region_assignment`/`app.approve_region_assignment` | `DEPLOY:Configure`/`DEPLOY:Approve`; approval REJECTS outright unless the tenant already has an ACTIVE dedicated deployment (RPD-013 composed as real code, not prose) |
| Register a region capability-gap exception | `app.register_region_capability_exception` | `DEPLOY:Approve` — the same tier as approval itself, since a non-gap exception would be a meaningless record |
| Read deployment/region state | `app.get_tenant_deployment_record`/`app.list_deployment_environment_refs`/`app.get_tenant_region_assignment`/`app.list_region_service_capabilities`/`app.list_region_capability_exceptions_for_tenant` | `DEPLOY:View` |
| Set a region's own service-category support flag | `app.set_region_service_capability` | **Supreme-Admin-only internally** — platform-wide reference data, not a tenant configuration |

**`app.resolve_tenant_deployment_type`/`app.resolve_tenant_region` are both `service_role`-only, bare-tenant-id, no-actor-parameter functions** — the exact shape named in the companion runbooks document §0; a client attempting to call either directly will fail, by design.

**`SUP`** (`View`/`Configure`/`Approve`) is a brand-new module registered by `IAE-035` (Disaster Recovery and Enterprise Support, Prompt 363) — Prompt 363's own "Reliability and Customer Success" workstream.

| Task | Real RPC | Gate |
|---|---|---|
| Record a DR restore-test result | `app.record_dr_restore_test` | `SUP:Configure` (tenant-scoped) or Supreme-Admin-only (platform-wide); real evidence CHECK constraints per outcome |
| Set a tenant's support entitlement tier | `app.set_support_entitlement` | `SUP:Configure`; `enterprise_24_7` requires a real escalation contact and a real, positive P1 response-time value |
| Verify one of the 5 automated onboarding-checklist items | `app.verify_onboarding_checklist_item` | `SUP:Configure` |
| Acknowledge the hypercare plan (the 6th, human-attestation item) | `app.verify_onboarding_checklist_item` (`item='hypercare_plan_acknowledged'`) | **`SUP:Approve` — a deliberately HIGHER tier than the other five items**, since this is the sign-off that green-lights `status='ready_for_production'` |
| Read DR tests/entitlement/checklist | `app.list_dr_restore_tests_for_tenant`/`app.get_support_entitlement`/`app.get_enterprise_onboarding_checklist` | `SUP:View` |

**`app.resolve_latest_dr_restore_status` is the identical bare-tenant-id, `service_role`-only shape** as every other "resolve the real default" function in this phase.

**Common errors and what they mean:**
- `deployment_self_approval_forbidden`/`region_self_approval_forbidden` — structurally blocked at both a CHECK constraint and an application check; no workaround, including via a colleague acting as a rubber stamp for a request they did not genuinely review.
- `region_requires_dedicated_deployment` — RPD-013's own rule enforced as real code; qualify and activate a dedicated deployment first via `IAE-032`'s own lifecycle before a non-default region assignment can ever be approved.
- `region_capability_gap_unresolved` — at least one of the six real service categories is neither genuinely supported in the target region nor covered by a registered exception.
- `dr_test_deployment_mismatch` — a `dedicated`-scoped restore test was recorded for a tenant with no active dedicated deployment.
- `dr_test_failure_evidence_required`/the widened passed-evidence CHECK — a `failed` test needs real, non-empty failure reason/recovery steps/a genuinely future retest date; a `passed` test needs real, non-negative, non-`NaN` RPO/RTO figures — neither can be satisfied with placeholder or hollow values.

**What this role can NEVER do, even holding every relevant grant:** cause physical infrastructure (a real dedicated database instance, a real cross-region data replica) to be provisioned as a side effect of any RPC above — every mechanism here is a real, structural GOVERNANCE evidence layer a future provisioning runbook/tool would read from and write into, never the provisioning mechanism itself; approve their own dedicated-deployment/region-assignment request; flip `hypercare_plan_acknowledged` to `true` without genuinely holding the higher `SUP:Approve` tier.

---

## 8. Supreme Admin — the RPD-022 cross-cutting exception

**What this role is, precisely, across the whole of Phase 9: the one identity class that bypasses the role/permission lookup entirely for every module:action tuple named in sections 1-7 above, via a single, structural branch in the repository-wide RBAC evaluator — never a per-capability special case.**

**The real mechanism** (`supabase/migrations/20260716104519_create_rbac_evaluator.sql:39-67`, RPD-022, `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` §8):

```sql
if exists (
  select 1 from app.principal_memberships
  where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active'
) then
  return row(true, 'supreme_admin_exception', v_permission.id, null, null, p_as_of)::app.rbac_decision;
end if;
```

`app.evaluate_permission` checks for a live, `active`, `supreme_admin`-**layer** `app.principal_memberships` row **before it ever joins `app.role_assignments`/`app.role_versions`/`app.role_version_permissions` at all** — a genuine Supreme Admin is granted **any** `(resource_module_code, action)` pair that exists as a real, registered `app.permissions` row, with no role assignment of any kind required. The returned `reason` is the literal string `'supreme_admin_exception'`, distinguishable in every audit trail from an ordinary `'role_grant'` decision.

**What this buys Supreme Admin across every Phase 9 module named above, concretely:**
- Every Supreme-Admin-only action this document names (`publish_report_type_version`, `register_analytics_view`/`refresh_analytics_view`, `register_integration_adapter`, `register_n8n_allowlisted_action`, `set_region_service_capability`, `compute_job_queue_backlog`, platform-wide `set_retention_policy`/`set_slo_definition`/`set_alert_route`/`record_dr_restore_test`) is real Supreme-Admin authority, not a fabricated "admin can do everything" claim layered on top — it is the SAME structural branch every ordinary module:action check also passes through.
- Supreme Admin is the correct actor to approve a self-blocked request when no genuinely independent second party exists yet within a tenant's own role assignments — e.g. `IAE-360.md`/`IAE-363.md` both note their own db-test fixtures approve a request with the fixture's own Supreme Admin identity specifically BECAUSE the self-approval CHECK constraint correctly rejects the tenant's own dual-permission actor.
- The two "resolve the tenant's own default" functions gate NOTHING against Supreme Admin either, since they are `service_role`-only regardless of caller identity — Supreme Admin authority is orthogonal to that particular shape.

**What this exception does NOT do, and what this document is careful never to imply:**
- **It does not make any table or ledger tamper-proof-for-all, or immune from its own audit trail.** Every Supreme Admin action that reaches a real mutation still writes a genuine `app.audit_logs` row — this is a detective control, not a preventive guarantee that the action itself could never later be reviewed or reversed by an equally privileged party.
- **It does not bypass a structural CHECK constraint.** Self-approval-forbidden constraints (`mfa_exceptions_no_self_approval`, `tenant_deployment_records_no_self_approval`, `tenant_region_assignments_no_self_approval`, `legal_holds_no_self_release`) apply to the DATABASE ROW's own `approved_by`/`released_by` value regardless of who holds it — a Supreme Admin who is ALSO the row's own `created_by`/`placed_by` identity is still rejected by the same constraint, exactly like any other actor. The exception grants PERMISSION to attempt the action; it does not exempt anyone from a structural data-integrity rule.
- **It does not disable RLS default-deny.** Every Phase 9 table named in this document is RLS-enabled with zero policies for `authenticated`, and Supreme Admin's own read access flows through the SAME `SECURITY DEFINER` list/get functions everyone else uses — `app.is_supreme_admin()` is checked explicitly, inline, inside each function's own authority branch, not by a blanket RLS bypass on the raw table.
- **It never appears as a distinct, separate module:action tuple to grant or revoke** — there is no `SUPREME:*` permission anywhere in this repository; the exception is keyed entirely on a live `principal_memberships` row with `layer = 'supreme_admin'`, a Platform Core (Layer 4/PLT-108) identity concept, structurally outside the `app.permissions` catalogue this whole document otherwise describes.

**Scenario walkthrough:** during Group 8's own capability build, the same identity legitimately held both `DEPLOY:Configure` and `DEPLOY:Approve` for a tenant fixture — a real, permitted RBAC combination this repository's own model does not forbid. When that identity's own self-approval attempt was correctly rejected by `deployment_self_approval_forbidden`, the fix pass and every downstream capability's own db-test fixture (`IAE-034`, `IAE-035`) switched to approving with the fixture's own Supreme Admin identity instead — a genuinely different actor from the requester, authorized purely through the `supreme_admin_exception` branch above, with zero tenant-scoped `DEPLOY:Approve` grant required at all (`IAE-360.md` §13, `IAE-363.md` §13 item 2).
