// Deploys the following:
// - App Insights
// - 1 logger on service level
// - 1 API with diagnostics
//  - 1 policy on the API including
//  - Managed Identity
//  - Token limit
//  - Token metric
//  - Setting the Authorization header with the token from the Managed Identity


param location string = 'eastus2'

var APIM_NAME = 'APIM3'

var serviceName = 'service${uniqueString(resourceGroup().id)}-${APIM_NAME}'

param apiName string = 'myAPI'

resource apimService 'Microsoft.ApiManagement/service@2020-06-01-preview' existing = {
  name: serviceName
}

resource loadBalancing 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' existing = { 
  parent: apimService
  name: 'LoadBalancer'
}


// Application Insights for API Management
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: serviceName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// logger, on service level

resource aiLoggerWithSystemAssignedIdentity 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
  parent: apimService
  name: 'ailogger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger with system-assigned managed identity'
    credentials: {
      connectionString: appInsights.properties.ConnectionString
      identityClientId: 'systemAssigned'
    }
  }
}

// api + diagnostics

resource api1 'Microsoft.ApiManagement/service/apis@2020-06-01-preview' = {
  parent: apimService
  name: apiName
  properties: {
    displayName: apiName
    apiType: 'http'
    path: '${apiName}/openai'
    format: 'openapi+json-link'
    value: 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/preview/2024-03-01-preview/inference.json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
    
  }
  resource apimDiagnostics 'diagnostics@2023-05-01-preview' = {
    name: 'applicationinsights' // Use a supported diagnostic identifier
    properties: {
      loggerId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apimService.name}/loggers/${aiLoggerWithSystemAssignedIdentity.name}'
      metrics: true
    }
  }
}

// POLICY DEFINITION, see inbound section Andrei is sharing
// - Token limit implemented below
// - Token metric implemented below
// - Managed Identity implemented below, using the token from the Managed Identity to call the OpenAI service

var headerPolicyXml = format('''
<policies>
  <inbound>
    <base />
    <set-backend-service id="apim-generated-policy" backend-id="{0}" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="managed-id-access-token" ignore-error="false" /> 

    <azure-openai-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="{1}" estimate-prompt-tokens="false" retry-after-variable-name="token-limit-retry-after"/>

    <azure-openai-emit-token-metric namespace="genaidemometrics">   
                    <dimension name="Subscription ID" />
                    <dimension name="Client IP" value="@(context.Request.IpAddress)" />
    </azure-openai-emit-token-metric>

    
<set-header name="Authorization" exists-action="override"> 
    <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value> 
</set-header> 
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
''',loadBalancing.name, 5000)

// POLICY adding rate limit policy to APIs

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2020-06-01-preview' = {
  parent: api1
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: headerPolicyXml
  }
  dependsOn: [
    loadBalancing
  ]
}
