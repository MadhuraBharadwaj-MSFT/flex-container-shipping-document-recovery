param name string
param location string
param modelName string
param modelVersion string
param modelFormat string
param modelCapacity int
param functionPrincipalId string
param developerPrincipalId string

resource account 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: name
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: account
  name: 'shipping-recovery'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Shipping document recovery'
    description: 'Hosted Skill that repairs shipping-record formatting.'
  }
  dependsOn: [
    model
  ]
}

resource model 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: modelName
  sku: { name: 'GlobalStandard', capacity: modelCapacity }
  properties: {
    model: { format: modelFormat, name: modelName, version: modelVersion }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

var foundryUserRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)

resource functionModelAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, functionPrincipalId, foundryUserRole)
  scope: account
  properties: {
    roleDefinitionId: foundryUserRole
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource developerModelAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(account.id, developerPrincipalId, foundryUserRole)
  scope: account
  properties: {
    roleDefinitionId: foundryUserRole
    principalId: developerPrincipalId
    principalType: 'User'
  }
}

output projectEndpoint string = '${account.properties.endpoints['AI Foundry API']}api/projects/${project.name}'
output modelDeploymentName string = model.name
