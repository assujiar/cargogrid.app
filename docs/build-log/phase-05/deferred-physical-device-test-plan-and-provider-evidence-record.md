# Deferred Physical-Device Test Plan and Third-Party Provider Evidence Record

**Produced by:** `CG-S10-ATW-028` (Prompt 247, Advanced TMS/WMS Documentation and Handoff), the TECHNICAL/HARDWARE/PROTOCOL/OPERATIONS half of this checkpoint.
**Audience:** whoever eventually procures a real Teltonika device or negotiates a real third-party GPS provider contract, and any future runtime agent asked to activate either.
**Purpose:** the formal `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` and `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` record this checkpoint's own governing prompt requires (`docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/247_ADVANCED_TMS_WMS_DOCUMENTATION_HANDOFF_PROMPT.md` "External-evidence policy," identical text in `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/219_ADVANCED_TMS_WMS_README.md` §7).
**Status of both records below:** open, unstarted, honestly disclosed as such — neither a real device nor a real provider connection has ever existed in this repository at any checkpoint through `CG-S10-ATW-027`.

## 1. `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` — physical GPS device

### 1.1 Owner

Not yet assigned to a named individual or team — this repository has no procurement/operations organization of its own; assignment is an operator decision outside this repository's scope. Whoever activates this record (§1.6) is responsible for naming a real owner at that time.

### 1.2 Target device / model

Any Teltonika device implementing the **Codec 8 Extended** protocol — the family `services/gps-gateway/src/codec8e.ts`'s own header names explicitly: "FMC920 and every other Codec 8 Extended device." This is a protocol-level compatibility statement, not a single-SKU requirement: procurement should confirm the specific model quoted explicitly supports Codec 8 Extended (not the older, non-Extended Codec 8, and not Codec 12/16) before ordering — `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md` §2 covers this in full.

### 1.3 Installation prerequisites

1. A device procured and registered per `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md` §4 (`app.register_gps_device`).
2. An active SIM provisioned and paired per the same guide's §5.
3. A deployed, reachable `services/gps-gateway` instance per `docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` — **this itself has never happened** (`docs/build-log/phase-05/ATW-226I.md` §9: "`services/gps-gateway/` has never been deployed to any live registry/orchestrator... no live container has ever run against a real network"). A real device test cannot begin before this prerequisite is independently satisfied.
4. Physical installation per the same procurement guide's §7.1.
5. Network-layer compensating controls in place — a private APN, VPN/tunnel, or IP allowlist — per `docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` §6's own disclosed residual risk. Running a real device test without this is not unsafe to the software (the protocol/decode layer is real and tested regardless), but it would not be testing a representative production security posture.

### 1.4 Exact future test procedure

Each item below already has real, repository-controlled evidence via protocol simulators and recorded/synthetic frames (§1.5); the future procedure is to re-prove the identical list against a genuine physical device and confirm no divergence:

