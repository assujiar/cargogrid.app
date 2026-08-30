import type { ReactNode } from "react";
import { TenantMain } from "../../../../components/layout/tenant-main.tsx";

/**
 * `<main>` landmark for the automation-rules module (`ISS-2026-241`). This module renders no chrome of
 * its own, so the landmark is the whole layout.
 */
export default function AutomationRulesModuleLayout({ children }: { children: ReactNode }) {
  return <TenantMain>{children}</TenantMain>;
}
