targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param resourceGroupName string = ''

@description('Location for the OpenAI resource group')
@allowed(['australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth', 'westeurope'])
@metadata({
  azd: {
    type: 'location'
  }
})
param openAiLocation string // Set in main.parameters.json
param openAiApiVersion string // Set in main.parameters.json

param apiName string = 'myAPI'

param productName string = 'APIM-AI_APIS'
param productDescription string = 'A product with AI APIs'

@description('When true, deploys two AOAI accounts behind the APIM load-balancer pool. When false, deploys only one AOAI account (the pool still exists but contains a single backend).')
param deployTwoBackends bool = true

// --- Shared platform wiring -------------------------------------------------
// These come from the platform stack outputs (platform/main.bicep). Set them
// into the azd env with `azd env set` — platform/deploy.sh prints the commands.
@description('Name of the shared APIM service this pattern attaches to.')
param sharedApimName string

@description('Resource group that holds the shared APIM (and shared monitoring).')
param sharedApimResourceGroup string

@description('System-assigned principalId of the shared APIM. Granted Cognitive Services OpenAI User on this pattern\'s AOAI accounts.')
param sharedApimPrincipalId string

@description('Name of the shared Application Insights instance (for this pattern\'s per-API diagnostics).')
param sharedApplicationInsightsName string

@description('Short pattern id (a/b/d). Disambiguates this pattern\'s resources on the shared APIM and tags its spend.')
param patternSuffix string = 'a'
// ---------------------------------------------------------------------------

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
// This pattern's API name on the shared APIM must be unique across patterns.
var patternApiName = '${apiName}-${patternSuffix}'
// Tagging schema for Azure Cost Management — applies to every resource via
// the `tags` param threaded through every module.
//   cs-integration-pattern: a/b/c/d per cs-integration-patterns.html.
//                           Lets Cost Analysis group spend by integration pattern.
//   recon-role:             distinguishes recon test targets (reference-deployment)
//                           from real workloads (production-landing-zone, etc.).
// Cost Management aggregates new tag dimensions on an 8-24h delay.
var tags = {
  'azd-env-name': environmentName
  'cs-integration-pattern': patternSuffix
  'recon-role': 'reference-deployment'
}

// This pattern's own resource group — holds its AOAI accounts + role grant.
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Existing shared-platform resource group — the API/backends/policy are created
// here, as children of the shared APIM, even though AOAI lives in our own RG.
resource platformResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: sharedApimResourceGroup
}

// FIRST: creating Azure Cognitive Services account for OpenAI
module openAi1 'core/ai/cognitiveservices.bicep' = {
  name: 'openai1'
  scope: resourceGroup
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}-${patternSuffix}-AOAI1'
    location: openAiLocation
    tags: tags
    sku: {
      name: 'S0'
    }
    disableLocalAuth: true
    deployments: [
      {
        name: 'conversation-model'
        raiPolicyName: 'Microsoft.Default'
        model: {
          format: 'OpenAI'
          name: 'gpt-4.1-mini'
          version: '2025-04-14'
        }
        sku: {
          name: 'Standard'
          capacity: 50
        }
      }
    ]
  }
}

// SECOND: creating Azure Cognitive Services account for OpenAI (only when deployTwoBackends)
module openAi2 'core/ai/cognitiveservices.bicep' = if (deployTwoBackends) {
  name: 'openai2'
  scope: resourceGroup
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}-${patternSuffix}-AOAI2'
    location: openAiLocation
    tags: tags
    sku: {
      name: 'S0'
    }
    disableLocalAuth: true
    deployments: [
      {
        name: 'conversation-model'
        raiPolicyName: 'Microsoft.Default'
        model: {
          format: 'OpenAI'
          name: 'gpt-4.1-mini'
          version: '2025-04-14'
        }
        sku: {
          name: 'Standard'
          capacity: 50
        }
      }
    ]
  }
}

// This pattern's API, backends, load balancer, policy, product and subscription,
// created on the SHARED APIM (hence scope: platformResourceGroup).
module api 'app/apim-api.bicep' = {
  name: 'api-${patternSuffix}'
  scope: platformResourceGroup
  params: {
    name: sharedApimName
    applicationInsightsName: sharedApplicationInsightsName
    apiName: patternApiName
    patternSuffix: patternSuffix
    productName: productName
    productDescription: productDescription
    deployTwoBackends: deployTwoBackends
    openai1Endpoint: openAi1.outputs.endpoint
    openai2Endpoint: deployTwoBackends ? openAi2.outputs.endpoint : ''
  }
}

// Grant the shared APIM's managed identity Cognitive Services OpenAI User over
// this pattern's RG (covers both AOAI accounts — one RG-scoped grant is enough;
// the previous two-module form produced an identical guid and silently no-op'd).
module openAiRoleApim 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'openai-role-apim-${patternSuffix}'
  params: {
    principalId: sharedApimPrincipalId
    // Cognitive Services OpenAI User
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroup.name

output DEPLOYMENT_ID string = 'conversation-model'
output API_VERSION string = openAiApiVersion
output APIM_ENDPOINT string = 'https://${sharedApimName}.azure-api.net'
output API_SUFFIX string = api.outputs.apiSuffix
output SUBSCRIPTION_KEY string = api.outputs.subscriptionKey
