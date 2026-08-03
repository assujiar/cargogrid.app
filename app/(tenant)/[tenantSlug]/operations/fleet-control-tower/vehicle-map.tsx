"use client";

/**
 * Live vehicle map (ATW-226H) -- the first Leaflet map in this repository. Both
 * operations/dispatch-board and operations/fleet's own page-level comments explicitly
 * disclosed this as a deferred gap ("an interactive map view is deferred -- no map
 * library exists in this repository yet"); this is the checkpoint whose own job is to
 * close it.
 *
 * Leaflet is imported dynamically inside an effect, never at module scope -- its own
 * module-init code touches `window`/`navigator` for browser-feature detection and would
 * break this route's server render if imported statically in a file Next still renders
 * once on the server before hydration.
 */

import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";
import type * as Leaflet from "leaflet";
import type { TenantVehicleTrackingOverviewRow } from "../../../../../server/contracts/fleet-control-tower/fleet-control-tower.ts";

export interface VehicleMapProps {
  readonly vehicles: readonly TenantVehicleTrackingOverviewRow[];
}

// Jakarta -- matches this repository's own test-fixture default region, used only as
// the map's initial view before any vehicle position is known.
const FALLBACK_CENTER: [number, number] = [-6.2, 106.816666];
const FALLBACK_ZOOM = 5;

export function VehicleMap({ vehicles }: VehicleMapProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<Leaflet.Map | null>(null);
  const markersRef = useRef<Leaflet.Marker[]>([]);

  useEffect(() => {
    let cancelled = false;

    void import("leaflet").then((L) => {
      if (cancelled || !containerRef.current || mapRef.current) {
        return;
      }
      const map = L.map(containerRef.current).setView(FALLBACK_CENTER, FALLBACK_ZOOM);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 19,
      }).addTo(map);
      mapRef.current = map;
    });

    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    void import("leaflet").then((L) => {
      const map = mapRef.current;
      if (cancelled || !map) {
        return;
      }

      markersRef.current.forEach((marker) => marker.remove());
      markersRef.current = [];

      const tracked = vehicles.filter((vehicle) => vehicle.currentLocation !== null);
      const positions: [number, number][] = [];
      for (const vehicle of tracked) {
        const location = vehicle.currentLocation;
        if (!location) {
          continue;
        }
        const [lng, lat] = location.coordinates;
        positions.push([lat, lng]);
        const marker = L.marker([lat, lng])
          .addTo(map)
          .bindPopup(`<strong>${vehicle.vehicleCode}</strong><br/>${vehicle.vehicleName}<br/>Source: ${vehicle.currentSourceType ?? "unknown"}`);
        markersRef.current.push(marker);
      }

      if (positions.length > 0) {
        map.fitBounds(L.latLngBounds(positions), { padding: [32, 32], maxZoom: 14 });
      }
    });

    return () => {
      cancelled = true;
    };
  }, [vehicles]);

  const trackedCount = vehicles.filter((vehicle) => vehicle.currentLocation !== null).length;

  return (
    <div className="flex flex-col gap-2">
      <div ref={containerRef} role="img" aria-label="Live vehicle map" style={{ height: 420 }} className="rounded-md border border-neutral-200" />
      <p className="text-xs text-neutral-500">
        {trackedCount} of {vehicles.length} vehicles have a live position.
      </p>
    </div>
  );
}
