// Role assignment scoped to a single Key Vault key (wrap/unwrap of the Data Protection key ring only).

param keyVaultName string
param keyName string
param principalId string

@description('Built-in role definition GUID.')
param roleDefinitionId string

@allowed([
  'ServicePrincipal'
  'Group'
  'User'
])
param principalType string = 'ServicePrincipal'

resource vault 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: keyVaultName
}

resource key 'Microsoft.KeyVault/vaults/keys@2025-05-01' existing = {
  parent: vault
  name: keyName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(key.id, principalId, roleDefinitionId)
  scope: key
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}
