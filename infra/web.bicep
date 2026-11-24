param name string
param location string = 'eastus2'
param functionAppId string
param functionAppName string
param functionAppLocation string

resource web 'Microsoft.Web/staticSites@2024-04-01' = {
  name: name
  location: location
  tags: { 'azd-service-name': 'web' }
  sku: { name: 'Standard', tier: 'Standard' }
  properties: {
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Disabled'
  }
}

resource backend 'Microsoft.Web/staticSites/linkedBackends@2024-04-01' = {
  parent: web
  name: functionAppName
  properties: {
    backendResourceId: functionAppId
    region: functionAppLocation
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' existing = {
  name: functionAppName
}

resource auth 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: app
  name: 'authsettingsV2'
  properties: {
    platform: { enabled: true, runtimeVersion: '~1' }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureStaticWebApps: {
        enabled: true
        registration: { clientId: web.properties.defaultHostname }
      }
    }
    httpSettings: { requireHttps: true }
  }
  dependsOn: [backend]
}

output name string = web.name
output url string = 'https://${web.properties.defaultHostname}'
