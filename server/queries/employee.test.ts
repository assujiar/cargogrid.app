import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listEmployees,
  getEmployeeProfile,
  getMyEmployeeProfile,
  listMyTeamEmployees,
  getEmployeeLifecycleHistory,
  listEmployeeEmergencyContacts,
  searchEmployeeDuplicateCandidates,
  exportEmployees,
  EmployeeQueryError,
  type EmployeeQueryClient,
} from "./employee.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: EmployeeQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EmployeeQueryClient;
  return { client, calls };
}

describe("listEmployees", () => {
  test("calls list_employees with mapped snake_case args and default pagination", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listEmployees(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_employees");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status_filter: null,
      p_department_org_unit_id: null,
      p_search: null,
      p_limit: 50,
      p_after_employee_number: null,
    });
  });

  test("threads through explicit filter/search/pagination options", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listEmployees(client, TENANT_ID, ACTOR_ID, { statusFilter: "active", departmentOrgUnitId: MASTER_RECORD_ID, search: "Budi", limit: 10, afterEmployeeNumber: "EMP-2026-000001" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status_filter: "active",
      p_department_org_unit_id: MASTER_RECORD_ID,
      p_search: "Budi",
      p_limit: 10,
      p_after_employee_number: "EMP-2026-000001",
    });
  });

  test("throws EmployeeQueryError on an RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(() => listEmployees(client, TENANT_ID, ACTOR_ID), EmployeeQueryError);
  });
});

describe("getEmployeeProfile", () => {
  test("parses the first row and throws when the RPC returns nothing", async () => {
    const { client } = fakeClient({ data: [], error: null });
    await assert.rejects(() => getEmployeeProfile(client, MASTER_RECORD_ID, ACTOR_ID), EmployeeQueryError);
  });
});

describe("getMyEmployeeProfile", () => {
  test("returns null (never throws) when the RPC returns zero rows", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getMyEmployeeProfile(client, TENANT_ID, ACTOR_ID);
    assert.equal(result, null);
  });

  test("parses a real row when present", async () => {
    const { client } = fakeClient({
      data: [
        {
          master_record_id: MASTER_RECORD_ID,
          employee_number: "EMP-2026-000008",
          tenant_id: TENANT_ID,
          user_id: ACTOR_ID,
          full_name: "Own Profile Person",
          employment_type: "full_time",
          lifecycle_status: "active",
          intake_source: "hr_created",
          work_email: null,
          work_phone: null,
          personal_email: null,
          personal_phone: null,
          national_id_number: null,
          date_of_birth: null,
          gender: null,
          personal_address_street: null,
          personal_address_city: null,
          personal_address_province: null,
          personal_address_postal_code: null,
          personal_address_country: null,
          hire_date: null,
          probation_end_date: null,
          employment_end_date: null,
          company_org_unit_id: null,
          branch_org_unit_id: null,
          department_org_unit_id: null,
          position_title: null,
          manager_employee_id: null,
          record_version: 1,
          created_at: "2026-08-09T00:00:00.000Z",
          updated_at: "2026-08-09T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getMyEmployeeProfile(client, TENANT_ID, ACTOR_ID);
    assert.equal(result?.fullName, "Own Profile Person");
  });
});

describe("listMyTeamEmployees / getEmployeeLifecycleHistory / listEmployeeEmergencyContacts", () => {
  test("listMyTeamEmployees maps default pagination", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyTeamEmployees(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 50, p_after_employee_number: null });
  });

  test("getEmployeeLifecycleHistory maps args and parses rows", async () => {
    const { client, calls } = fakeClient({
      data: [{ id: MASTER_RECORD_ID, master_record_id: MASTER_RECORD_ID, from_status: "draft", to_status: "submitted", reason: null, metadata: {}, actor_label: "staff", occurred_at: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    const result = await getEmployeeLifecycleHistory(client, MASTER_RECORD_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_employee_lifecycle_history");
    assert.equal(result.length, 1);
    assert.equal(result[0]?.toStatus, "submitted");
  });

  test("listEmployeeEmergencyContacts parses masked rows", async () => {
    const { client } = fakeClient({
      data: [{ id: MASTER_RECORD_ID, master_record_id: MASTER_RECORD_ID, name: "Contact", relationship: null, phone: null, email: null, is_primary: true, record_version: 1, created_at: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    const result = await listEmployeeEmergencyContacts(client, MASTER_RECORD_ID, ACTOR_ID);
    assert.equal(result[0]?.phone, null);
  });
});

describe("searchEmployeeDuplicateCandidates / exportEmployees", () => {
  test("searchEmployeeDuplicateCandidates maps optional search dimensions", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await searchEmployeeDuplicateCandidates(client, TENANT_ID, ACTOR_ID, { fullName: "Budi", nationalIdNumber: "3201" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_full_name: "Budi",
      p_national_id_number: "3201",
      p_work_email: null,
      p_personal_email: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_limit: 10,
    });
  });

  test("exportEmployees returns the scoped, non-PII projection rows", async () => {
    const { client } = fakeClient({
      data: [{ employee_number: "EMP-2026-000009", full_name: "Export Person", employment_type: "full_time", lifecycle_status: "active", hire_date: null, department_org_unit_id: null, position_title: null }],
      error: null,
    });
    const result = await exportEmployees(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.employeeNumber, "EMP-2026-000009");
    assert.deepEqual(Object.keys(result[0] ?? {}).includes("personalEmail" as never), false);
  });
});
