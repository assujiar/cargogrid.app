"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import type { FleetFormState } from "./actions.ts";
import {
  VEHICLE_OWNERSHIP_TYPES,
  DEVICE_OWNERSHIP_TYPES,
  GPS_DEVICE_STATUSES,
  type VehicleOperationalProfile,
  type DriverOperationalProfile,
  type GpsDevice,
  type SimCard,
  type GpsDeviceStatus,
  type ProviderVehicleMapping,
  type VehicleTrackingSourcePriority,
} from "../../../../../server/contracts/fleet-driver-device/fleet-driver-device.ts";
import type { MasterRecord } from "../../../../../server/contracts/master-data/master-data.ts";

const INITIAL_STATE: FleetFormState = { error: null };

type FleetFormAction = (prevState: FleetFormState, formData: FormData) => Promise<FleetFormState>;

function masterLabel(masterById: ReadonlyMap<string, MasterRecord>, masterId: string): string {
  const record = masterById.get(masterId);
  return record ? `${record.code} — ${record.name}` : masterId;
}

const DEVICE_STATUS_TONE: Record<GpsDeviceStatus, "success" | "warning" | "danger" | "info" | "neutral"> = {
  stock: "neutral",
  assigned: "info",
  installed: "info",
  active: "success",
  offline: "warning",
  suspended: "danger",
  maintenance: "warning",
  retired: "danger",
};

/**
 * Which statuses this generic transition control may offer, per current status.
 *
 * ATW-031 (ISS-2026-028): `installed` is deliberately ABSENT from `assigned`'s list.
 * Moving a device to `installed` requires real installation evidence (a malware-scan-
 * clean evidence file belonging to the device, plus a technician label) and must go
 * through `app.record_gps_device_installation` (ATW-226B). Offering it here let a staff
 * user mark a device installed with no evidence at all. The database now refuses that
 * transition outright (`installation_evidence_required`,
 * supabase/migrations/20260730420000_harden_gps_device_installation_evidence_gate.sql),
 * so this removal is the second line of defence, not the enforcement itself -- but
 * leaving the option visible would only ever produce an error the user cannot act on.
 */
const NEXT_DEVICE_STATUSES: Record<GpsDeviceStatus, readonly GpsDeviceStatus[]> = {
  stock: ["assigned", "retired"],
  assigned: ["retired"],
  installed: ["active", "retired"],
  active: ["offline", "suspended", "maintenance", "retired"],
  offline: ["active", "suspended", "maintenance", "retired"],
  suspended: ["active", "retired"],
  maintenance: ["active", "retired"],
  retired: [],
};

