// Application Key Vault, separate from the bootstrap vault that holds VM credentials, so the
// runtime identity can never read them. Holds the Data Protection key-wrapping key.
// App setting contract: KeyVault__Uri, DataProtection__KeyVaultKeyUri.

param name string
param location string

@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 7

param dataProtectionKeyName string = 'dataprotection'
param tags object = {}

resource vault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Created through the control plane, so no key material passes through the template.
resource dataProtectionKey 'Microsoft.KeyVault/vaults/keys@2025-05-01' = {
  parent: vault
  name: dataProtectionKeyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
    attributes: {
      enabled: true
    }
  }
}

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
output dataProtectionKeyName string = dataProtectionKey.name
@description('Versionless key URI, so key rotation needs no app configuration change.')
output dataProtectionKeyUri string = dataProtectionKey.properties.keyUri
