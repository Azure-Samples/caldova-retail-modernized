// Storage for the ASP.NET Core Data Protection key ring, shared by every replica and revision.
// App setting contract: DataProtection__BlobUri. Entra ID only: shared keys and public access are off.

@minLength(3)
@maxLength(24)
param name string

param location string
param containerName string = 'dataprotection'
param keyRingBlobName string = 'keys.xml'

@minValue(1)
@maxValue(365)
param deleteRetentionInDays int = 7

param tags object = {}

resource account 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Soft delete protects the key ring: losing it signs every user out.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: account
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: deleteRetentionInDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: deleteRetentionInDays
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

output id string = account.id
output name string = account.name
output containerName string = container.name
output keyRingBlobUri string = '${account.properties.primaryEndpoints.blob}${containerName}/${keyRingBlobName}'
