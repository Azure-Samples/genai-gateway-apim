
param name string

@description('Resource name to uniquely identify this API within the API Management service instance')
@minLength(1)
param apiName string

@description('Azure Application Insights Name')
param applicationInsightsName string

param openai1Endpoint string
param openai2Endpoint string

param productName string = 'APIM-AI_APIS'
param productDescription string = 'A product with AI APIs'

param resourceGroupName string = resourceGroup().name

var subscriptionId = az.subscription().subscriptionId
var apiSuffix = '${apiName}/openai'

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: name
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2021-12-01-preview' existing = if (!empty(applicationInsightsName)) {
  name: 'app-insights-logger'
  parent: apimService
}

// Creating a backend for Cog service account 1, also adding a circuit breaker rule
resource backend1 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'backend1'
  properties: {
    url: '${openai1Endpoint}openai'
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
resource backend2 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'backend2'
  properties: {
    url: '${openai2Endpoint}openai'
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


// Create a load balancer (pool) for the backends where backend1 and backend2 are added
resource loadBalancing 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'LoadBalancer'
  properties: {
    description: 'Load balancer for multiple backends'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ApiManagement/service/${apimService.name}/backends/${backend1.id}'
        }
        {
          id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ApiManagement/service/${apimService.name}/backends/${backend2.id}'
        }
      ]
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
    path: apiSuffix
    format: 'openapi+json-link'
    value: 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/preview/2024-03-01-preview/inference.json'
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
    
  }
  resource apimDiagnostics 'diagnostics@2023-05-01-preview' = {
    name: 'applicationinsights' // Use a supported diagnostic identifier
    properties: {
      loggerId: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apimService.name}/loggers/${apimLogger.name}'
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
var headerPolicyXml = format(loadTextContent('./apim-api-policy.xml'), loadBalancing.name, 5000)

// Create a policy for the API, using the headerPolicyXml variable
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2020-06-01-preview' = {
  parent: api1
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: headerPolicyXml
  }
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

output subscriptionKey string = subscription.listSecrets().primaryKey
output apiSuffix string = apiSuffix
