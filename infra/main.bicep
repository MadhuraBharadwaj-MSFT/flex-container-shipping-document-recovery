targetScope = 'subscription'

@minLength(1)
@maxLength(24)
param environmentName string
param location string = 'eastus2'
param functionLocation string = 'eastus2euap'
param connectorLocation string = 'westcentralus'
param foundryModel string = 'gpt-5.4'
param foundryModelVersion string = '2026-03-05'
@minValue(1)
param foundryModelCapacity int = 100
param developerPrincipalId string = ''
@description('Owner userId from this Static Web App /.auth/me. Empty denies all demo API access.')
param demoOwnerId string = ''

var suffix = take(toLower(uniqueString(subscription().id, environmentName, location)), 6)

resource group 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}-${suffix}'
  location: location
  tags: { 'azd-env-name': environmentName }
}

module resources './resources.bicep' = {
  name: 'shipping-document-resources'
  scope: group
  params: {
    location: location
    functionLocation: functionLocation
    connectorLocation: connectorLocation
    foundryModel: foundryModel
    foundryModelVersion: foundryModelVersion
    foundryModelCapacity: foundryModelCapacity
    developerPrincipalId: empty(developerPrincipalId)
      ? deployer().objectId
      : developerPrincipalId
    demoOwnerId: demoOwnerId
  }
}

output AZURE_RESOURCE_GROUP string = group.name
output AZURE_LOCATION string = location
output AZURE_FUNCTION_LOCATION string = functionLocation
output SERVICE_RECOVERY_NAME string = resources.outputs.recoveryFunctionAppName
output SERVICE_WEB_NAME string = resources.outputs.staticWebAppName
output DEMO_URL string = resources.outputs.demoUrl
output AZURE_STORAGE_ACCOUNT_NAME string = resources.outputs.storageAccount
output AZURE_SERVICE_BUS_NAMESPACE string = resources.outputs.serviceBusNamespace
output AZURE_SHIPMENT_QUEUE string = resources.outputs.queueName
output SCHEMA_MCP_SERVER_URL string = resources.outputs.schemaMcpEndpoint
output QUEUE_MCP_SERVER_URL string = resources.outputs.queueMcpEndpoint
output FOUNDRY_PROJECT_ENDPOINT string = resources.outputs.foundryProjectEndpoint
output FOUNDRY_MODEL string = resources.outputs.foundryModelDeployment
output AZURE_CONTAINER_REGISTRY_NAME string = resources.outputs.containerRegistryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.containerRegistryEndpoint
output AZURE_IMAGE_REPOSITORY string = resources.outputs.imageRepository
output AZURE_ACR_TOKEN_NAME string = resources.outputs.tokenName
output AZURE_DOCUMENT_FUNCTION_NAME string = resources.outputs.documentFunctionAppName
output AZURE_DOCUMENT_PLAN_ID string = resources.outputs.documentPlanId
output AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING string = resources.outputs.applicationInsightsConnectionString
output AZURE_USER_ASSIGNED_IDENTITY_ID string = resources.outputs.identityId
output AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID string = resources.outputs.identityClientId
output AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID string = resources.outputs.identityPrincipalId