1. **IMEI handshake** — confirm the real device's own 2-byte-length-prefixed IMEI frame is byte-identical in shape to what `services/gps-gateway/src/codec8e.ts`'s `decodeImeiHandshake` expects, and that the device correctly interprets the gateway's `0x01`/`0x00` single-byte response.
2. **Codec 8 Extended parsing** — confirm the device's own real AVL data packets decode cleanly (`decodeAvlDataPacket`), with particular attention to IO element IDs the device actually populates in practice (the simulator/test suite exercises all five width categories structurally, but not necessarily every IO ID a specific real device sends).
3. **CRC validation** — confirm the device's own CRC-16 computation matches `crc16Ibm`'s output for real frames (already verified against the standard `"123456789"` → `0xBB3D` check vector in the abstract; a real device's own frames are the missing confirmation).
4. **ACK behavior** — confirm the device correctly reads the 4-byte accepted-record-count ACK and does not retransmit when the count matches.
5. **Duplicate/replay handling** — confirm a real device's own retry-on-no-ACK behavior (e.g. after a dropped TCP packet) is handled correctly by the gateway's existing ordering/durable-buffer logic.
6. **Reconnect** — confirm a real device reconnecting after a genuine cellular signal loss (not merely a scripted `socket.destroy()`) behaves as `docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md` §4.1's reconnect sub-scenario already proves for a simulated reconnect.
7. **Malformed payload rejection** — not expected to trigger under normal operation with a real, correctly-functioning device; confirm the gateway does not crash if it ever does (already proven against a deliberately corrupted frame in simulation).
8. **Buffering** — confirm a real Supabase-outage window (not a forced fake-client failure) is durably buffered and correctly flushed on recovery, per `docs/build-log/phase-05/queue-dlq-replay-reconciliation-procedure.md` §3.
9. **Database outage recovery** — the same, at the database layer (already proven via a real `SIGKILL` + cluster restart in `scripts/load-tests/`'s own Scenario 7, but against synthetic, not device-originated, data).
10. **Canonical projection** — confirm a real device's own reported coordinates flow correctly through `app.arbitrate_and_project_vehicle_position` into `app.vehicle_current_positions` and are visible on the Fleet Control Tower live map.

### 1.5 Expected evidence

- A dated test log (or `db:test`-shaped script output) showing each of the 10 items in §1.4 exercised against the real device, with pass/fail per item.
- The real device's own model/firmware version, IMEI, and SIM ICCID, cross-referenced against the `app.gps_devices`/`app.sim_cards` rows registered for it.
- Any divergence from the simulator-based behavior found during this test (e.g. a real-world IO element ID the simulator never exercised, a timing characteristic the loopback tests could not represent) recorded as a new, dated finding — not silently absorbed into "still passing."
- A new build-log entry (following this repository's own established `docs/build-log/phase-05/ATW-NNN.md` convention) documenting the result, superseding this record's `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` status for the specific items proven.

### 1.6 Safe activation gate

Do **not** change any customer-facing or security-facing claim about "physical hardware tested" until:

1. All 10 items in §1.4 have real, dated evidence per §1.5.
2. §1.3's prerequisites (most critically, an actually-deployed `services/gps-gateway` instance and the network-layer compensating controls) are independently confirmed, not merely assumed.
3. The residual IMEI-spoofing risk (`docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md` §6) is re-assessed against the real device's own behavior — a real device test does not close this risk by itself; it is a protocol-level limitation, not a device-specific bug.

Until then, every reference to physical-device testing anywhere in this repository must continue to say exactly what it says today: protocol simulators and recorded/synthetic frames proved the parser/handshake/CRC/ACK/replay/reconnect/malformed-payload/buffering/outage-recovery behavior; hardware-in-the-loop testing is deferred until a device is available. **Do not claim "tested on physical device" before that evidence exists** — the exact instruction this record exists to satisfy.

## 2. `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` — third-party GPS platform

### 2.1 Required prerequisites for a live test

1. **Credentials** — a real API key/webhook secret/OAuth credential (whatever the specific vendor requires) issued by the provider for a CargoGrid-controlled test or production account.
2. **API access** — the provider's own sandbox or production API/webhook endpoint reachable from wherever CargoGrid's own infrastructure runs.
3. **Legal/commercial permission** — an executed contract or terms-of-service acceptance authorizing CargoGrid to receive and process that provider's data; this repository has no legal/commercial function of its own and cannot satisfy this prerequisite internally.
4. **Documented rate limits** — the provider's own published or contractually-agreed request-rate ceiling, so `app.third_party_provider_ingestion_attempts`'s own rate-limiting (`docs/build-log/phase-05/guides/third-party-provider-onboarding-and-credential-rotation-guide.md` §6) can be configured/interpreted against a real external constraint rather than only this repository's own internal 10-per-15-minutes bad-attempt limiter.
5. **A stable provider contract** — the vendor's own real webhook/poll payload shape, in writing, stable enough to build a translation layer against (§2.3 below).

None of these five exist for any named vendor anywhere in this repository today.

### 2.2 What is already proven via deterministic contract fixtures (repository-controlled, real, current)

- **The adapter contract itself**: `scripts/db-tests/advanced-tms-third-party-provider-adapter.sql` proves registration/rotation idempotency, a correctly-signed location event accepted, an identical `provider_event_id` replayed returning `duplicate` (never re-inserted), a tampered payload rejected `invalid`, a stale timestamp outside the 5-minute window rejected despite an otherwise-correct signature, an unmapped `vehicle_id` quarantined with the raw payload preserved, malformed JSON/bad `connection_id`/unsupported `event_type`/missing coordinates all cleanly `invalid` (never raised), rate limiting, and schema-privilege defense in depth.
- **Authentication/signature checks**: HMAC-SHA256 verification is pure cryptographic computation, not network I/O — genuinely provable without any live HTTP call, and proven exactly that way (`docs/build-log/phase-05/guides/third-party-provider-onboarding-and-credential-rotation-guide.md` §5).
- **Mapping**: `app.provider_vehicle_mappings` (`ATW-223`) resolution against a mapped vs. unmapped `vehicle_id`, both branches tested.
- **Retry/idempotency**: the replayed-`provider_event_id` case above.
- **Schema-drift handling**: a malformed/incorrectly-typed field is caught and returns a clean `invalid` outcome rather than an uncaught exception, hardened further at `CG-S10-ATW-027` finding 3 (the exception boundary now covers every field extraction/cast through the final `INSERT`, not only JSON parsing).
- **Failure behavior**: the 10-consecutive-signature-failure auto-disable (`ATW-226I`) and its manual disable/reenable recovery RPCs, all proven in `scripts/db-tests/advanced-tms-gps-telematics-integrated-verification.sql` Part A.

### 2.3 What a live connection would still need to prove, that fixtures cannot

1. **The real vendor's own actual payload shape** — this repository's reference contract (`event_id`/`vehicle_id`/`event_type`/`timestamp`/`latitude`/`longitude`/`speed_kmh`/`heading_degrees`) is explicitly disclosed as representative, never a claim that any named vendor's real API matches it (`docs/build-log/phase-05/guides/third-party-provider-onboarding-and-credential-rotation-guide.md` §1). A real integration needs a translation layer in front of `app.ingest_third_party_provider_webhook_event`, and that translation layer's own correctness against the vendor's real, live payloads is unproven by anything in this repository.
2. **Real network conditions** — actual latency, actual TLS/certificate behavior, actual retry/backoff behavior the vendor's own infrastructure exhibits under a real outage, none of which a deterministic fixture can represent.
3. **Real rate-limit behavior** — whether the vendor's own documented rate limit matches what they actually enforce, and how their own client behaves when CargoGrid's own 10-per-15-minute limiter (§2.1 point 4) trips during legitimate traffic.
4. **Poll-mode behavior** — `integration_mode='poll'` is structurally represented (`poll_cursor`, `app.update_third_party_provider_poll_cursor`) but has **no live HTTP poll call anywhere in this repository** (`docs/build-log/phase-05/queue-dlq-replay-reconciliation-procedure.md` §5) — a live provider test in poll mode would be building and proving a genuinely new poll worker, not merely activating an existing one.
5. **Volume/cost behavior at real scale** — this repository's own load-test evidence for the downstream arbitration layer (`docs/build-log/phase-05/guides/gps-gateway-endpoints-firewall-health-metrics-scaling-guide.md` §4.3) used synthetic, not vendor-originated, traffic.

### 2.4 Safe activation gate

Do not claim a named provider is "live," "certified," or "integrated" until: a real credential and contract exist (§2.1), a translation layer for that vendor's real payload shape is built and tested against real traffic (§2.3 point 1), and at minimum one real end-to-end webhook delivery has been observed to reach `app.canonical_telemetry_events` and the Fleet Control Tower correctly. Until then, continue marking any named-vendor claim `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE`, exactly as `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/219_ADVANCED_TMS_WMS_README.md` §7 requires.

## 3. Closure treatment (restated, not reinterpreted)

Per the governing prompt's own "External-evidence policy" §3: these two deferred/conditional external tests are **non-blocking** when all repository-controlled implementation, simulator/contract, security, migration, load, recovery, and canonical-data gates pass — which they do as of `CG-S10-ATW-027` (`docs/build-log/phase-05/ATW-027.md` §11: zero Critical/High-severity finding remains open). Any unresolved *repository-controlled* defect remains blocking; the absence of physical hardware or a live provider connection does not.

## 4. Related documentation

- `docs/build-log/phase-05/guides/gps-hardware-procurement-installation-guide.md`
- `docs/build-log/phase-05/guides/teltonika-codec8e-gateway-deployment-guide.md`
- `docs/build-log/phase-05/guides/third-party-provider-onboarding-and-credential-rotation-guide.md`
- `docs/build-log/phase-05/ATW-226D.md` §5, `docs/build-log/phase-05/ATW-226E.md` §5, `docs/build-log/phase-05/ATW-226I.md` §9 — the prior checkpoints' own disclosures this record consolidates and formalizes.
