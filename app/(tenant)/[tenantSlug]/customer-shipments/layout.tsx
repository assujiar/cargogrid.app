import type { ReactNode } from "react";
import { TenantMain } from "../../../../components/layout/tenant-main.tsx";

/**
 * `<main>` landmark for the customer-shipments module (`ISS-2026-241`). This module renders no chrome of
 * its own, so the landmark is the whole layout.
 */
export default function CustomerShipmentsModuleLayout({ children }: { children: ReactNode }) {
  return <TenantMain>{children}</TenantMain>;
}
