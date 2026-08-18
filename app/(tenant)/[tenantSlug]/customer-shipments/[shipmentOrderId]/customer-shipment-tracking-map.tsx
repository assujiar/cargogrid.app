"use client";

/**
 * Single-vehicle live position map (CPL-305, CG-S13-CPL-007). Mirrors app/
 * (tenant)/[tenantSlug]/operations/fleet-control-tower/vehicle-map.tsx's own
 * dynamic-import-Leaflet technique exactly (Leaflet's own module-init code
 * touches `window`/`navigator`, so it is imported inside an effect, never at
 * module scope, which would break this route's server render) -- adapted
 * for one already-sanitized GeoJSON point (app.get_customer_shipment_
 * tracking's own vehicle_position_geojson) rather than a fleet list. Not a
 * fork of that component's own logic (there is no shared logic to extract
 * yet, only a shared technique) -- a genuinely different shape: one point,
 * not a list of vehicles with popups.
 */

import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";
import type * as Leaflet from "leaflet";

export interface CustomerShipmentTrackingMapPosition {
  readonly type: string;
  readonly coordinates: readonly [number, number];
}

export interface CustomerShipmentTrackingMapProps {
  readonly position: CustomerShipmentTrackingMapPosition;
}

const DEFAULT_ZOOM = 12;

export function CustomerShipmentTrackingMap({ position }: CustomerShipmentTrackingMapProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<Leaflet.Map | null>(null);
  const markerRef = useRef<Leaflet.Marker | null>(null);
  const [lng, lat] = position.coordinates;

  useEffect(() => {
    let cancelled = false;

    void import("leaflet").then((L) => {
      if (cancelled || !containerRef.current) {
        return;
      }
      if (!mapRef.current) {
        const map = L.map(containerRef.current).setView([lat, lng], DEFAULT_ZOOM);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
          maxZoom: 19,
        }).addTo(map);
        mapRef.current = map;
      } else {
        mapRef.current.setView([lat, lng], mapRef.current.getZoom());
      }
      markerRef.current?.remove();
      markerRef.current = L.marker([lat, lng]).addTo(mapRef.current);
    });

    return () => {
      cancelled = true;
    };
  }, [lat, lng]);

  useEffect(() => {
    return () => {
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  return <div ref={containerRef} role="img" aria-label="Shipment vehicle live position" style={{ height: 280 }} className="rounded-md border border-neutral-200" />;
}
