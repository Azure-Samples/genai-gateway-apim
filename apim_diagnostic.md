# APIM monitoring — pipelines, tables, and what's missing here

## TL;DR

APIM has **two independent telemetry pipelines**. They are configured by
different resource types, write to **different Log Analytics tables**, and
neither one implies the other. This repo currently wires up pipeline (1) only.

| # | Pipeline | Configured by | Writes to (table) |
|---|---|---|---|
| 1 | APIM → App Insights logger | `Microsoft.ApiManagement/service/loggers` + `…/diagnostics` (APIM-scoped child resources) | `AppRequests`, `AppDependencies`, `AppMetrics`, `AppTraces`, `AppExceptions` |
| 2 | APIM → Azure Monitor diagnostic setting | `Microsoft.Insights/diagnosticSettings` on the APIM resource | `AzureDiagnostics` (or `ApiManagementGatewayLogs` in resource-specific mode) |

Both can run simultaneously; they don't overlap and don't replace each other.
The App Insights logger never populates `AzureDiagnostics`, regardless of how
it is configured.

---

## Pipeline 1 — APIM → App Insights logger (what this repo deploys)

Two child resources of the APIM service:

- **Logger** (`Microsoft.ApiManagement/service/loggers`) — registers an App
  Insights instance as a sink. Name in this repo: `app-insights-logger`
  (`infra/core/gateway/apim.bicep:65`).
- **Diagnostic** (`Microsoft.ApiManagement/service/diagnostics`) — turns the
  logger on for a given API and sets sampling, verbosity, header/body
  capture, etc. Defined per-API at `infra/app/apim-api.bicep:137`.

App Insights then forwards into its backing Log Analytics workspace, where
the data shows up in the **App Insights table family**:

```kql
AppRequests
| where AppRoleName == "<apim-service-name>"
| project TimeGenerated, Name, ResultCode, DurationMs, Url
| take 50
```

You also get the per-policy custom metrics (e.g. token counts emitted by the
`azure-openai-emit-token-metric` policy in `apim-api-policy.xml`) under
`AppMetrics` / `customMetrics`.

What this pipeline **does not** give you:
- Raw gateway access logs in `AzureDiagnostics` / `ApiManagementGatewayLogs`.
- Subscription-key-level audit fields, full per-request backend status, etc.,
  with the same shape as platform logs. You can approximate some of this via
  App Insights, but the schemas differ.

## Pipeline 2 — Azure Monitor diagnostic settings (what is missing)

Adds a `Microsoft.Insights/diagnosticSettings` resource **scoped to the APIM
service** that ships selected platform log categories to Log Analytics
(or Storage / Event Hubs).

Categories APIM exposes today:

- `GatewayLogs` — per-request gateway log (the most useful one)
- `WebSocketConnectionLogs`
- `GenAIPromptAndCompletionLogs` (preview, AI-Gateway-specific)
- `AllMetrics` (platform metrics)

Where it lands depends on the `logAnalyticsDestinationType` flag on the
diagnostic setting:

- **default (unset / `AzureDiagnostics`)** → single `AzureDiagnostics` table,
  rows distinguished by `ResourceType == "APIMANAGEMENT"`. Easier to add
  alongside other services, harder to query.
- **`Dedicated`** (a.k.a. resource-specific) → dedicated typed tables like
  `ApiManagementGatewayLogs`. Cleaner schema, recommended for new
  deployments. **One-way switch** per workspace once enabled.

Sample query in resource-specific mode:

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| summarize count() by ResponseCode, ApiId, OperationId
```

---

## Adding the missing piece to this repo's Bicep

The Log Analytics workspace already exists — `monitoring.bicep` outputs
`logAnalyticsWorkspaceId` (`infra/core/monitor/monitoring.bicep:32`). It just
isn't passed down to the APIM module, and the diagnostic-setting resource
isn't declared anywhere.

Three small changes:

### 1. `infra/core/gateway/apim.bicep` — accept the workspace ID and create the diagnostic setting

```bicep
@description('Log Analytics workspace resource ID. If empty, no diagnostic setting is created.')
param logAnalyticsWorkspaceId string = ''

// …existing apimService + apimLogger resources unchanged…

resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'apim-to-log-analytics'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'  // resource-specific tables (ApiManagementGatewayLogs)
    logs: [
      { category: 'GatewayLogs', enabled: true }
      { category: 'WebSocketConnectionLogs', enabled: true }
      // Uncomment if you want raw prompt/completion bodies in logs (preview, big volume):
      // { category: 'GenAIPromptAndCompletionLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}
```

> Drop `logAnalyticsDestinationType` (or set it to `AzureDiagnostics`) if you
> want rows to land in the shared `AzureDiagnostics` table instead.

### 2. `infra/main.bicep` — wire the output through

Find the `apim` module call and add the new parameter:

```bicep
module apim 'core/gateway/apim.bicep' = {
  name: 'apim'
  scope: resourceGroup
  params: {
    // …existing params…
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId  // NEW
  }
}
```

### 3. Verify after `azd up`

> Note: `azd provision --preview` will **not** show this diagnostic setting —
> ARM `what-if` misses extension resources. The compiled template does include
> it; see [arm_what_if_limitations.md](arm_what_if_limitations.md) for why and
> what else to distrust in the preview output.

```bash
# Should show the new diagnostic setting
az monitor diagnostic-settings list \
  --resource $(az apim show -n <apim-name> -g <rg> --query id -o tsv) \
  -o table

# Then in the Log Analytics workspace (give it a couple of minutes after a request):
#   ApiManagementGatewayLogs | take 10        (Dedicated mode)
#   AzureDiagnostics | where ResourceType == "APIMANAGEMENT" | take 10   (default mode)
```

## When to actually add pipeline 2 in this repo

Worth it if you want:
- Gateway access logs with subscription / product / API / operation IDs in a
  stable schema (recon correlation, audit, abuse investigation).
- Long retention or export to Storage / Event Hubs separate from App Insights.
- Alerts driven off `ApiManagementGatewayLogs` (some KQL is easier there than
  on `AppRequests`).

Probably not worth it if App Insights `AppRequests` + token metrics already
cover everything the recon harness asserts on. Costs are workspace-ingestion
cents per GB, but `GenAIPromptAndCompletionLogs` in particular can balloon
quickly if you log full bodies on every call.
