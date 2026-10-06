// Entra-only Azure SQL logical server and the retail database. Public network access is disabled;
// the private endpoint and DNS zone are composed by the entry point.

param serverName string
param location string
param databaseName string

@description('Database SKU name, e.g. S0 (DTU) or GP_S_Gen5_1 (serverless).')
param skuName string

param skuTier string

@allowed([
  'Local'
  'Zone'
  'Geo'
  'GeoZone'
])
param backupStorageRedundancy string

param entraAdminObjectId string
param entraAdminLogin string

@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdminPrincipalType string

param tags object = {}

resource server 'Microsoft.Sql/servers@2023-08-01' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdminLogin
      principalType: entraAdminPrincipalType
      sid: entraAdminObjectId
      tenantId: subscription().tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: server
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    requestedBackupStorageRedundancy: backupStorageRedundancy
    zoneRedundant: false
  }
}

output serverId string = server.id
output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
