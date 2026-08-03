# ATW-226B — Device, SIM, Provider, Installation, and Mapping Management

## 0. Checkpoint

| Field | Value |
|---|---|
| Prompt | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226B`'s own scope line), parent `CG-S10-ATW-007` (`CG-AABPP-ATW-226`) |
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-225-udh-x4hsij` |
| Dependency | `CG-S10-ATW-004` (Prompt 223, Fleet/Vehicle/Driver/Device/SIM Baseline, `VERIFIED`) |
| Authorization | User message "lanjut sd prompt terakhir di 226 (226a-226i)" (continue through the last prompt in 226, i.e. 226A-226I) — a scoped, explicit range authorization following `226A`'s own completion, honoring this session's own standing ascending-order discipline. This checkpoint is the second task within that range. |

## 1. Pre-flight collision check

`pnpm run git:check` clean, continuing directly on top of `ATW-226A`'s own commit. No open PR.

## 2. Baseline reconciliation

Re-read `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20's own one-line `226B` scope ("implement device/SIM/installation/provider/mobile eligibility mappings") plus `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` §1.4's own planned `226B` row. A direct re-read of `ATW-223`'s own already-applied migration (`20260729310000`) found that `app.gps_devices`, `app.sim_cards`, `app.device_vehicle_assignments`, `app.provider_vehicle_mappings`, and the mobile eligibility/consent flags on `app.vehicle_operational_profiles`/`app.driver_operational_profiles` **all already exist** — re-building any of that would violate `AGENTS.md`'s "do not create duplicate... schemas... because an existing implementation was not searched thoroughly." The one genuine, concrete gap found: `app.transition_gps_device_status` lets any `OPS:Edit` actor flip a device straight to `'installed'` with zero evidence — no technician, no date, no proof. This checkpoint's own scope is narrowed to exactly that gap, disclosed below rather than inventing scope to fill the terse §20 one-liner. Fresh baseline gate suite green before any file was written: `typecheck`/`lint` 0 errors, `node:test` 2273/2273, `db:test` PASS across 101 migrations/103 db-test files.

## 3. Implementation

### 3.1 Scope boundaries and design decisions (disclosed, migration header)

1. **Not a new device/SIM/provider schema.** Confirmed by direct re-read of `ATW-223`'s own migration; every identity/mapping concept `226_*.md` §13 names already has a table. Only installation *evidence* was missing.
2. **Reuses the Document and File Engine (`PLT-128`) exactly as `ATW-176` (ePOD) already established** — a file uploaded against the owning business record (here, the device itself: `record_type='gps_device'`, `record_id=device_id`), then linked and clean-scan-validated by this capability's own mutation. No second file-storage mechanism. A new `document_type_code` (`gps_device_installation`) is registered and published per-tenant, the same `register_document_type` → `create_config_draft('document:<code>', ...)` → `set_config_items` → `publish_document_type_definition` sequence every prior file-consuming capability uses.
3. **`app.record_gps_device_installation` composes `app.transition_gps_device_status` (`ATW-223`, unmodified, called internally)** rather than re-implementing the `assigned`→`installed` status-machine/authority logic — the device's own status machine remains the single source of truth for device state; this table only adds the evidence a bare status value cannot carry.
4. **One installation row per `app.device_vehicle_assignments` row** (unique constraint) — an assignment *is* the installation event; a device reassigned/reinstalled later gets a new assignment row (`ATW-223`'s own `is_current`/`superseded_by_id` idiom) and therefore a fresh installation-evidence row, never an overwrite. Recording evidence against a superseded assignment is rejected (`assignment_not_current`).
5. **Evidence is mandatory at record time**, not attachable later — an installation with no evidence is not recorded as installed by this capability at all, avoiding an unresolved "attach evidence later" placeholder (`AGENTS.md`: "do not add... unresolved TODOs").
6. Authority: `OPS:Edit`, the same tier `ATW-223`'s own device/status functions already use — no new tier invented.
7. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

### 3.2 Schema — `supabase/migrations/20260729350000_create_advanced_tms_device_installation_evidence.sql`

One new table, `app.gps_device_installations`. Two new functions: `app.record_gps_device_installation` (evidences installation and transitions the device `assigned`→`installed` in one call), `app.verify_gps_device_installation` (optional `OPS:Edit`-gated secondary review, idempotent-by-reassertion). RLS mirrors `ATW-223`'s own tenant-wide read shape.

### 3.3 Service layer

`server/contracts/gps-device-installation/gps-device-installation.ts`, `server/queries/gps-device-installation.ts` (`listGpsDeviceInstallations`, `getGpsDeviceInstallationForAssignment`), `server/mutations/gps-device-installation.ts` (`recordGpsDeviceInstallation`, `verifyGpsDeviceInstallation`; 11-code error classification list). No UI this checkpoint — same disclosed boundary `ATW-226A` already established (`226_*.md` §20's own `226B` scope line cites no §15 UI requirement of its own; installation-evidence capture is naturally a `226H` administration-surface concern).

## 4. Tests

`scripts/db-tests/advanced-tms-device-installation-evidence.sql` (new) — setup (tenant, `OPS:Edit` rep, `OPS:View`-only viewer, Supreme Admin, one registered+assigned GPS device on one active vehicle, the `gps_device_installation` document type published); assertion sections: three rejected-attempt cases (not-yet-clean evidence, evidence belonging to a different device, blank technician label) proven to leave device status untouched; authority-gating (`OPS:View`-only rejected); a real call that evidences installation **and** transitions the device `assigned`→`installed` atomically; a second attempt on the same assignment rejected (`installation_already_recorded`); `app.verify_gps_device_installation` authority-gated and idempotent-by-reassertion, proven never to mutate the original evidence fields; a superseded (reassigned-away) assignment rejected (`assignment_not_current`); RLS tenant-wide read; schema-privilege defense in depth; exact-count audit trail.

`server/contracts/gps-device-installation/gps-device-installation.test.ts` (5 cases), `server/queries/gps-device-installation.test.ts` (4 cases), `server/mutations/gps-device-installation.test.ts` (4 cases) — **13 net new** `node:test` cases. `node:test` **2286/2286**. `db:test` PASS across 101 migrations/**104** db-test files (1 net new). `npx next build` PASS (81 routes, unchanged).

### 4.1 Real defects found and fixed during authoring (before any full-suite gate run)

1. **Db-test setup omitted the `stock`→`assigned` transition before calling `app.assign_device_to_vehicle`.** Assumed (incorrectly) that assignment itself moves device status — `ATW-223`'s own db-test proves the two are independent (`assign_device_to_vehicle` never touches `status`). Root-caused directly by inspecting real device state in a scratch database after a first failing run, not assumed from documentation. Fixed by adding an explicit `app.transition_gps_device_status(..., 'assigned', ...)` call in setup.
2. **Hardcoded `expected_device_version` literals in the "viewer denied" and "real success" test calls masked the intended assertion** — since the setup fix above bumped the device's real `record_version` to 2, a stale hardcoded `1` would raise `stale_version` before ever reaching the authority check `transition_gps_device_status` performs internally. Fixed by resolving the real current version via a subquery instead of a literal.
3. **`assign_device_to_vehicle` also requires `OPS:Assign`, not just `OPS:Create`/`OPS:Edit`** — the fixture's own role initially granted only Edit/Create; fixed by adding Assign to the same role.

## 5. Residual disclosures

- No UI exists yet for capturing installation evidence in the field (technician-facing) or reviewing it (dispatcher-facing) — deferred to `ATW-226H` per the same boundary `ATW-226A` already disclosed.
- SIM-specific installation evidence (which ICCID was in the device at install time) is not separately modeled — `app.sim_cards.current_device_id` already tracks the live pairing; a future capability may choose to snapshot it onto the installation row if audit requirements demand a historical record, not required by anything this checkpoint's own re-read of `226_*.md` found.
- `ATW-226D`/`226E` remain `NOT_STARTED`, still blocked on `226B`+`226A` — `226A` is now `VERIFIED`, `226B` (this checkpoint) is now `VERIFIED` too, so both are unblocked for `226D`/`226E` to begin once explicitly authorized (already covered by this session's own range authorization).
- No REST/GraphQL surface exists for this or any domain yet (repository-wide, unchanged).

## 6. Completion

This checkpoint corrects `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` §1.4 row `ATW-226B` (`READY` → `VERIFIED`). Per this session's own explicit range authorization ("226a-226i"), proceeding directly to `ATW-226C` next, without a further authorization pause.
