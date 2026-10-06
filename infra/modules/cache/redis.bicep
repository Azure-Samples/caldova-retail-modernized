// Azure Managed Redis for the ASP.NET Core session cache (the cart), so carts survive restarts and
// are shared by replicas. Microsoft Entra ID auth only. App setting contract: Redis__Endpoint.

param name string
param location string

@description('Azure Managed Redis SKU. Balanced_B0 is the smallest tier.')
param skuName string = 'Balanced_B0'

@description('Cart data is ephemeral, so the lab default trades replication for cost.')
@allowed([
  'Enabled'
  'Disabled'
])
param highAvailability string = 'Disabled'

@description('Object ID granted the built-in "default" data access policy.')
param dataAccessPrincipalId string

param tags object = {}

resource cluster 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    minimumTlsVersion: '1.2'
    highAvailability: highAvailability
    publicNetworkAccess: 'Disabled'
  }
}

resource database 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  parent: cluster
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    port: 10000
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'VolatileLRU'
    accessKeysAuthentication: 'Disabled'
  }
}

resource accessPolicyAssignment 'Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-07-01' = {
  parent: database
  name: 'runtime${uniqueString(dataAccessPrincipalId)}'
  properties: {
    accessPolicyName: 'default'
    user: {
      objectId: dataAccessPrincipalId
    }
  }
}

output id string = cluster.id
output name string = cluster.name
output hostName string = cluster.properties.hostName
output endpoint string = '${cluster.properties.hostName}:${database.properties.port}'
