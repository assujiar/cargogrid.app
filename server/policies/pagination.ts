/**
 * Cursor-pagination primitives (PLT-130, CG-S6-PLT-027). A cursor opaquely encodes the
 * last-seen row's own keyset ordering value -- never a raw offset -- matching
 * docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §7's "keyset mandatory for
 * shipment_milestones/audit_logs/event_logs/inventory_ledger/tickets" convention. The
 * cursor is base64url-encoded so it is URL-safe and opaque to the caller -- a client is
 * never meant to construct or parse one itself, only pass back what a prior page
 * returned.
 */

import type { PageInfo } from "../contracts/api/api.ts";

export interface CursorPayload {
  readonly sortValue: string;
  readonly id: string;
}

export function encodeCursor(payload: CursorPayload): string {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

export class InvalidCursorError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidCursorError";
  }
}

export function decodeCursor(cursor: string): CursorPayload {
  let json: string;
  try {
    json = Buffer.from(cursor, "base64url").toString("utf8");
  } catch {
    throw new InvalidCursorError(`cursor is not valid base64url: ${cursor}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new InvalidCursorError(`cursor did not decode to valid JSON: ${cursor}`);
  }
  if (
    !parsed ||
    typeof parsed !== "object" ||
    typeof (parsed as Record<string, unknown>).sortValue !== "string" ||
    typeof (parsed as Record<string, unknown>).id !== "string"
  ) {
    throw new InvalidCursorError(`cursor did not decode to a well-formed { sortValue, id } payload: ${cursor}`);
  }
  return parsed as CursorPayload;
}

/** The one place both a REST list endpoint and a GraphQL connection field build a PageInfo -- so they can never drift into two different pagination behaviors. */
export function buildPageInfo(input: {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  nextCursorPayload: CursorPayload | null;
  previousCursorPayload: CursorPayload | null;
}): PageInfo {
  return {
    hasNextPage: input.hasNextPage,
    hasPreviousPage: input.hasPreviousPage,
    nextCursor: input.nextCursorPayload ? encodeCursor(input.nextCursorPayload) : null,
    previousCursor: input.previousCursorPayload ? encodeCursor(input.previousCursorPayload) : null,
  };
}
