// =============================================================================
// Shared platform stack (the "bootstrapper")
// =============================================================================
// Deployed ONCE, ahead of any pattern workload, via `az deployment sub create`
// (see platform/deploy.sh). It owns the resources that are shared across every
// recon pattern (a/b/d) so they are paid for once:
//   - the API Management instance (Basic v2 by default — the single big fixed cost)
//   - Log Analytics + Application Insights + the APIM app-insights-logger
//   - the service-level (all-APIs) global policy: api-version defaulting
//
// Pattern workloads (infra/main.bicep) attach their own API, backends, policy,
// product and subscription to this APIM by name, across resource groups.
// =============================================================================

targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the shared-platform environment; seeds the resource-name hash. e.g. "shared-platform".')
param environmentName string

@minLength(1)
@description('Location for the shared resource group + monitoring.')
param location string

@description('Location for the APIM instance. Defaults to West Europe to match the pattern workloads.')
param apimLocation string = 'westeurope'

@description('APIM pricing tier. Basic v2 (~$150/mo) is the cheapest tier that still supports backend pools + circuit breaker. Flip to StandardV2 if Basic v2 rejects the load-balancer pool.')
@allowed([ 'BasicV2', 'StandardV2', 'PremiumV2' ])
param apimSku string = 'BasicV2'

param resourceGroupName string = ''
param apimName string = 'SHARED'
param publisherName string = 'myPublisherName'
param publisherEmail string = 'myPublisherEmail@example.com'

var abbrs = loadJsonContent('../infra/abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  'recon-role': 'shared-platform'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Shared monitoring — every pattern's API diagnostics + token metrics land here.
module monitoring '../infra/core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
  }
}

// The one shared APIM instance + the app-insights-logger child.
module apim '../infra/core/gateway/apim.bicep' = {
  name: 'apim'
  scope: resourceGroup
  params: {
    name: '${abbrs.apiManagementService}${resourceToken}-${apimName}'
    location: apimLocation
    tags: tags
    sku: apimSku
    skuCount: 1
    publisherEmail: publisherEmail
    publisherName: publisherName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Service-level (all-APIs) policy: default api-version. Shared by every pattern,
// so it lives here and is set exactly once — not re-applied by each workload.
module globalPolicy 'apim-service-policy.bicep' = {
  name: 'apim-global-policy'
  scope: resourceGroup
  params: {
    apimServiceName: apim.outputs.apimServiceName
  }
}

// Outputs to feed each pattern workload (set these into the workload azd env —
// deploy.sh prints the exact `azd env set` commands).
output SHARED_APIM_NAME string = apim.outputs.apimServiceName
output SHARED_APIM_RESOURCE_GROUP string = resourceGroup.name
output SHARED_APIM_PRINCIPAL_ID string = apim.outputs.apimPrincipalId
output SHARED_APPLICATION_INSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output APIM_ENDPOINT string = 'https://${apim.outputs.apimServiceName}.azure-api.net'
