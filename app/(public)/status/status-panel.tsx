"use client";

import { useCallback, useEffect, useState } from "react";
import { interpretServiceStatus, readProbeResponse, type ProbeOutcome, type ServiceStatus } from "../../../lib/status/service-status.ts";

const REFRESH_MS = 30_000;
const PROBE_TIMEOUT_MS = 8_000;

const STATE_STYLES: Record<ServiceStatus["state"], { dot: string; label: string }> = {
  operational: { dot: "bg-emerald-500", label: "Operational" },
  degraded: { dot: "bg-amber-500", label: "Degraded" },
  down: { dot: "bg-red-500", label: "Not responding" },
  unknown: { dot: "bg-neutral-400", label: "Unverified" },
};

/**
 * A probe never rejects: a status page whose own check throws tells the visitor nothing. Every
 * failure -- network, timeout, non-JSON body -- becomes `unreachable`, which is exactly what
 * the visitor experiences.
 */
async function probe(path: string): Promise<ProbeOutcome> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);
  try {
    const response = await fetch(path, { cache: "no-store", signal: controller.signal });
    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }
    return readProbeResponse(response.status, body);
  } catch {
    return "unreachable";
  } finally {
    clearTimeout(timer);
  }
}

export function StatusPanel() {
  const [status, setStatus] = useState<ServiceStatus | null>(null);
  const [checkedAt, setCheckedAt] = useState<Date | null>(null);
  const [checking, setChecking] = useState(false);

  /**
   * Returns the result rather than writing it. That is what lets the caller decide whether the
   * answer is still wanted -- during an incident the probes are exactly the ones that take the
   * full timeout to fail, so a page unmounted mid-probe must not write state afterwards.
   */
  const check = useCallback(async (): Promise<{ status: ServiceStatus; at: Date }> => {
    // Both probes at once: the interesting state is the disagreement between them, and
    // sequential checks would report it from two different moments.
    const [liveness, readiness] = await Promise.all([probe("/api/health"), probe("/api/ready")]);
    return { status: interpretServiceStatus(liveness, readiness), at: new Date() };
  }, []);

  const checkNow = useCallback(async () => {
    setChecking(true);
    try {
      const result = await check();
      setStatus(result.status);
      setCheckedAt(result.at);
    } finally {
      setChecking(false);
    }
  }, [check]);

  useEffect(() => {
    // The first check is scheduled rather than called inline. Two reasons, both real: React
    // flags any setState reachable synchronously from an effect as a cascading-render risk,
    // and a page that unmounts mid-probe must not write state afterwards -- during an incident
    // the probes are exactly the ones that take the full timeout to fail.
    let cancelled = false;
    const run = async () => {
      const result = await check();
      if (cancelled) return;
      setStatus(result.status);
      setCheckedAt(result.at);
    };
    const first = setTimeout(() => void run(), 0);
    const interval = setInterval(() => void run(), REFRESH_MS);
    return () => {
      cancelled = true;
      clearTimeout(first);
      clearInterval(interval);
    };
  }, [check]);

  const styles = status ? STATE_STYLES[status.state] : null;

  return (
    <section className="flex flex-col gap-6" aria-labelledby="status-heading">
      <div className="rounded-lg border border-neutral-200 p-6">
        {/* aria-live so a screen-reader user hears the state change on the 30s refresh rather
            than having to re-read the page to discover it. */}
        <div aria-live="polite" aria-atomic="true">
          {status === null || styles === null ? (
            <p className="text-sm text-neutral-500">Checking CargoGrid&rsquo;s status&hellip;</p>
          ) : (
            <>
              <div className="flex items-center gap-3">
                <span className={`h-3 w-3 shrink-0 rounded-full ${styles.dot}`} aria-hidden="true" />
                <h2 id="status-heading" className="text-lg font-semibold text-neutral-900">
                  {status.headline}
                </h2>
              </div>
              <p className="mt-3 text-sm text-neutral-700">{status.detail}</p>
              <p className="mt-4 text-xs text-neutral-500">
                Status: {styles.label}
                {checkedAt ? ` · last checked ${checkedAt.toLocaleTimeString()}` : null}
                {checking ? " · checking…" : null}
              </p>
            </>
          )}
        </div>
      </div>

      <button
        type="button"
        onClick={() => void checkNow()}
        className="self-start rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
      >
        Check again
      </button>

      <div className="rounded-lg border border-neutral-200 bg-neutral-50 p-6 text-sm text-neutral-700">
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">What this page can and cannot tell you</h2>
        <p>
          This page is served separately from the CargoGrid application, so it keeps working when the application or its database does
          not &mdash; which is the outage it exists to report.
        </p>
        <p className="mt-2">
          It cannot report an outage of the hosting platform itself: if that is down, this page will not load either. It also does not
          show planned maintenance or incident history. Signed-in users receive incident notices inside CargoGrid.
        </p>
      </div>
    </section>
  );
}
