param name string
param location string
param storageName string
param deploymentContainer string
param identityId string
param identityClientId string
param insightsConnection string
param busNamespace string
param queueName string
param maximumInstances int
param extraSettings object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${name}-plan'
  location: location
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

var settings = union({
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: identityClientId
  AzureWebJobsStorage__blobServiceUri: storage.properties.primaryEndpoints.blob
  AzureWebJobsStorage__queueServiceUri: storage.properties.primaryEndpoints.queue
  AzureWebJobsStorage__tableServiceUri: storage.properties.primaryEndpoints.table
  ServiceBusConnection__fullyQualifiedNamespace: busNamespace
  ServiceBusConnection__credential: 'managedidentity'
  ServiceBusConnection__clientId: identityClientId
  SHIPMENT_QUEUE: queueName
  DATA_STORAGE_BLOB_URL: storage.properties.primaryEndpoints.blob
  AZURE_CLIENT_ID: identityClientId
  APPLICATIONINSIGHTS_CONNECTION_STRING: insightsConnection
  APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${identityClientId};Authorization=AAD'
  OTEL_TRACES_SAMPLER: 'always_on'
  PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY: 'true'
}, extraSettings)

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  tags: { 'azd-service-name': 'recovery' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainer}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityId
          }
        }
      }
      runtime: { name: 'python', version: '3.13' }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: maximumInstances
        triggers: {
          http: { perInstanceConcurrency: 4 }
        }
        alwaysReady: [
          { name: 'http', instanceCount: 1 }
          { name: 'function:shipment_repair', instanceCount: 1 }
        ]
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
  }
}

resource appSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: app
  name: 'appsettings'
  properties: settings
}

output name string = app.name
output id string = app.id
