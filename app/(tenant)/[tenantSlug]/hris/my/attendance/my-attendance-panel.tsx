"use client";

import { useActionState, useState, useCallback } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { MyAttendanceStatus, CorrectionRequestRow, CorrectionRequestType } from "../../../../../../server/contracts/attendance/attendance.ts";
import type { AttendanceActionState } from "./actions.ts";

const INITIAL_STATE: AttendanceActionState = { error: null };

const SESSION_STATUS_TONE: Record<string, StatusTone> = { open: "info", closed: "success" };
const CORRECTION_STATUS_TONE: Record<string, StatusTone> = { pending_approval: "warning", approved: "success", rejected: "danger", cancelled: "neutral" };

type GeoState = { status: "idle" | "locating" | "ready" | "denied" | "unsupported"; lat: string; lon: string };

/**
 * Browser Geolocation capture (section 15/16). A genuine denied/unsupported
 * state is shown explicitly -- never a silently-skipped location or a fake
 * success. Location is only ever attached to the two live self-service
 * channels (mobile_web/kiosk); the server independently decides whether the
 * effective policy actually requires it (a policy of 'none' discards
 * whatever is sent here, per the migration's own decision 4).
 */
function useGeolocation() {
  const [geo, setGeo] = useState<GeoState>({ status: "idle", lat: "", lon: "" });

  const capture = useCallback(() => {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setGeo({ status: "unsupported", lat: "", lon: "" });
      return;
    }
    setGeo((prev) => ({ ...prev, status: "locating" }));
    navigator.geolocation.getCurrentPosition(
      (position) => setGeo({ status: "ready", lat: String(position.coords.latitude), lon: String(position.coords.longitude) }),
      () => setGeo({ status: "denied", lat: "", lon: "" }),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  }, []);

  return { geo, capture };
}

function ClockControls({ open, clockAction }: { open: boolean; clockAction: (prevState: AttendanceActionState, formData: FormData) => Promise<AttendanceActionState> }) {
  const [state, formAction, pending] = useActionState(clockAction, INITIAL_STATE);
  const { geo, capture } = useGeolocation();
  // Generated once per mount, not per render (react-hooks/purity) -- a fresh
  // key per real clock attempt is all decision 6/C-01 needs (the server's own
  // full-tuple idempotency comparison is the actual safety net, not the key's
  // own uniqueness scheme).
  const [idempotencyKey] = useState(() => `${open ? "out" : "in"}-${crypto.randomUUID()}`);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <input type="hidden" name="eventType" value={open ? "clock_out" : "clock_in"} />
      <input type="hidden" name="sourceChannel" value="mobile_web" />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <input type="hidden" name="lat" value={geo.lat} />
      <input type="hidden" name="lon" value={geo.lon} />

      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-neutral-900">{open ? "You are clocked in" : "Not clocked in"}</span>
        <StatusBadge tone={open ? "info" : "neutral"} label={open ? "open" : "not started"} />
      </div>

      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="button" variant="secondary" onClick={capture} disabled={geo.status === "locating"}>
          {geo.status === "ready" ? "Location captured" : geo.status === "locating" ? "Getting location…" : "Share my location"}
        </Button>
        <Button type="submit" variant={open ? "destructive" : "primary"} loading={pending} loadingLabel={open ? "Clocking out…" : "Clocking in…"} className="flex-1">
          {open ? "Clock out" : "Clock in"}
        </Button>
      </div>

      {geo.status === "denied" ? <p className="text-xs text-warning">Location permission was denied -- some policies require a verified location to clock in/out; this attempt may be rejected.</p> : null}
      {geo.status === "unsupported" ? <p className="text-xs text-warning">This browser does not support location capture.</p> : null}
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function CorrectionRequestForm({
  sessionId,
  requestCorrectionAction,
}: {
  sessionId: string;
  requestCorrectionAction: (prevState: AttendanceActionState, formData: FormData) => Promise<AttendanceActionState>;
}) {
  const [state, formAction, pending] = useActionState(requestCorrectionAction, INITIAL_STATE);
  const [requestType, setRequestType] = useState<CorrectionRequestType>("adjust_clock_out");
  const [idempotencyKey] = useState(() => `corr-${sessionId}-${crypto.randomUUID()}`);

  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Request a correction for this session</h3>
      <input type="hidden" name="sessionId" value={sessionId} />
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
      <label className="text-xs text-neutral-500">
        What needs fixing?
        <select name="requestType" value={requestType} onChange={(e) => setRequestType(e.target.value as CorrectionRequestType)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="adjust_clock_in">Adjust my clock-in time</option>
          <option value="adjust_clock_out">Adjust my clock-out time</option>
          <option value="add_missing_clock_in">I forgot to clock in</option>
          <option value="add_missing_clock_out">I forgot to clock out</option>
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Correct time
        <input type="datetime-local" name="proposedTime" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Reason
        <textarea name="reason" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" rows={2} />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit for HR review
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

export function MyAttendancePanel({
  statusRows,
  corrections,
  clockAction,
  requestCorrectionAction,
}: {
  statusRows: MyAttendanceStatus[];
  corrections: CorrectionRequestRow[];
  clockAction: (prevState: AttendanceActionState, formData: FormData) => Promise<AttendanceActionState>;
  requestCorrectionAction: (prevState: AttendanceActionState, formData: FormData) => Promise<AttendanceActionState>;
}) {
  const today = statusRows[0] ?? null;
  const open = today?.status === "open";

  return (
    <div className="mx-auto flex max-w-lg flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">My attendance</h1>

      <ClockControls open={open} clockAction={clockAction} />

      {today?.sessionId ? <CorrectionRequestForm sessionId={today.sessionId} requestCorrectionAction={requestCorrectionAction} /> : null}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Recent days</h2>
        {statusRows.length === 0 ? (
          <EmptyState title="No attendance history yet" description="Clock in above to start your record." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="p-2">Date</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Clock in</th>
                  <th className="p-2">Clock out</th>
                  <th className="p-2">Exceptions</th>
                </tr>
              </thead>
              <tbody>
                {statusRows.map((row) => (
                  <tr key={row.sessionId ?? row.workDate} className="border-t border-neutral-100">
                    <td className="p-2">{row.workDate}</td>
                    <td className="p-2">
                      <StatusBadge tone={row.status ? SESSION_STATUS_TONE[row.status] ?? "neutral" : "neutral"} label={row.status ?? "—"} />
                    </td>
                    <td className="p-2 text-xs">{row.effectiveClockInAt ? new Date(row.effectiveClockInAt).toLocaleTimeString() : "—"}</td>
                    <td className="p-2 text-xs">{row.effectiveClockOutAt ? new Date(row.effectiveClockOutAt).toLocaleTimeString() : "—"}</td>
                    <td className="p-2">{row.openExceptionCount > 0 ? <StatusBadge tone="warning" label={String(row.openExceptionCount)} /> : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">My correction requests</h2>
        {corrections.length === 0 ? (
          <EmptyState title="No correction requests" description="Requests you submit will appear here with their review status." />
        ) : (
          <ul className="flex flex-col gap-2">
            {corrections.map((c) => (
              <li key={c.id} className="flex items-center justify-between rounded-md border border-neutral-200 p-3 text-sm">
                <span>
                  {c.workDate} — {c.requestType.replace(/_/g, " ")}
                </span>
                <StatusBadge tone={CORRECTION_STATUS_TONE[c.status] ?? "neutral"} label={c.status.replace(/_/g, " ")} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
