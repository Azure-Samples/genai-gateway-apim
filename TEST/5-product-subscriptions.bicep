// Deploys the following resources:
// - 1 product
// - 1 product + API association
// - 1 user
// - 1 subscription

param serviceName string = 'servicewiu65klfbzao6-APIM3'
param apiName string = 'myAPI'
param productName string = 'APIM-AI_APIS'
param productDescription string = 'A product with AI APIs'

resource apimService 'Microsoft.ApiManagement/service@2020-06-01-preview' existing = {
  name: serviceName
}

resource api1 'Microsoft.ApiManagement/service/apis@2020-06-01-preview' existing = { 
  parent: apimService
  name: apiName
}

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

// PRODUCT-API associate the API with the product

resource productApi1 'Microsoft.ApiManagement/service/products/apis@2020-06-01-preview' = {
  parent: product
  name: api1.name
}


// What aout these?

// USER creating a user
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

// SUBSCRIPTION creating a subscription, ID

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


