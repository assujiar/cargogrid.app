import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseDocumentRequirementDefinition,
  parseShipmentDocumentChecklistItem,
  parseChecklistItemView,
  parseChecklistCompleteness,
} from "./document-requirement.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const DEFINITION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseDocumentRequirementDefinition", () => {
  test("maps snake_case columns, including nullable mode/service_type wildcards", () => {
    const definition = parseDocumentRequirementDefinition({
      id: DEFINITION_ID,
      tenant_id: TENANT_ID,
      mode: null,
      service_type: null,
      applicable_status: "delivered",
      party: "carrier",
      document_type_code: "pod",
      criticality: "mandatory",
      status: "published",
      supersedes_version_id: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-28T09:00:00.000Z",
      updated_at: "2026-07-28T09:00:00.000Z",
    });
    assert.equal(definition.mode, null);
    assert.equal(definition.status, "published");
  });
});

describe("parseShipmentDocumentChecklistItem", () => {
  test("maps snake_case columns and nullable review fields", () => {
    const item = parseShipmentDocumentChecklistItem({
      id: ITEM_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      requirement_definition_id: DEFINITION_ID,
      party: "carrier",
      document_type_code: "pod",
      criticality: "mandatory",
      file_id: null,
      review_status: "pending",
      reviewed_by_auth_user_id: null,
      reviewed_at: null,
      review_notes: null,
      expires_at: null,
      pinned_at: "2026-07-28T09:00:00.000Z",
      created_at: "2026-07-28T09:00:00.000Z",
      updated_at: "2026-07-28T09:00:00.000Z",
    });
    assert.equal(item.fileId, null);
    assert.equal(item.reviewStatus, "pending");
  });
});

describe("parseChecklistItemView", () => {
  test("maps effective_status and the joined malware_scan_status", () => {
    const view = parseChecklistItemView({
      id: ITEM_ID,
      requirement_definition_id: DEFINITION_ID,
      party: "carrier",
      document_type_code: "pod",
      criticality: "mandatory",
      file_id: FILE_ID,
      malware_scan_status: "clean",
      review_status: "approved",
      reviewed_by_auth_user_id: null,
      reviewed_at: "2026-07-28T09:05:00.000Z",
      review_notes: "signed",
      expires_at: null,
      effective_status: "approved",
    });
    assert.equal(view.effectiveStatus, "approved");
    assert.equal(view.malwareScanStatus, "clean");
  });

  test("maps a missing (never-linked) checklist item", () => {
    const view = parseChecklistItemView({
      id: ITEM_ID,
      requirement_definition_id: DEFINITION_ID,
      party: "carrier",
      document_type_code: "pod",
      criticality: "mandatory",
      file_id: null,
      malware_scan_status: null,
      review_status: "pending",
      reviewed_by_auth_user_id: null,
      reviewed_at: null,
      review_notes: null,
      expires_at: null,
      effective_status: "missing",
    });
    assert.equal(view.fileId, null);
    assert.equal(view.effectiveStatus, "missing");
  });
});

describe("parseChecklistCompleteness", () => {
  test("maps is_complete=true with zero missing_mandatory entries", () => {
    const completeness = parseChecklistCompleteness({ is_complete: true, missing_mandatory: [] });
    assert.equal(completeness.isComplete, true);
    assert.deepEqual(completeness.missingMandatory, []);
  });

  test("maps missing_mandatory rows for an incomplete checklist", () => {
    const completeness = parseChecklistCompleteness({
      is_complete: false,
      missing_mandatory: [{ checklist_item_id: ITEM_ID, document_type_code: "pod", party: "carrier" }],
    });
    assert.equal(completeness.isComplete, false);
    assert.equal(completeness.missingMandatory.length, 1);
    assert.equal(completeness.missingMandatory[0]?.documentTypeCode, "pod");
  });
});
