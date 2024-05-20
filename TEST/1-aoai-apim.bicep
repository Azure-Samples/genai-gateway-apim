
// Deploys the following:
// - 2 Azure Cognitive Services accounts for OpenAI
// - 2 deployments for the OpenAI model
// - 1 API Management service
// - 2 role assignments for the API Management service to access the Cognitive Services accounts


// parameters
param publisherName string = 'myPublisherName'
param publisherEmail string = 'myPublisherEmail@example.com'

var serviceName = 'service${uniqueString(resourceGroup().id)}-APIM3'

param openai_first_endpoint_name string = '${uniqueString(resourceGroup().id)}-AOAI1'

param openai_second_endpoint_name string = '${uniqueString(resourceGroup().id)}-AOAI2'

// model version: 0613
param location string = 'eastus2' // resourceGroup().location

// START, AI creating resources

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


// creating 2 deployments for the OpenAI model

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

// creating a resource for the RAI policy and assigning it to the Cognitive Services account

// create API Management service

resource apimService 'Microsoft.ApiManagement/service@2020-06-01-preview' = {
  name: serviceName
  location: 'westcentralus'
  sku: {
    name: 'Standard' // TODO, SKU2?
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
