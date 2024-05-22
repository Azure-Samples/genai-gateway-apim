
// Deployes the following:
// - 3 backends
//  - 1 load balancer
//  - 1 backend with circuit breaker policy, tied to cog service account 1
//  - 1 backend with circuit breaker policy, tied to cog service account 2 

var APIM_NAME = 'APIM3'

var serviceName = 'service${uniqueString(resourceGroup().id)}-${APIM_NAME}'

var cognitiveServicesAccountName1 = '${uniqueString(resourceGroup().id)}-${APIM_NAME}-AOAI1'

var cognitiveServicesAccountName2 = '${uniqueString(resourceGroup().id)}-${APIM_NAME}-AOAI2'

// add the policies
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: serviceName
}

resource cognitiveServicesAccount1 'Microsoft.CognitiveServices/accounts@2021-04-30' existing = {
  name: cognitiveServicesAccountName1
}

resource cognitiveServicesAccount2 'Microsoft.CognitiveServices/accounts@2021-04-30' existing = {
  name: cognitiveServicesAccountName2
}

param resourceGroupName string = resourceGroup().name

// POLICY1/BACKEND: create a backend that wires up "circuit breaker policy" to the Cognitive Services account
resource backend1 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
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
resource backend2 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
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
resource loadBalancing 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
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
