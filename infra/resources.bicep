targetScope = 'resourceGroup'

param location string = resourceGroup().location
param functionLocation string
param connectorLocation string
param experienceLocation string
param foundryModel string
param foundryModelVersion string
param foundryModelFormat string
param foundryModelCapacity int
param developerPrincipalId string
param demoOwnerId string

var suffix = uniqueString(resourceGroup().id)
var prefix = 'shipdoc'
var queueName = 'shipment-submissions'
var imageRepository = 'shipping-document-worker'
var roles = {
  blobOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  queueContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  serviceBusReceiver: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
  serviceBusSender: '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
  blobContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  metricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${prefix}${suffix}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for name in [
  'deploy-skill'
  'generated-documents'
  'schemas'
  'demo-runs'
]: {
  parent: blobs
  name: name
  properties: { publicAccess: 'None' }
}]

resource bus 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: '${prefix}-${suffix}'
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: bus
  name: queueName
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 1
    defaultMessageTimeToLive: 'P1D'
    deadLetteringOnMessageExpiration: true
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'P1D'
    enablePartitioning: true
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-logs-${suffix}'
  location: experienceLocation
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-insights-${suffix}'
  location: experienceLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    SamplingPercentage: 100
    DisableLocalAuth: true
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-app-${suffix}'
  location: location
}

resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, identity.id, roles.blobOwner)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobOwner)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource queueStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, identity.id, roles.queueContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.queueContributor)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource receiveRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(queue.id, identity.id, roles.serviceBusReceiver)
  scope: queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusReceiver)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource senderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(queue.id, identity.id, roles.serviceBusSender)
  scope: queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusSender)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource metricsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(insights.id, identity.id, roles.metricsPublisher)
  scope: insights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.metricsPublisher)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource developerStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(storage.id, developerPrincipalId, roles.blobContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobContributor)
    principalId: developerPrincipalId
    principalType: 'User'
  }
}

resource developerQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(queue.id, developerPrincipalId, roles.serviceBusSender)
  scope: queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusSender)
    principalId: developerPrincipalId
    principalType: 'User'
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: 'acr${prefix}${suffix}'
  location: location
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource scopeMap 'Microsoft.ContainerRegistry/registries/scopeMaps@2025-04-01' = {
  parent: registry
  name: 'pull-${take(suffix, 10)}-ro'
  properties: {
    actions: [
      'repositories/${imageRepository}/content/read'
      'repositories/${imageRepository}/metadata/read'
    ]
    description: 'Read-only access to the shipping document worker image.'
  }
}

resource pullToken 'Microsoft.ContainerRegistry/registries/tokens@2025-04-01' = {
  parent: registry
  name: 'pull-${take(suffix, 10)}'
  properties: {
    scopeMapId: scopeMap.id
    status: 'enabled'
  }
}

resource documentPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${prefix}-document-plan-${suffix}'
  location: functionLocation
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

module foundry './foundry.bicep' = {
  name: 'foundry'
  params: {
    name: '${prefix}-ai-${suffix}'
    location: location
    modelName: foundryModel
    modelVersion: foundryModelVersion
    modelFormat: foundryModelFormat
    modelCapacity: foundryModelCapacity
    functionPrincipalId: identity.properties.principalId
    developerPrincipalId: developerPrincipalId
  }
}

module connectors './connectors.bicep' = {
  name: 'connectors'
  params: {
    name: '${prefix}-connectors-${suffix}'
    location: connectorLocation
    functionPrincipalId: identity.properties.principalId
    developerPrincipalId: developerPrincipalId
    storageAccountName: storage.name
    serviceBusNamespace: bus.name
    queueName: queue.name
  }
  dependsOn: [containers]
}

module recoveryApp './function-app.bicep' = {
  name: 'recovery-app'
  params: {
    name: '${prefix}-recovery-${suffix}'
    location: location
    storageName: storage.name
    deploymentContainer: 'deploy-skill'
    identityId: identity.id
    identityClientId: identity.properties.clientId
    insightsConnection: insights.properties.ConnectionString
    busNamespace: '${bus.name}.servicebus.windows.net'
    queueName: queue.name
    maximumInstances: 20
    extraSettings: {
      AZURE_FUNCTIONS_AGENTS_PROVIDER: 'foundry'
      FOUNDRY_PROJECT_ENDPOINT: foundry.outputs.projectEndpoint
      FOUNDRY_MODEL: foundry.outputs.modelDeploymentName
      SCHEMA_MCP_SERVER_URL: connectors.outputs.schemaEndpoint
      QUEUE_MCP_SERVER_URL: connectors.outputs.queueEndpoint
      SHIPMENT_MCP_CLIENT_ID: identity.properties.clientId
      DEMO_OWNER_ID: demoOwnerId
      'AzureWebJobs.shipment_repair.Disabled': 'false'
    }
  }
  dependsOn: [
    blobRole
    queueStorageRole
    receiveRole
    senderRole
    metricsRole
    containers
  ]
}

module web './web.bicep' = {
  name: 'demo-web'
  params: {
    name: '${prefix}-web-${suffix}'
    location: experienceLocation
    functionAppId: recoveryApp.outputs.id
    functionAppName: recoveryApp.outputs.name
    functionAppLocation: location
  }
}

output staticWebAppName string = web.outputs.name
output demoUrl string = web.outputs.url
output recoveryFunctionAppName string = recoveryApp.outputs.name
output documentFunctionAppName string = '${prefix}-document-${suffix}'
output documentPlanId string = documentPlan.id
output storageAccount string = storage.name
output serviceBusNamespace string = bus.name
output queueName string = queue.name
output schemaMcpEndpoint string = connectors.outputs.schemaEndpoint
output queueMcpEndpoint string = connectors.outputs.queueEndpoint
output foundryProjectEndpoint string = foundry.outputs.projectEndpoint
output foundryModelDeployment string = foundry.outputs.modelDeploymentName
output containerRegistryName string = registry.name
output containerRegistryEndpoint string = registry.properties.loginServer
output imageRepository string = imageRepository
output tokenName string = pullToken.name
output applicationInsightsConnectionString string = insights.properties.ConnectionString
output identityId string = identity.id
output identityClientId string = identity.properties.clientId
output identityPrincipalId string = identity.properties.principalId