export function VehicleSection({
  vehicles,
  vehicleMasterById,
  registerAction,
}: {
  vehicles: readonly VehicleOperationalProfile[];
  vehicleMasterById: ReadonlyMap<string, MasterRecord>;
  registerAction: FleetFormAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Vehicles</h2>
      {vehicles.length === 0 ? (
        <p className="text-sm text-neutral-500">No vehicles registered yet.</p>
      ) : (
        <div className="overflow-x-auto">
        <table className="w-full min-w-[560px] text-sm">
          <thead>
            <tr className="text-left text-xs text-neutral-500">
              <th className="pb-1">Vehicle</th>
              <th className="pb-1">Ownership</th>
              <th className="pb-1">Capacity</th>
              <th className="pb-1">Tracking eligibility</th>
              <th className="pb-1">Status</th>
            </tr>
          </thead>
          <tbody>
            {vehicles.map((vehicle) => (
              <tr key={vehicle.id} className="border-t border-neutral-100">
                <td className="py-1">{masterLabel(vehicleMasterById, vehicle.vehicleMasterId)}</td>
                <td className="py-1">{vehicle.ownershipType}</td>
                <td className="py-1">
                  {vehicle.capacityWeightKg ?? "—"} kg / {vehicle.capacityVolumeCbm ?? "—"} cbm
                </td>
                <td className="py-1 text-xs">
                  {[vehicle.mobileTrackingEligible && "mobile", vehicle.directDeviceTrackingEligible && "direct-device", vehicle.thirdPartyTrackingEligible && "third-party"]
                    .filter(Boolean)
                    .join(", ") || "none"}
                </td>
                <td className="py-1">
                  <StatusBadge tone={vehicle.status === "active" ? "success" : "neutral"} label={vehicle.status} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Register vehicle</h3>
        <RegisterVehicleForm action={registerAction} />
      </div>
    </section>
  );
}

function RegisterVehicleForm({ action }: { action: FleetFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="code" type="text" required placeholder="Vehicle code" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="name" type="text" required placeholder="Vehicle name" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <select name="ownershipType" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Ownership…
        </option>
        {VEHICLE_OWNERSHIP_TYPES.map((type) => (
          <option key={type} value={type}>
            {type}
          </option>
        ))}
      </select>
      <input name="capacityWeightKg" type="number" step="any" placeholder="Capacity (kg)" className="w-32 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="capacityVolumeCbm" type="number" step="any" placeholder="Capacity (cbm)" className="w-32 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function DriverSection({
  drivers,
  driverMasterById,
  registerAction,
  consentActionFor,
}: {
  drivers: readonly DriverOperationalProfile[];
  driverMasterById: ReadonlyMap<string, MasterRecord>;
  registerAction: FleetFormAction;
  consentActionFor: (driverProfileId: string, expectedVersion: number, consent: boolean) => FleetFormAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Drivers</h2>
      {drivers.length === 0 ? (
        <p className="text-sm text-neutral-500">No drivers registered yet.</p>
      ) : (
        <ol className="flex flex-col gap-2">
          {drivers.map((driver) => (
            <DriverRow key={driver.id} driver={driver} label={masterLabel(driverMasterById, driver.driverMasterId)} consentActionFor={consentActionFor} />
          ))}
        </ol>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Register driver</h3>
        <RegisterDriverForm action={registerAction} />
      </div>
    </section>
  );
}

function DriverRow({
  driver,
  label,
  consentActionFor,
}: {
  driver: DriverOperationalProfile;
  label: string;
  consentActionFor: (driverProfileId: string, expectedVersion: number, consent: boolean) => FleetFormAction;
}) {
  const [state, formAction, pending] = useActionState(consentActionFor(driver.id, driver.recordVersion, !driver.mobileTrackingConsent), INITIAL_STATE);
  return (
    <li className="flex flex-wrap items-center gap-2 border-t border-neutral-100 pt-2 text-sm first:border-t-0 first:pt-0">
      <span className="font-medium text-neutral-900">{label}</span>
      <span className="text-xs text-neutral-500">
        {driver.licenseClass ?? "—"} {driver.licenseExpiryDate ? `(exp. ${driver.licenseExpiryDate})` : ""}
      </span>
      <StatusBadge tone={driver.mobileTrackingConsent ? "success" : "neutral"} label={driver.mobileTrackingConsent ? "Mobile consent granted" : "No mobile consent"} />
      <form action={formAction}>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…" className="w-fit">
          {driver.mobileTrackingConsent ? "Revoke consent" : "Grant consent"}
        </Button>
      </form>
      {state.error ? (
        <p role="alert" className="basis-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

function RegisterDriverForm({ action }: { action: FleetFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="code" type="text" required placeholder="Driver code" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="name" type="text" required placeholder="Driver name" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="licenseClass" type="text" placeholder="License class" className="w-28 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="licenseExpiryDate" type="date" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function DeviceSection({
  devices,
  vehicles,
  vehicleMasterById,
  registerAction,
  transitionActionFor,
  assignActionFor,
  unassignActionFor,
}: {
  devices: readonly GpsDevice[];
  vehicles: readonly VehicleOperationalProfile[];
  vehicleMasterById: ReadonlyMap<string, MasterRecord>;
  registerAction: FleetFormAction;
  transitionActionFor: (deviceId: string, expectedVersion: number) => FleetFormAction;
  assignActionFor: (deviceId: string) => FleetFormAction;
  unassignActionFor: (deviceId: string) => FleetFormAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">GPS devices</h2>
      {devices.length === 0 ? (
        <p className="text-sm text-neutral-500">No devices registered yet.</p>
      ) : (
        <ol className="flex flex-col gap-3">
          {devices.map((device) => (
            <DeviceRow
              key={device.id}
              device={device}
              vehicles={vehicles}
              vehicleMasterById={vehicleMasterById}
              transitionAction={transitionActionFor(device.id, device.recordVersion)}
              assignAction={assignActionFor(device.id)}
              unassignAction={unassignActionFor(device.id)}
            />
          ))}
        </ol>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Register device</h3>
        <RegisterDeviceForm action={registerAction} />
      </div>
    </section>
  );
}

function DeviceRow({
  device,
  vehicles,
  vehicleMasterById,
  transitionAction,
  assignAction,
  unassignAction,
}: {
  device: GpsDevice;
  vehicles: readonly VehicleOperationalProfile[];
  vehicleMasterById: ReadonlyMap<string, MasterRecord>;
  transitionAction: FleetFormAction;
  assignAction: FleetFormAction;
  unassignAction: FleetFormAction;
}) {
  const [transitionState, transitionFormAction, transitionPending] = useActionState(transitionAction, INITIAL_STATE);
  const [assignState, assignFormAction, assignPending] = useActionState(assignAction, INITIAL_STATE);
  const [unassignState, unassignFormAction, unassignPending] = useActionState(unassignAction, INITIAL_STATE);
  const nextStatuses = NEXT_DEVICE_STATUSES[device.status];

  return (
    <li className="flex flex-col gap-2 border-t border-neutral-100 pt-2 first:border-t-0 first:pt-0">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="font-medium text-neutral-900">
          {device.deviceModel} — {device.imei}
        </span>
        <StatusBadge tone={DEVICE_STATUS_TONE[device.status]} label={device.status} />
        <span className="text-xs text-neutral-500">{device.ownershipType}</span>
      </div>

      {device.status === "assigned" ? (
        <p className="text-xs text-neutral-500">
          To mark this device installed, record the installation evidence (evidence file and technician) — a device cannot be
          moved to <span className="font-medium">installed</span> without it.
        </p>
      ) : null}

      <div className="flex flex-wrap items-center gap-2">
        {nextStatuses.length > 0 ? (
          <form action={transitionFormAction} className="flex items-center gap-2">
            <select name="toStatus" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
              <option value="" disabled>
                Move to…
              </option>
              {nextStatuses.map((status) => (
                <option key={status} value={status}>
                  {status}
                </option>
              ))}
            </select>
            <Button type="submit" variant="secondary" loading={transitionPending} loadingLabel="…" className="w-fit text-xs">
              Transition
            </Button>
          </form>
        ) : null}

        <form action={assignFormAction} className="flex items-center gap-2">
          <select name="vehicleProfileId" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
            <option value="" disabled>
              Assign to vehicle…
            </option>
            {vehicles.map((vehicle) => (
              <option key={vehicle.id} value={vehicle.id}>
                {masterLabel(vehicleMasterById, vehicle.vehicleMasterId)}
              </option>
            ))}
          </select>
          <input name="reason" type="text" placeholder="Reason (optional)" className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <Button type="submit" variant="secondary" loading={assignPending} loadingLabel="…" className="w-fit text-xs">
            Assign
          </Button>
        </form>

        <form action={unassignFormAction} className="flex items-center gap-2">
          <input name="reason" type="text" required placeholder="Unassign reason" className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <Button type="submit" variant="destructive" loading={unassignPending} loadingLabel="…" className="w-fit text-xs">
            Unassign
          </Button>
        </form>
      </div>
      {transitionState.error || assignState.error || unassignState.error ? (
        <p role="alert" className="text-xs text-danger">
          {transitionState.error ?? assignState.error ?? unassignState.error}
        </p>
      ) : null}
    </li>
  );
}

function RegisterDeviceForm({ action }: { action: FleetFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="imei" type="text" required placeholder="IMEI" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="deviceModel" type="text" required placeholder="Device model" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <select name="ownershipType" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Ownership…
        </option>
        {DEVICE_OWNERSHIP_TYPES.map((type) => (
          <option key={type} value={type}>
            {type}
          </option>
        ))}
      </select>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function SimSection({
  sims,
  devices,
  registerAction,
  assignActionFor,
  unassignActionFor,
}: {
  sims: readonly SimCard[];
  devices: readonly GpsDevice[];
  registerAction: FleetFormAction;
  assignActionFor: (simId: string) => FleetFormAction;
  unassignActionFor: (simId: string) => FleetFormAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">SIM cards</h2>
      {sims.length === 0 ? (
        <p className="text-sm text-neutral-500">No SIM cards registered yet.</p>
      ) : (
        <ol className="flex flex-col gap-2">
          {sims.map((sim) => (
            <SimRow key={sim.id} sim={sim} devices={devices} assignAction={assignActionFor(sim.id)} unassignAction={unassignActionFor(sim.id)} />
          ))}
        </ol>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Register SIM</h3>
        <RegisterSimForm action={registerAction} />
      </div>
    </section>
  );
}

function SimRow({
  sim,
  devices,
  assignAction,
  unassignAction,
}: {
  sim: SimCard;
  devices: readonly GpsDevice[];
  assignAction: FleetFormAction;
  unassignAction: FleetFormAction;
}) {
  const [assignState, assignFormAction, assignPending] = useActionState(assignAction, INITIAL_STATE);
  const [unassignState, unassignFormAction, unassignPending] = useActionState(unassignAction, INITIAL_STATE);

  return (
    <li className="flex flex-wrap items-center gap-2 border-t border-neutral-100 pt-2 text-sm first:border-t-0 first:pt-0">
      <span className="font-medium text-neutral-900">{sim.iccid}</span>
      <span className="text-xs text-neutral-500">{sim.carrier ?? "—"}</span>
      <StatusBadge tone={sim.status === "active" || sim.status === "assigned" ? "success" : "neutral"} label={sim.status} />
      {sim.currentDeviceId ? (
        <form action={unassignFormAction}>
          <Button type="submit" variant="destructive" loading={unassignPending} loadingLabel="…" className="w-fit text-xs">
            Unassign from device
          </Button>
        </form>
      ) : (
        <form action={assignFormAction} className="flex items-center gap-2">
          <select name="deviceId" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
            <option value="" disabled>
              Assign to device…
            </option>
            {devices.map((device) => (
              <option key={device.id} value={device.id}>
                {device.imei}
              </option>
            ))}
          </select>
          <Button type="submit" variant="secondary" loading={assignPending} loadingLabel="…" className="w-fit text-xs">
            Assign
          </Button>
        </form>
      )}
      {assignState.error || unassignState.error ? (
        <p role="alert" className="basis-full text-xs text-danger">
          {assignState.error ?? unassignState.error}
        </p>
      ) : null}
    </li>
  );
}

function RegisterSimForm({ action }: { action: FleetFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="iccid" type="text" required placeholder="ICCID" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="msisdn" type="text" placeholder="MSISDN (optional)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="carrier" type="text" placeholder="Carrier (optional)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

/**
 * ATW-226H: renders app.provider_vehicle_mappings/app.vehicle_tracking_source_priorities
 * (ATW-223) -- both already-shipped mutations that had zero UI until this checkpoint.
 * Flattened across every vehicle (a per-vehicle detail page is Fleet Control Tower's own
 * scope, not this operational-baseline workspace's).
 */
export function ProviderMappingSection({
  mappings,
  vehicles,
  vehicleMasterById,
  registerAction,
}: {
  mappings: readonly ProviderVehicleMapping[];
  vehicles: readonly VehicleOperationalProfile[];
  vehicleMasterById: ReadonlyMap<string, MasterRecord>;
  registerAction: FleetFormAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Third-party provider mappings</h2>
      {mappings.length === 0 ? (
        <p className="text-sm text-neutral-500">No provider mappings registered yet.</p>
      ) : (
        <div className="overflow-x-auto">
        <table className="w-full min-w-[480px] text-sm">
          <thead>
            <tr className="text-left text-xs text-neutral-500">
              <th className="pb-1">Vehicle</th>
              <th className="pb-1">Provider</th>
              <th className="pb-1">External vehicle ID</th>
              <th className="pb-1">Status</th>
            </tr>
          </thead>
          <tbody>
            {mappings.map((mapping) => (
              <tr key={mapping.id} className="border-t border-neutral-100">
                <td className="py-1">{masterLabel(vehicleMasterById, mapping.vehicleMasterId)}</td>
                <td className="py-1">{mapping.providerCode}</td>
                <td className="py-1">{mapping.externalVehicleId}</td>
                <td className="py-1">
                  <StatusBadge tone={mapping.status === "active" ? "success" : "neutral"} label={mapping.status} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Register mapping</h3>
        <RegisterProviderMappingForm vehicles={vehicles} action={registerAction} />
      </div>
    </section>
  );
}

function RegisterProviderMappingForm({ vehicles, action }: { vehicles: readonly VehicleOperationalProfile[]; action: FleetFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <select name="vehicleMasterId" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Vehicle…
        </option>
        {vehicles.map((vehicle) => (
          <option key={vehicle.vehicleMasterId} value={vehicle.vehicleMasterId}>
            {vehicle.vehicleMasterId}
          </option>
        ))}
      </select>
      <input name="providerCode" type="text" required placeholder="Provider code" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="externalVehicleId" type="text" required placeholder="External vehicle ID" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function SourcePrioritySection({
  priorities,
  vehicles,
  vehicleMasterById,
  setAction,
}: {
  priorities: readonly VehicleTrackingSourcePriority[];
  vehicles: readonly VehicleOperationalProfile[];
  vehicleMasterById: ReadonlyMap<string, MasterRecord>;
  setAction: FleetFormAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Per-vehicle source priority overrides</h2>
        <p className="text-xs text-neutral-500">
          Overrides the tenant-default source priority (Admin → Tracking) for one vehicle. A source with is_enabled unchecked can never win arbitration for that
          vehicle, regardless of priority.
        </p>
      </div>
      {priorities.length === 0 ? (
        <p className="text-sm text-neutral-500">No per-vehicle overrides set yet.</p>
      ) : (
        <div className="overflow-x-auto">
        <table className="w-full min-w-[420px] text-sm">
          <thead>
            <tr className="text-left text-xs text-neutral-500">
              <th className="pb-1">Vehicle</th>
              <th className="pb-1">Source</th>
              <th className="pb-1">Rank</th>
              <th className="pb-1">Enabled</th>
            </tr>
          </thead>
          <tbody>
            {priorities.map((priority) => (
              <tr key={priority.id} className="border-t border-neutral-100">
                <td className="py-1">{masterLabel(vehicleMasterById, priority.vehicleMasterId)}</td>
                <td className="py-1">{priority.sourceType}</td>
                <td className="py-1">{priority.priorityRank}</td>
                <td className="py-1">
                  <StatusBadge tone={priority.isEnabled ? "success" : "danger"} label={priority.isEnabled ? "enabled" : "disabled"} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Set override</h3>
        <SetSourcePriorityForm vehicles={vehicles} action={setAction} />
      </div>
    </section>
  );
}

function SetSourcePriorityForm({ vehicles, action }: { vehicles: readonly VehicleOperationalProfile[]; action: FleetFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <select name="vehicleMasterId" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Vehicle…
        </option>
        {vehicles.map((vehicle) => (
          <option key={vehicle.vehicleMasterId} value={vehicle.vehicleMasterId}>
            {vehicle.vehicleMasterId}
          </option>
        ))}
      </select>
      <select name="sourceType" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Source…
        </option>
        {(["driver_mobile", "direct_device", "third_party_platform"] as const).map((sourceType) => (
          <option key={sourceType} value={sourceType}>
            {sourceType}
          </option>
        ))}
      </select>
      <input name="priorityRank" type="number" min={1} required placeholder="Rank" className="w-20 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <label className="flex items-center gap-1 text-xs text-neutral-600">
        <input name="isEnabled" type="checkbox" defaultChecked />
        Enabled
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
        Save
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
