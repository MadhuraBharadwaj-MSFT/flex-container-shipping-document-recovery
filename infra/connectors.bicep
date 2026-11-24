param name string
param location string
param functionPrincipalId string
param developerPrincipalId string = ''
param storageAccountName string
param serviceBusNamespace string
param queueName string

resource connectorNamespace 'Microsoft.Web/connectorGateways@2026-05-01-preview' = {
  name: name
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

resource blobConnection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: connectorNamespace
  name: 'schema-reader'
  properties: {
    connectorName: 'azureblob'
    displayName: 'Read shipping schema'
    parameterValueSet: { name: 'managedIdentityAuth', values: {} }
  }
}

resource busConnection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: connectorNamespace
  name: 'shipment-sender'
  properties: {
    connectorName: 'servicebus'
    displayName: 'Requeue repaired shipments'
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: {
        namespaceEndpoint: {
          value: 'sb://${serviceBusNamespace}.servicebus.windows.net/'
        }
      }
    }
  }
}

var callers = concat(
  [
    connectorNamespace.identity.principalId
    functionPrincipalId
  ],
  empty(developerPrincipalId) ? [] : [developerPrincipalId]
)

resource blobAccess 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = [for i in range(0, empty(developerPrincipalId) ? 2 : 3): {
  parent: blobConnection
  name: 'caller-${i}'
  location: location
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: callers[i]
        tenantId: tenant().tenantId
      }
    }
  }
}]

resource busAccess 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = [for i in range(0, empty(developerPrincipalId) ? 2 : 3): {
  parent: busConnection
  name: 'caller-${i}'
  location: location
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: callers[i]
        tenantId: tenant().tenantId
      }
    }
  }
}]

resource schemaServer 'Microsoft.Web/connectorGateways/mcpServerConfigs@2026-05-01-preview' = {
  parent: connectorNamespace
  name: 'shipment-schema'
  properties: {
    description: 'Read the compact shipping repair contract from Blob Storage.'
    state: 'Enabled'
    disableApiKeyAuth: true
    settings: { textOnlyContent: true }
    policies: []
    connectors: [
      {
        connectionName: blobConnection.name
        name: 'azureblob'
        displayName: 'Shipping repair contract'
        description: 'Read the allowlisted shipping-record repair contract.'
        operations: [
          {
            name: 'GetFileContentByPath_V2'
            displayName: 'Read repair contract'
            description: 'Read the compact JSON repair contract.'
            userParameters: [
              { name: 'dataset', value: storageAccountName }
              { name: 'path', value: '/schemas/repair-contract.json' }
            ]
            agentParameters: []
          }
        ]
      }
    ]
  }
  dependsOn: [blobAccess]
}

resource queueServer 'Microsoft.Web/connectorGateways/mcpServerConfigs@2026-05-01-preview' = {
  parent: connectorNamespace
  name: 'shipment-requeue'
  properties: {
    description: 'Return a repaired shipment to the primary Service Bus queue.'
    state: 'Enabled'
    disableApiKeyAuth: true
    settings: { textOnlyContent: true }
    policies: []
    connectors: [
      {
        connectionName: busConnection.name
        name: 'servicebus'
        displayName: 'Requeue shipment'
        description: 'Send one repaired shipment to the primary queue.'
        operations: [
          {
            name: 'SendMessage'
            displayName: 'Requeue repaired shipment'
            description: 'Send compact JSON as literal ContentData, not base64.'
            userParameters: [
              { name: 'entityName', value: queueName }
            ]
            agentParameters: [
              {
                name: 'message'
                schema: {
                  type: 'object'
                  required: true
                  properties: {
                    ContentData: {
                      type: 'string'
                      description: 'Compact shipment JSON as plain text.'
                    }
                    ContentType: {
                      type: 'string'
                      enum: ['application/json']
                    }
                    MessageId: { type: 'string' }
                    CorrelationId: { type: 'string' }
                    Properties: { type: 'object' }
                  }
                }
              }
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [busAccess]
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}
resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storage
  name: 'default'
}
resource schemas 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: blobs
  name: 'schemas'
}
resource schemaReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(schemas.id, connectorNamespace.id, 'read')
  scope: schemas
  properties: {
    principalId: connectorNamespace.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    )
  }
}

resource bus 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: serviceBusNamespace
}
resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' existing = {
  parent: bus
  name: queueName
}
resource sender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(queue.id, connectorNamespace.id, 'send')
  scope: queue
  properties: {
    principalId: connectorNamespace.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
    )
  }
}

output schemaEndpoint string = schemaServer.properties.mcpEndpointUrl
output queueEndpoint string = queueServer.properties.mcpEndpointUrl
