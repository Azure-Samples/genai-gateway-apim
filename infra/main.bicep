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

param apimLocation string // Set in main.parameters.json

param publisherName string = 'myPublisherName'
param publisherEmail string = 'myPublisherEmail@example.com'
param apiName string = 'myAPI'

param productName string = 'APIM-AI_APIS'
param productDescription string = 'A product with AI APIs'

param apimName string = 'APIM8'

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// FIRST: creating Azure Cognitive Services account for OpenAI
module openAi1 'core/ai/cognitiveservices.bicep' = {
  name: 'openai1'
  scope: resourceGroup
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}-${apimName}-AOAI1'
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
          name: 'gpt-35-turbo'
          version: '0125'
        }
        sku: {
          name: 'Standard'
          capacity: 2
        }
      }
    ]
  }
}

// SECOND: creating Azure Cognitive Services account for OpenAI
module openAi2 'core/ai/cognitiveservices.bicep' = {
  name: 'openai2'
  scope: resourceGroup
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}-${apimName}-AOAI2'
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
          name: 'gpt-35-turbo'
          version: '0125'
        }
        sku: {
          name: 'Standard'
          capacity: 2
        }
      }
    ]
  }
}

// Create API Management service
// NOTE: certain features are only available in certain regions, e.g 'westcentralus' for example until this is GA
module apim 'core/gateway/apim.bicep' = {
  name: 'apim'
  scope: resourceGroup
  params: {
    name: '${abbrs.apiManagementService}${resourceToken}-${apimName}'
    location: apimLocation
    tags: tags
    sku: 'StandardV2'
    skuCount: 1
    publisherEmail: publisherEmail
    publisherName: publisherName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
  }
}

module api 'app/apim-api.bicep' = {
  name: 'api'
  scope: resourceGroup
  params: {
    name: apim.outputs.apimServiceName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    apiName: apiName
    productName: productName
    productDescription: productDescription
    openai1Endpoint: openAi1.outputs.endpoint
    openai2Endpoint: openAi2.outputs.endpoint
  }
}

// Monitor application with Azure Monitor
module monitoring 'core/monitor/monitoring.bicep' = {
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

// Roles

// Assign the role (to Cog service account 1), a role entry is added to Cognitive Services account with the following args: 
// - roleDefinitionId (Cognitive Service User), 
// - principalId (APIM service instance) 
// - scope (Cognitive Services account)
module openAi1RoleApim 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'openai1-role-apim'
  params: {
    principalId: apim.outputs.apimPrincipalId
    // Cognitive Services OpenAI User
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

// Assign the role (to Cog service account 2), a role entry is added to Cognitive Services account with the following args: 
// - roleDefinitionId (Cognitive Service User), 
// - principalId (APIM service instance) 
// - scope (Cognitive Services account)
module openAi2RoleApim 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'openai2-role-apim'
  params: {
    principalId: apim.outputs.apimPrincipalId
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
output APIM_ENDPOINT string = 'https://${apim.outputs.apimServiceName}.azure-api.net'
output API_SUFFIX string = api.outputs.apiSuffix
output SUBSCRIPTION_KEY string = api.outputs.subscriptionKey
