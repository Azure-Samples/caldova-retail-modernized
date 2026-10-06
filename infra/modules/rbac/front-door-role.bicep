// Role assignment scoped to the Front Door profile (Reader for the Lab 06 deploy identity's smoke test).

param profileName string
param principalId string

@description('Built-in role definition GUID.')
param roleDefinitionId string

@allowed([
  'ServicePrincipal'
  'Group'
  'User'
])
param principalType string = 'ServicePrincipal'

resource profile 'Microsoft.Cdn/profiles@2025-06-01' existing = {
  name: profileName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(profile.id, principalId, roleDefinitionId)
  scope: profile
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}
