// Applies the service-level (all-APIs) global policy to the shared APIM.
// Kept as its own module so the reusable core/gateway/apim.bicep stays generic.
// Single source of truth for the policy XML is infra/app/apim-global-policy.xml.
param apimServiceName string

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimServiceName
}

resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-09-01-preview' = {
  parent: apimService
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../infra/app/apim-global-policy.xml')
  }
}
