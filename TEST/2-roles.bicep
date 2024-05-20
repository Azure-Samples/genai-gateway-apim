// Deploys the following:
// - An API Management service
// - An Azure Cognitive Services account

resource apimService 'Microsoft.ApiManagement/service@2020-06-01-preview' existing = {
  name: 'servicewiu65klfbzao6-APIM3'
}

resource cognitiveServicesAccount1 'Microsoft.CognitiveServices/accounts@2021-04-30' existing = {
  name: 'wiu65klfbzao6-AOAI1'
}

resource cognitiveServicesAccount2 'Microsoft.CognitiveServices/accounts@2021-04-30' existing = {
  name: 'wiu65klfbzao6-AOAI2'
}

// adding Managed Identity connection between APIM and Azure Open AI by adding a role assignment

// TODO Cognitive Services API Management Contributor role ID 
param roleDefinitionId string = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(apimService.id, roleDefinitionId)
  scope: cognitiveServicesAccount1
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
    principalId: apimService.identity.principalId
  }
}

resource roleAssignment2 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(apimService.id, roleDefinitionId)
  scope: cognitiveServicesAccount2
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
    principalId: apimService.identity.principalId
  }
}


