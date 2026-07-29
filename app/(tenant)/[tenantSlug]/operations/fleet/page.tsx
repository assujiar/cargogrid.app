import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listVehicleOperationalProfiles,
  listDriverOperationalProfiles,
  listGpsDevices,
  listSimCards,
  FleetDriverDeviceQueryError,
} from "../../../../../server/queries/fleet-driver-device.ts";
import { searchMasterRecords, MasterDataQueryError, type MasterDataQueryRpcClient } from "../../../../../server/queries/master-data.ts";
import type { MasterRecord } from "../../../../../server/contracts/master-data/master-data.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VehicleSection, DriverSection, DeviceSection, SimSection } from "./fleet-panel.tsx";
import {
  registerVehicleAction,
  registerDriverAction,
  setDriverConsentAction,
  registerDeviceAction,
  transitionDeviceStatusAction,
  assignDeviceToVehicleAction,
  unassignDeviceFromVehicleAction,
  registerSimAction,
  assignSimToDeviceAction,
  unassignSimFromDeviceAction,
} from "./actions.ts";

function masterMap(records: readonly MasterRecord[]): ReadonlyMap<string, MasterRecord> {
  return new Map(records.map((record) => [record.id, record]));
}

/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline (ATW-223, CG-S10-ATW-004).
 * A single operational workspace over the vehicle/driver profiles, GPS devices, and SIM
 * cards that Prompt 226's telemetry ingestion will read from -- no telemetry, provider
 * webhook, or live map exists yet in this checkpoint. Vehicle/driver identity itself
 * stays in app.master_records (PLT-120); this page only manages the operational profile
 * layer on top of it.
 */
export default async function FleetPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const tenantId = access.tenant.id;

  let loadFailed = false;
  let vehicles: Awaited<ReturnType<typeof listVehicleOperationalProfiles>> = [];
  let drivers: Awaited<ReturnType<typeof listDriverOperationalProfiles>> = [];
  let devices: Awaited<ReturnType<typeof listGpsDevices>> = [];
  let sims: Awaited<ReturnType<typeof listSimCards>> = [];
  let vehicleMasterById: ReadonlyMap<string, MasterRecord> = new Map();
  let driverMasterById: ReadonlyMap<string, MasterRecord> = new Map();

  // Adapts the real Supabase client to `MasterDataQueryRpcClient`'s plain-`Promise`
  // shape -- `supabase.rpc()` itself returns a thenable `PostgrestFilterBuilder`, not a
  // structural `Promise` (missing `catch`/`finally`), which an `async` wrapper
  // normalizes without changing behavior (same pattern as
  // `lib/portal/resolve-tenant-portal-theme.server.ts`).
  const masterDataClient: MasterDataQueryRpcClient = { rpc: async (fn, args) => await supabase.rpc(fn, args) };

  try {
    const [vehicleProfiles, driverProfiles, gpsDevices, simCards, vehicleMasters, driverMasters] = await Promise.all([
      listVehicleOperationalProfiles(supabase, tenantId),
      listDriverOperationalProfiles(supabase, tenantId),
      listGpsDevices(supabase, tenantId),
      listSimCards(supabase, tenantId),
      searchMasterRecords(masterDataClient, { masterTypeCode: "vehicle", tenantId, query: null, limit: 200, afterCode: null }),
      searchMasterRecords(masterDataClient, { masterTypeCode: "driver", tenantId, query: null, limit: 200, afterCode: null }),
    ]);
    vehicles = vehicleProfiles;
    drivers = driverProfiles;
    devices = gpsDevices;
    sims = simCards;
    vehicleMasterById = masterMap(vehicleMasters);
    driverMasterById = masterMap(driverMasters);
  } catch (error) {
    if (!(error instanceof FleetDriverDeviceQueryError) && !(error instanceof MasterDataQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the fleet workspace. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Fleet, drivers and devices</h1>
        <p className="text-xs text-neutral-500">
          Operational baseline for vehicles, drivers, GPS devices, and SIM cards. Telemetry ingestion and live tracking are not part of this workspace yet.
        </p>
      </div>

      <VehicleSection vehicles={vehicles} vehicleMasterById={vehicleMasterById} registerAction={registerVehicleAction.bind(null, tenantSlug)} />

      <DriverSection
        drivers={drivers}
        driverMasterById={driverMasterById}
        registerAction={registerDriverAction.bind(null, tenantSlug)}
        consentActionFor={(driverProfileId, expectedVersion, consent) => setDriverConsentAction.bind(null, tenantSlug, driverProfileId, expectedVersion, consent)}
      />

      <DeviceSection
        devices={devices}
        vehicles={vehicles}
        vehicleMasterById={vehicleMasterById}
        registerAction={registerDeviceAction.bind(null, tenantSlug)}
        transitionActionFor={(deviceId, expectedVersion) => transitionDeviceStatusAction.bind(null, tenantSlug, deviceId, expectedVersion)}
        assignActionFor={(deviceId) => assignDeviceToVehicleAction.bind(null, tenantSlug, deviceId)}
        unassignActionFor={(deviceId) => unassignDeviceFromVehicleAction.bind(null, tenantSlug, deviceId)}
      />

      <SimSection
        sims={sims}
        devices={devices}
        registerAction={registerSimAction.bind(null, tenantSlug)}
        assignActionFor={(simId) => assignSimToDeviceAction.bind(null, tenantSlug, simId)}
        unassignActionFor={(simId) => unassignSimFromDeviceAction.bind(null, tenantSlug, simId)}
      />
    </div>
  );
}
