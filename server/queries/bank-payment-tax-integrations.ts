/**
 * Bank, Payment Gateway, E-Invoice and Tax Integrations queries (IAE-017,
 * Prompt 345). Thin, typed wrappers around
 * app.list_finance_payment_gateway_events_for_tenant /
 * app.get_finance_provider_dispatch_info / app.get_finance_provider_credential /
 * app.get_finance_provider_connection_for_sync /
 * app.list_finance_provider_call_evidence_for_tenant
 * (supabase/migrations/20260805040000_create_intelligence_bank_payment_einvoice_tax_integrations.sql).
 */

import {
  ListFinancePaymentGatewayEventsForTenantInputSchema,
  parseFinancePaymentGatewayEvent,
  parseFinanceProviderDispatchInfo,
  parseFinanceProviderConnectionForSync,
  ListFinanceProviderCallEvidenceForTenantInputSchema,
  parseFinanceProviderCallEvidence,
  type ListFinancePaymentGatewayEventsForTenantInput,
  type FinancePaymentGatewayEvent,
  type FinanceProviderDispatchInfo,
  type FinanceProviderConnectionForSync,
  type ListFinanceProviderCallEvidenceForTenantInput,
  type FinanceProviderCallEvidence,
} from "../contracts/bank-payment-tax-integrations/bank-payment-tax-integrations.ts";

export interface FinanceIntegrationsQueryRpcClient {
  rpc(
    fn:
      | "list_finance_payment_gateway_events_for_tenant"
      | "get_finance_provider_dispatch_info"
      | "get_finance_provider_credential"
      | "get_finance_provider_connection_for_sync"
      | "list_finance_provider_call_evidence_for_tenant",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class FinanceIntegrationsQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FinanceIntegrationsQueryError";
  }
}

/** Authority: FIN:View for the tenant. */
export async function listFinancePaymentGatewayEventsForTenant(client: FinanceIntegrationsQueryRpcClient, input: ListFinancePaymentGatewayEventsForTenantInput): Promise<FinancePaymentGatewayEvent[]> {
  const parsedInput = ListFinancePaymentGatewayEventsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_finance_payment_gateway_events_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_bank_transaction_id: parsedInput.bankTransactionId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new FinanceIntegrationsQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new FinanceIntegrationsQueryError("list_finance_payment_gateway_events_for_tenant returned a non-array result");
  }
  return data.map((row) => parseFinancePaymentGatewayEvent(row as Record<string, unknown>));
}

/** The real outbound client's own minimal read -- never the raw credential. Returns null if no active connection exists for this adapter. */
export async function getFinanceProviderDispatchInfo(client: FinanceIntegrationsQueryRpcClient, tenantId: string, actorAuthUserId: string, adapterCode: string): Promise<FinanceProviderDispatchInfo | null> {
  const { data, error } = await client.rpc("get_finance_provider_dispatch_info", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_adapter_code: adapterCode });
  if (error) {
    throw new FinanceIntegrationsQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseFinanceProviderDispatchInfo(row as Record<string, unknown>);
}

/** service_role-only. Returns null if the connection has no stored credential. */
export async function getFinanceProviderCredential(client: FinanceIntegrationsQueryRpcClient, connectionId: string): Promise<string | null> {
  const { data, error } = await client.rpc("get_finance_provider_credential", { p_connection_id: connectionId });
  if (error) {
    throw new FinanceIntegrationsQueryError(error.message);
  }
  return typeof data === "string" ? data : null;
}

/** The real bank-feed poll worker's own read -- no actor authority check (an already-authorized background job). Returns null if the connection does not exist. */
export async function getFinanceProviderConnectionForSync(client: FinanceIntegrationsQueryRpcClient, connectionId: string): Promise<FinanceProviderConnectionForSync | null> {
  const { data, error } = await client.rpc("get_finance_provider_connection_for_sync", { p_connection_id: connectionId });
  if (error) {
    throw new FinanceIntegrationsQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseFinanceProviderConnectionForSync(row as Record<string, unknown>);
}

/** Authority: FIN:View for the tenant. */
export async function listFinanceProviderCallEvidenceForTenant(client: FinanceIntegrationsQueryRpcClient, input: ListFinanceProviderCallEvidenceForTenantInput): Promise<FinanceProviderCallEvidence[]> {
  const parsedInput = ListFinanceProviderCallEvidenceForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_finance_provider_call_evidence_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_call_type: parsedInput.callType,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new FinanceIntegrationsQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new FinanceIntegrationsQueryError("list_finance_provider_call_evidence_for_tenant returned a non-array result");
  }
  return data.map((row) => parseFinanceProviderCallEvidence(row as Record<string, unknown>));
}
