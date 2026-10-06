// Role assignment scoped to a single Container App (Container Apps Contributor for the Lab 06 deploy identity).

param containerAppName string
param principalId string

@description('Built-in role definition GUID.')
param roleDefinitionId string

@allowed([
  'ServicePrincipal'
  'Group'
  'User'
])
param principalType string = 'ServicePrincipal'

resource app 'Microsoft.App/containerApps@2025-07-01' existing = {
  name: containerAppName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, principalId, roleDefinitionId)
  scope: app
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}
