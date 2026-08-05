# GPS Hardware Procurement, Inventory, SIM, Installation, and Replacement/RMA Guide

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff), the TECHNICAL/HARDWARE/PROTOCOL/OPERATIONS half of this checkpoint.
**Audience:** operations administrators who procure and register devices, field/warehouse technicians who physically install them, and dispatchers who assign them to vehicles.
**Source of truth:** `supabase/migrations/20260729310000_create_advanced_tms_fleet_driver_device.sql` (`ATW-223`, device/SIM/assignment primitives), `supabase/migrations/20260729350000_create_advanced_tms_device_installation_evidence.sql` (`ATW-226B`, installation evidence), `supabase/migrations/20260730360000_harden_advanced_tms_device_driver_mobile_tracking.sql` (`CG-S10-ATW-027`, cross-tenant collision rejection and deregistration). Read those migrations directly for the authoritative function bodies; this guide explains and cites them, it does not redefine them.
**Companion documents:** `docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` (what happens after a device is installed and powered on), `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` (the formal deferred-hardware-evidence record this guide's own procedures feed into).

## 1. What is real/tested here, and what is procedure only

This is a **process/procedure guide for physical hardware CargoGrid does not yet own an installed instance of.** Read that sentence literally before following any step below:

- Every RPC named in this guide (`app.register_gps_device`, `app.register_sim_card`, `app.assign_sim_to_device`, `app.assign_device_to_vehicle`, `app.transition_gps_device_status`, `app.record_gps_device_installation`, `app.verify_gps_device_installation`, `app.deregister_gps_device`) is real, applied, and covered by a passing `db:test` file (`scripts/db-tests/advanced-tms-fleet-driver-device.sql`, `scripts/db-tests/advanced-tms-device-installation-evidence.sql`). The software-side steps in this guide are tested exactly as described.
- No physical Teltonika device, SIM, vehicle mount, or wiring harness has ever been purchased, received, or installed against this repository. The procurement/inventory-intake/physical-installation/RMA steps below are **documented operating procedure**, written against the real RPCs and the real device status machine, but **not yet exercised end-to-end against real hardware** — this is the same `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` boundary every `ATW-226` checkpoint has carried since `ATW-226D` (`docs/build-log/phase-05/ATW-226D.md` §5, `docs/build-log/phase-05/ATW-226I.md` §9). Do not represent any step below as "field-tested" — only the database-level state machine and RLS/authority gates are.
- `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` is the formal record of what a first real device would need to prove before that status changes.

## 2. Target device / protocol compatibility

`services/gps-gateway/src/codec8e.ts`'s own header describes its scope precisely: "a deliberately real, byte-level implementation of the publicly documented Teltonika wire protocol (**FMC920** and every other Codec 8 Extended device)." The implementation is protocol-level (Teltonika Codec 8 Extended over raw TCP, IMEI handshake, CRC-16/IBM (ARC) framing — see `docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` for the wire format), not hard-coded to one SKU. In practice this means:

- Any Teltonika device that speaks Codec 8 Extended (the FMC9xx/FMB9xx family and others sharing the same codec) is protocol-compatible with `services/gps-gateway` as shipped.
- A device that only speaks Codec 8 (the original, non-Extended variant) or Codec 12/16 is **not** compatible — `decodeAvlDataPacket` (`services/gps-gateway/src/codec8e.ts`) rejects any codec ID other than `0x8E` with `unsupported_codec_id`.
- Procurement should confirm the vendor quote/spec sheet explicitly states Codec 8 Extended support before ordering, rather than assuming every Teltonika model qualifies.

## 3. Device status lifecycle (the single source of truth every step below moves through)

`app.gps_devices.status` (`ATW-223`) is a hardcoded state machine, enforced entirely inside `app.transition_gps_device_status` — no other function or UI action moves a device between states except the two composed flows in §7:

| From | Allowed to | Enforced by |
|---|---|---|
| `stock` | `assigned` | `app.transition_gps_device_status` |
| `assigned` | `installed` | `app.transition_gps_device_status` (called directly, no evidence) **or** `app.record_gps_device_installation` (evidence-mandatory, §7.2) |
| `installed` | `active` | `app.transition_gps_device_status` (the GPS Gateway itself also flips this automatically the moment the device's first telemetry batch is accepted — `app.ingest_direct_device_telemetry_batch`, `ATW-226D`) |
| `active` / `offline` | `active`, `offline`, `suspended`, `maintenance` | `app.transition_gps_device_status` |
| `suspended` / `maintenance` | `active` | `app.transition_gps_device_status` |
| any non-`retired` status | `retired` (terminal — no edge leads back out) | `app.transition_gps_device_status` or `app.deregister_gps_device` (§8) |

Any other transition raises `invalid_device_status_transition`. Every call is optimistic-concurrency-guarded (`p_expected_version` against `app.gps_devices.record_version`; a mismatch raises `stale_version`) and authority-gated `OPS:Edit`.

## 4. Procurement and inventory intake

1. **Order hardware against a confirmed Codec 8 Extended SKU** (§2). Nothing in this repository automates purchase-order/vendor management — that is outside this capability's scope; procurement remains an external process.
2. **On physical receipt, register each device before it leaves the stockroom**, via `app.register_gps_device(p_tenant_id, p_imei, p_device_model, p_ownership_type, p_actor_auth_user_id, p_actor_label)`:
   - `p_imei` — the device's own printed/labeled IMEI. `app.gps_devices.imei` is stored as plain text (not hashed) — IMEIs are not secret; they are printed on the box and device (`services/gps-gateway/README.md` "Known, disclosed limitations").
   - `p_ownership_type` — one of `cargogrid` (CargoGrid-owned hardware), `customer` (customer-owned, CargoGrid-installed), or `partner` — `app.gps_devices` `CHECK` constraint (`gps_devices_ownership_check`). Any other value raises `invalid_ownership_type`.
   - The row is created with `status = 'stock'` by default (`ATW-223`'s own table default) — this is the inventory-intake state.
   - Requires `OPS:Create` for a genuinely new `(tenant_id, imei)` pair. Re-calling with an IMEI already registered under the *same* tenant is idempotent — it returns the existing row without a second insert or a fresh authority check (`app.register_gps_device`'s own idempotency short-circuit runs before the permission check).
3. **A UI form for this step exists today**: the `operations/fleet` workspace (`app/(tenant)/[tenantSlug]/operations/fleet/page.tsx`, `DeviceSection`) wires `registerGpsDevice`/`transitionGpsDeviceStatus`/`assignDeviceToVehicle` directly to real forms — device registration and bare status transitions do not require calling the RPCs by hand.
4. **A duplicate real-world IMEI across two tenants is now rejected, not silently accepted** (`CG-S10-ATW-027`/Prompt 246, migration `20260730360000`, finding 1a). Before this hardening, any tenant could self-register another tenant's already-active device IMEI and permanently break that victim tenant's own handshake (`imei_ambiguous_across_tenants` at the gateway, with no repair path). `app.register_gps_device` now raises `imei_registered_to_another_tenant` the moment a *different* tenant already holds that IMEI, serialized against a concurrent double-registration race via a per-IMEI `pg_advisory_xact_lock`. See §8 for the remediation path when this rejection is itself the mistake (e.g. a device was retired by its original tenant and resold/reassigned).

## 5. SIM provisioning

1. **Register the SIM** via `app.register_sim_card(p_tenant_id, p_iccid, p_msisdn, p_carrier, p_actor_auth_user_id, p_actor_label)`. Idempotent on `(tenant_id, iccid)`. `status` defaults to `stock` (`app.sim_cards` `CHECK`: `stock`, `assigned`, `active`, `suspended`, `retired`). Requires `OPS:Create`.
2. **Pair the SIM to a device** via `app.assign_sim_to_device(p_sim_id, p_device_id, p_actor_auth_user_id, p_actor_label)`. Requires `OPS:Assign`. Sets `current_device_id` and flips the SIM's own `status` to `assigned`. At most one SIM per device at a time — enforced by both a pre-check (`device_already_has_sim`) and a real partial unique index (`sim_cards_current_device_unique on app.sim_cards (current_device_id) where current_device_id is not null`), so this cannot be violated even under a race.
3. **To swap a SIM** (carrier change, a faulty SIM, an RMA), call `app.unassign_sim_from_device(p_sim_id, p_actor_auth_user_id, p_actor_label)` first — it clears `current_device_id` and resets `status` back to `stock` — then `assign_sim_to_device` the replacement.
4. `current_device_id` is a mutable pointer, not an append-only history (`app.sim_cards`'s own table comment, `ATW-223`): unlike device-to-vehicle assignment (§6), there is no historical record of which SIM was in a device at any past point in time beyond what `app.capture_audit_event` records for each `assign_sim_to_device`/`unassign_sim_from_device` call. If a tenant's own compliance process needs a point-in-time SIM/device pairing snapshot for an installation record, note it in `installation_notes` (§7.2) — the schema does not capture it separately today (this exact residual is disclosed in `docs/build-log/phase-05/ATW-226B.md` §5).

## 6. Device-to-vehicle assignment

`app.assign_device_to_vehicle(p_device_id, p_vehicle_profile_id, p_reason, p_actor_auth_user_id, p_actor_label)` — requires `OPS:Assign`. Unlike SIM pairing, this is a real append-only history: `app.device_vehicle_assignments` never overwrites a prior row. Assigning a device that already has a current assignment automatically supersedes the old row (`is_current = false`, `effective_to = now()`, `superseded_by_id` pointing at the new row) before inserting the new one — the identical `is_current`/`superseded_by_id` idiom `app.resource_assignments` already established elsewhere in this repository. A retired device cannot be assigned (`device_retired`); a device and vehicle profile from different tenants cannot be paired (`tenant_mismatch`).

To release a device from a vehicle without immediately reassigning it (e.g. the vehicle is being decommissioned), call `app.unassign_device_from_vehicle(p_device_id, p_reason, p_actor_auth_user_id, p_actor_label)` — a non-empty `p_reason` is mandatory; it raises `no_current_assignment` if the device has none to release.

## 7. Installation procedure

### 7.1 Physical steps (procedure only — see §1)

These are the operational steps a technician would follow; they are **not** encoded in software and are not what any RPC verifies:

1. Confirm the device's SIM is inserted, activated with the carrier, and the device's own IMEI matches the row registered in §4.
2. Mount the device in the vehicle per the vendor's own installation manual (typically hardwired to ignition-switched power, with a backup battery for power-loss/tamper reporting — exact wiring depends on the specific model procured).
3. Power on and confirm the device's own local status LEDs (if present) show a GSM/cellular and GPS fix, per the vendor's manual.
4. Photograph or otherwise document the completed physical installation — this becomes the uploaded evidence file in §7.2.
5. Confirm the device successfully completes a TCP handshake against the deployed GPS Gateway (`docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` §5) before considering the physical installation complete — a device that cannot reach the gateway's own public endpoint (wrong APN, no signal, firewall block) has not actually been installed from an operational standpoint, even if it is physically bolted into the vehicle.

### 7.2 Software-side installation confirmation (real, tested)

Once §7.1 is physically done, record it — do **not** stop at a bare status flip. `app.record_gps_device_installation(p_device_vehicle_assignment_id, p_evidence_file_id, p_technician_label, p_installation_notes, p_expected_device_version, p_actor_auth_user_id, p_actor_label)` is the one call that both evidences the installation **and** transitions the device `assigned` → `installed` atomically (it composes `app.transition_gps_device_status` internally rather than re-implementing the state machine, `ATW-226B`'s own design note 3). Requires `OPS:Edit`.

Before calling it:

1. **Upload the evidence file through the Document and File Engine (PLT-128)**, the same mechanism `ATW-176` (ePOD) already established — never a second file-storage path. The file must be scoped `record_type = 'gps_device'`, `record_id = <the device's id>`, `document_type_code = 'gps_device_installation'`, and must pass malware clean-scan (`malware_scan_status = 'clean'`) before `record_gps_device_installation` will accept it — an evidence file with any other scan status is rejected with `installation_unsafe_evidence`.
2. The `gps_device_installation` document type must be published for the tenant first (`app.register_document_type('gps_device_installation', ...)` → `app.create_config_draft('document:gps_device_installation', ...)` → `app.set_config_items` → `app.publish_document_type_definition` — the identical per-tenant publish sequence every prior Document-and-File-Engine consumer uses). This is a one-time per-tenant setup step, not a per-installation one.
3. Call `app.record_gps_device_installation` with:
   - `p_device_vehicle_assignment_id` — the row from §6. Must be the assignment's own **current** row — recording evidence against a superseded (reassigned-away) assignment is rejected with `assignment_not_current`.
   - `p_evidence_file_id` — the uploaded file from step 1. It must belong to the exact device named by the assignment and the assignment's own tenant, or the call is rejected with `installation_evidence_file_mismatch`.
   - `p_technician_label` — a non-empty free-text identifier for who performed the install (`technician_label_required` if blank).
   - `p_installation_notes` — optional free text (mount location, wiring notes, anything not captured elsewhere — see §5 point 4 for the SIM-pairing-snapshot use of this field).
4. One installation-evidence row per `device_vehicle_assignment_id` (a real unique constraint, `gps_device_installations_assignment_unique`) — calling it twice for the same assignment raises `installation_already_recorded`. A device reassigned and reinstalled later gets a new assignment row (§6) and therefore a fresh, independent installation-evidence row — never an overwrite of the original.
5. **Optional secondary review**: `app.verify_gps_device_installation(p_installation_id, p_actor_auth_user_id, p_actor_label)` (`OPS:Edit`) lets a second person (e.g. a dispatcher or ops lead) confirm the recorded evidence. It is idempotent-by-reassertion — calling it again only refreshes `verified_by_auth_user_id`/`verified_at`, it never mutates the original evidence fields, and a second reviewer re-confirming the same evidence is not an error.

## 8. BAST / installation handover proof — what the schema actually has

There is **no dedicated `berita_acara`/BAST field, table, or document type** anywhere in this repository. Read that as a direct, honest answer rather than an omission: `app.gps_device_installations` (`ATW-226B`) has exactly these columns —

```
id, tenant_id, device_id, device_vehicle_assignment_id, evidence_file_id, technician_label,
installation_notes, installed_at, verified_by_auth_user_id, verified_at,
record_version, created_by, created_at, updated_at
```

— and none of them is a BAST document number, a customer signatory name, or a customer countersignature reference. The closest real analogues are:

- **`evidence_file_id`** — a mandatory, clean-scan-validated file upload (§7.2). If a tenant's own process produces a signed paper or PDF BAST/handover form, **upload that signed document itself as the evidence file** — the system will happily store a scanned/photographed BAST as the evidence, it just has no separate structured fields describing it (no BAST number, no customer name/signature captured as data).
- **`technician_label`** — who performed the install (a free-text label, not a structured employee/user reference).
- **`installation_notes`** — free text; a tenant that needs to record a BAST document number or customer contact name today has nowhere to put it except this field.
- **`verified_by_auth_user_id`/`verified_at`** — an *internal* CargoGrid secondary reviewer confirming the technician's own evidence (§7.2 point 5). This is not a customer signature and must not be represented as one.

If a customer-countersigned BAST record with its own structured fields (document number, customer signatory, signature capture) becomes a real product requirement, it needs its own schema addition — do not invent one in this guide, and do not repurpose `installation_notes`/`verified_at` as if they already model it.

## 9. Known gap: the Fleet workspace UI does not enforce evidence capture today

Direct inspection of `app/(tenant)/[tenantSlug]/operations/fleet/actions.ts` and `fleet-panel.tsx` found that `DeviceSection`'s own status-transition control calls `transitionDeviceStatusAction` → `transitionGpsDeviceStatus` (the bare `ATW-223` RPC) directly — **not** `app.record_gps_device_installation`. This means a staff user working entirely through the `operations/fleet` screen can move a device from `assigned` straight to `installed` with a plain dropdown action, with **no evidence file, no technician label, and no installation-evidence row created at all** — the evidence-mandatory path in §7.2 exists and is fully real/tested at the database layer, but has no UI entry point wired to it as of this checkpoint. `ATW-226H` (Fleet Control Tower, device administration) wired the provider-mapping and source-priority forms into this same page but did not add an installation-evidence form; no later checkpoint has either.

**Operational recommendation until a dedicated UI ships:** treat `app.record_gps_device_installation` (called directly, e.g. via the Supabase SQL editor or a short internal script under `OPS:Edit` credentials) as the *only* sanctioned way to move a device to `installed` in production, and treat the bare "Installed" option in the Fleet workspace dropdown as a known footgun to avoid using for a real installation. This is a genuine, disclosed process gap, not a hypothetical one — confirmed by direct code read, not assumed.

## 10. Cross-tenant IMEI collision remediation

If `app.register_gps_device` rejects a registration with `imei_registered_to_another_tenant` and the rejection is itself wrong (e.g. the IMEI belongs to hardware CargoGrid's own tenant previously retired and is now being reissued, or a different tenant registered it by mistake and never installed it), the remediation path is `app.deregister_gps_device(p_device_id, p_reason, p_expected_version, p_actor_auth_user_id, p_actor_label)` (`CG-S10-ATW-027`, migration `20260730360000`, finding 1b):

- Requires `OPS:Override` — stricter than the `OPS:Create`/`OPS:Assign`/`OPS:Edit` every other step in this guide uses.
- Soft-retires the row (`status → 'retired'`, the same terminal state §3's table shows, never a raw `DELETE`). Idempotent-safe if the device is already `retired`.
- Evaluated against the *device's own* tenant — a tenant's own `OPS:Override` holder may self-service-deregister their own spuriously-registered device, but clearing a **different** tenant's row (the actual cross-tenant remediation case) requires a real Supreme Admin, since ordinary tenant-scoped role assignment cannot span a tenant boundary.
- `app.resolve_gps_device_for_handshake` (the GPS Gateway's own per-connection lookup) excludes `retired` rows from its own ambiguity check — deregistering the spurious row is what actually restores the victim tenant's own handshake, not merely a bookkeeping cleanup.
- A device retired this way can never transition again (`app.transition_gps_device_status` has no edge out of `retired`) — a cleared collision can never be silently re-created under the same offending registration.

## 11. Replacement / RMA procedure

There is no single "replace device" RPC — the real procedure composes the same primitives used for a first install:

1. **Unassign the failing device from its vehicle**: `app.unassign_device_from_vehicle(p_device_id, p_reason, ...)` with a reason describing the failure (e.g. "no GPS fix, RMA requested").
2. **Move the failing device out of active service**: `app.transition_gps_device_status(p_device_id, 'maintenance', ...)` if it is being sent for repair and may return to service, or straight to `'retired'` if it will not (both are valid edges from `active`/`offline` per §3's table; `retired` is reachable from any non-`retired` status).
3. **If a SIM was paired to the failing device**, `app.unassign_sim_from_device` it first (§5 point 3) so it is free to move to the replacement.
4. **Bring the replacement device into service**: either `app.register_gps_device` it fresh (new hardware, §4) or, if it is already in `stock` from prior inventory, skip straight to assignment.
5. **Assign and install the replacement**: `app.assign_device_to_vehicle` (§6) then `app.record_gps_device_installation` (§7.2) — a genuinely new installation-evidence row, never a mutation of the original device's own evidence row, since evidence is keyed to the `device_vehicle_assignment_id`, and a new device means a new assignment.
6. **Track the RMA itself** (vendor ticket, shipping the failed unit back, warranty status) is outside this repository's scope entirely — nothing in this schema models a vendor RMA case. If a tenant needs to record RMA correspondence against the retired device, `installation_notes` on the *original* installation-evidence row, or an external ticketing system, are the only places available today.

## 12. Related documentation

- `docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` — what a device does once it is physically installed and powered on: the TCP handshake, the protocol, and the residual IMEI-spoofing risk this guide's own registration step does not close.
- `docs/build-log/phase-05/deferred-physical-device-test-plan-and-provider-evidence-record.md` — the formal deferred-hardware-evidence record.
- `docs/runbooks/gps-gateway-outage.md` — what happens operationally once an installed device stops reporting.
- `services/gps-gateway/README.md` — the gateway's own "Known, disclosed limitations" section, including the accepted IMEI-spoofing residual risk this guide's registration/deregistration flow is one half of the compensating control for.
