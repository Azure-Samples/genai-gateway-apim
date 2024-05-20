
// Deployes the following:
// - 3 backends
//  - 1 load balancer
//  - 1 backend with circuit breaker policy, tied to cog service account 1
//  - 1 backend with circuit breaker policy, tied to cog service account 2 

param serviceName string = 'servicewiu65klfbzao6-APIM3'

// add the policies
resource apimService 'Microsoft.ApiManagement/service@2020-06-01-preview' existing = {
  name: serviceName
}

resource cognitiveServicesAccount1 'Microsoft.CognitiveServices/accounts@2021-04-30' existing = {
  name: 'wiu65klfbzao6-AOAI1'
}

resource cognitiveServicesAccount2 'Microsoft.CognitiveServices/accounts@2021-04-30' existing = {
  name: 'wiu65klfbzao6-AOAI2'
}

param resourceGroupName string = resourceGroup().name

// POLICY1/BACKEND: create a backend that wires up "circuit breaker policy" to the Cognitive Services account
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

 // POLICY/BACKEND: create a backend that wires up "circuit breaker policy" to the Cognitive Services account
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

// POLICY, load balancing
resource loadBalancing 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'LoadBalancer'
  properties: {
    description: 'Load balancer for multiple backends'
    type: 'Pool'
    // protocol: 'http' // TODO, maybe not required
    // url: 'https://example.com' // TODO, maybe not required
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
