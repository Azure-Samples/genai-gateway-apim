
// parameters
param publisherName string = 'myPublisherName'
param publisherEmail string = 'myPublisherEmail@example.com'
param apiName string = 'myAPI'

param productName string = 'APIM-AI_APIS'
param productDescription string = 'A product with AI APIs'

var serviceName = 'service${uniqueString(resourceGroup().id)}-APIM3'

param openai_first_endpoint_name string = '${uniqueString(resourceGroup().id)}-AOAI1'

param openai_second_endpoint_name string = '${uniqueString(resourceGroup().id)}-AOAI2'

// model version: 0613
param location string = 'eastus2' // resourceGroup().location



// FIRST: creating Azure Cognitive Services account for OpenAI
resource cognitiveServicesAccount1 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openai_first_endpoint_name
  location: location
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openai_first_endpoint_name
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// SECOND: creating Azure Cognitive Services account for OpenAI
resource cognitiveServicesAccount2 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openai_second_endpoint_name
  location: location
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openai_second_endpoint_name
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}


// creating 1st deployment for the OpenAI model
resource cognitiveServicesAccountDeployment1 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: cognitiveServicesAccount1
  name: 'conversation-model'
  sku: {
    name: 'Standard'
    capacity: 2
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-35-turbo'
      version: '0613'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    currentCapacity: 2
    raiPolicyName: 'Microsoft.Default'
  }
}

// create 2nd deployment for the OpenAI model
resource cognitiveServicesAccountDeployment2 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: cognitiveServicesAccount2
  name: 'conversation-model'
  sku: {
    name: 'Standard'
    capacity: 2
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-35-turbo'
      version: '0613'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    currentCapacity: 2
    raiPolicyName: 'Microsoft.Default'
  }
}

// Create API Management service
// NOTE: certain features are only available in certain regions, e.g 'westcentralus' for example until this is GA
resource apimService 'Microsoft.ApiManagement/service@2020-06-01-preview' = {
  name: serviceName
  location: 'westcentralus'
  sku: {
    name: 'Standard' 
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ROLES

// role definition Cognitive Services User
param roleDefinitionId string = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// Assign the role (to Cog service account 1), a role entry is added to Cognitive Services account with the following args: 
// - roleDefinitionId (Cognitive Service User), 
// - principalId (APIM service instance) 
// - scope (Cognitive Services account)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(apimService.id, roleDefinitionId)
  scope: cognitiveServicesAccount1
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
    principalId: apimService.identity.principalId
  }
}

// Assign the role (to Cog service account 2), a role entry is added to Cognitive Services account with the following args:
// - roleDefinitionId (Cognitive Service User),
// - principalId (APIM service instance)
// - scope (Cognitive Services account)
resource roleAssignment2 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(apimService.id, roleDefinitionId)
  scope: cognitiveServicesAccount2
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
    principalId: apimService.identity.principalId
  }
}

param resourceGroupName string = resourceGroup().name


// 3 - POLICIES

// Creating a backend for Cog service account 1, also adding a circuit breaker rule
resource backend1 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'backend1'
  properties: {
    url: '${cognitiveServicesAccount1.properties.endpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 3
            errorReasons: [
              'Server errors'
            ]
            interval: 'P1D'
            statusCodeRanges: [
              {
                min: 500
                max: 599
              }
            ]
          }
          name: 'myBreakerRule'
          tripDuration: 'PT1H'
        }
      ]
    }
   }
 }

// Creating a backend for Cog service account 2, also adding a circuit breaker rule
resource backend2 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'backend2'
  properties: {
    url: '${cognitiveServicesAccount2.properties.endpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 3
            errorReasons: [
              'Server errors'
            ]
            interval: 'P1D'
            statusCodeRanges: [
              {
                min: 500
                max: 599
              }
            ]
          }
          name: 'myBreakerRule'
          tripDuration: 'PT1H'
        }
      ]
    }
   }
 }

var subscriptionId = az.subscription().subscriptionId

// Create a load balancer (pool) for the backends where backend1 and backend2 are added
resource loadBalancing 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'LoadBalancer'
  properties: {
    description: 'Load balancer for multiple backends'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ApiManagement/service/${serviceName}/backends/${backend1.id}'
        }
        {
          id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ApiManagement/service/${serviceName}/backends/${backend2.id}'
        }
      ]
    }
  }
}

// Create Application Insights for API Management
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: serviceName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// Create a 'logger instance' on the API Management service that logs to Application Insights
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

// Create an API in the API Management service, and a diagnostic setting that logs to Application Insights
// NOTE: diagnostic instance is added on API level, not on the service level as in the previous example
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
      loggerId: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apimService.name}/loggers/${aiLoggerWithSystemAssignedIdentity.name}'
      metrics: true
    }
  }
}

// Creating a policy for the API, adding the following:
// - `set-backend-service policy` to route the request to the load balancer, backend-id is the load balancer id
// - `authentication-managed-identity` policy to get the managed identity token
// - `azure-openai-token-limit` policy to limit the number of requests to the API
// - `azure-openai-emit-token-metric` policy to emit a metric with the token
// - `set-header` policy to add the managed identity token to the request
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

// Create a policy for the API, using the headerPolicyXml variable
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

// Creating a product for the API. Products are used to group APIs and apply policies to them
resource product 'Microsoft.ApiManagement/service/products@2020-06-01-preview' = {
  parent: apimService
  name: productName
  properties: {
    displayName: productName
    description: productDescription
    state: 'published'
    subscriptionRequired: true
  }
}

// Create PRODUCT-API association the API with the product
resource productApi1 'Microsoft.ApiManagement/service/products/apis@2020-06-01-preview' = {
  parent: product
  name: api1.name
}

// Creating a user for the API Management service
resource user 'Microsoft.ApiManagement/service/users@2020-06-01-preview' = {
  parent: apimService
  name: 'userName'
  properties: {
    firstName: 'User'
    lastName: 'Name'
    email: 'user@example.com'
    state: 'active'
  }
}

// Creating a subscription for the API Management service
// NOTE: the subscription is associated with the user and the product, AND the subscription ID is what will be used in the request to authenticate the calling client
resource subscription 'Microsoft.ApiManagement/service/subscriptions@2020-06-01-preview' = {
  parent: apimService
  name: 'subscriptionAIProduct'
  properties: {
    displayName: 'Subscribing to AI services'
    state: 'active'
    ownerId: user.id
    scope: product.id
  }
}


