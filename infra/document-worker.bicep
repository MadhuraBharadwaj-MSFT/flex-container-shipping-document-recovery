targetScope = 'resourceGroup'

param environmentName string
param functionAppName string
param functionLocation string
param appServicePlanId string
param applicationInsightsConnectionString string
param storageAccountName string
param serviceBusNamespace string
param queueName string
param userAssignedIdentityId string
param userAssignedIdentityClientId string
param registryImage string
param registryUsername string
@secure()
param registryPassword string

resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
}

resource functionApp 'Microsoft.Web/sites@2026-08-01' = {
  name: functionAppName
  location: functionLocation
  tags: {
    'azd-env-name': environmentName
  }
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'Registry'
          value: registryImage
          authentication: {
            type: 'Basic'
            usernameSettingName: 'FLEX_CONTAINER_REGISTRY_USERNAME'
            passwordSettingName: 'FLEX_CONTAINER_REGISTRY_PASSWORD'
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 20
      }
      siteUpdateStrategy: {
        type: 'Recreate'
      }
    }
    siteConfig: {
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.2'
      remoteDebuggingEnabled: false
      scmMinTlsVersion: '1.2'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
          value: 'ClientId=${userAssignedIdentityClientId};Authorization=AAD'
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storage.properties.primaryEndpoints.blob
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storage.properties.primaryEndpoints.queue
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storage.properties.primaryEndpoints.table
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: userAssignedIdentityClientId
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: serviceBusNamespace
        }
        {
          name: 'ServiceBusConnection__clientId'
          value: userAssignedIdentityClientId
        }
        {
          name: 'ServiceBusConnection__credential'
          value: 'managedidentity'
        }
        {
          name: 'SHIPMENT_QUEUE'
          value: queueName
        }
        {
          name: 'DATA_STORAGE_BLOB_URL'
          value: storage.properties.primaryEndpoints.blob
        }
        {
          name: 'DOCUMENT_CONTAINER'
          value: 'generated-documents'
        }
        {
          name: 'DEMO_RUNS_CONTAINER'
          value: 'demo-runs'
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
        {
          name: 'FLEX_CONTAINER_REGISTRY_PASSWORD'
          value: registryPassword
        }
        {
          name: 'FLEX_CONTAINER_REGISTRY_USERNAME'
          value: registryUsername
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
      ]
    }
  }
}

resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-03-01' = {
  parent: functionApp
  name: 'scm'
  properties: { allow: false }
}

resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2022-03-01' = {
  parent: functionApp
  name: 'ftp'
  properties: { allow: false }
}

output functionAppName string = functionApp.name
