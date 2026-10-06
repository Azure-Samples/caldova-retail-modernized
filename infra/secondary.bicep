targetScope = 'resourceGroup'

// Secondary database VNet (SQL MI subnet only), the single application VNet and internal
// Container Apps environment, every Azure resource the retail app's configuration implies,
// private connectivity, and least-privilege role assignments.

import { roleDefinitionIds } from './modules/shared/roles.bicep'

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@minLength(6)
@maxLength(6)
param suffix string

@description('Secondary database location.')
param location string = 'centralus'

@description('Application location; must support Availability Zones.')
param applicationLocation string = 'centralus'

param codeDeploymentPrincipalId string
param containerRegistryName string
param containerRegistryResourceGroupName string
param privateDnsZoneResourceGroupName string
param privateDnsZoneName string = 'privatelink${environment().suffixes.sqlServerHostname}'
param primaryDatabaseResourceGroupName string
param primaryDatabaseVnetName string
param primaryDatabaseVnetId string

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
}

// ---- Optional additions (defaults keep the documented contract) ----

param sqlDatabaseName string = 'eShop'

@description('Azure SQL FQDN from primary.bicep. Empty derives it from the deterministic server name.')
param primaryDatabaseFqdn string = ''

param secondaryDatabaseAddressPrefix string = '10.1.0.0/20'
param managedInstanceSubnetPrefix string = '10.1.0.0/24'
param applicationAddressPrefix string = '10.20.0.0/20'
param containerAppsSubnetPrefix string = '10.20.0.0/23'
param applicationPrivateEndpointSubnetPrefix string = '10.20.2.0/24'

@description('Microsoft sample image; the workshop application arrives in Lab 06.')
param containerImage string = 'mcr.microsoft.com/dotnet/samples:aspnetapp'

param targetPort int = 8080
param containerCpu string = '0.5'
param containerMemory string = '1Gi'

@minValue(2)
param minReplicas int = 2

@minValue(2)
@maxValue(10)
param maxReplicas int = 5

@minValue(1)
param httpConcurrentRequests int = 50

@description('GET probe path. "/" answers 200 for both the placeholder and the retail app.')
param healthProbePath string = '/'

param dataProtectionApplicationName string = 'eShopLite'

@minValue(30)
param logRetentionInDays int = 30

param logDailyQuotaGb int = 1

param redisSkuName string = 'Balanced_B0'

@allowed([
  'Enabled'
  'Disabled'
])
param redisHighAvailability string = 'Disabled'

@minValue(7)
@maxValue(90)
param keyVaultSoftDeleteRetentionInDays int = 7

var nameToken = take(replace(prefix, '-', ''), 12)
var applicationName = '${nameToken}-application-${suffix}'
var sqlServerFqdn = empty(primaryDatabaseFqdn)
  ? '${toLower('${nameToken}sql${suffix}')}${environment().suffixes.sqlServerHostname}'
  : primaryDatabaseFqdn
var effectiveMaxReplicas = max(minReplicas, maxReplicas)

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: containerRegistryName
  scope: resourceGroup(containerRegistryResourceGroupName)
}

// ---- Networks ----

module databaseNetwork './modules/network/secondary-database-vnet.bicep' = {
  name: 'secondary-database-network'
  params: {
    name: '${prefix}-db-secondary-${suffix}-vnet'
    location: location
    addressPrefix: secondaryDatabaseAddressPrefix
    managedInstanceSubnetPrefix: managedInstanceSubnetPrefix
    networkSecurityGroupName: '${prefix}-sqlmi-${suffix}-nsg'
    routeTableName: '${prefix}-sqlmi-${suffix}-rt'
    tags: tags
  }
}

module applicationNetwork './modules/network/application-vnet.bicep' = {
  name: 'application-network'
  params: {
    name: '${prefix}-app-${suffix}-vnet'
    location: applicationLocation
    addressPrefix: applicationAddressPrefix
    containerAppsSubnetPrefix: containerAppsSubnetPrefix
    privateEndpointSubnetPrefix: applicationPrivateEndpointSubnetPrefix
    tags: tags
  }
}

module applicationToPrimaryDatabasePeering './modules/network/vnet-peering.bicep' = {
  name: 'application-to-primary-database-peering'
  params: {
    localVnetName: applicationNetwork.outputs.name
    remoteVnetId: primaryDatabaseVnetId
    peeringName: 'application-to-primary-database'
  }
}

module primaryDatabaseToApplicationPeering './modules/network/vnet-peering.bicep' = {
  name: 'primary-database-to-application-peering'
  scope: resourceGroup(primaryDatabaseResourceGroupName)
  params: {
    localVnetName: primaryDatabaseVnetName
    remoteVnetId: applicationNetwork.outputs.id
    peeringName: 'primary-database-to-application'
  }
}

module secondaryToPrimaryDatabasePeering './modules/network/vnet-peering.bicep' = {
  name: 'secondary-to-primary-database-peering'
  params: {
    localVnetName: databaseNetwork.outputs.name
    remoteVnetId: primaryDatabaseVnetId
    peeringName: 'secondary-to-primary-database'
  }
}

module primaryToSecondaryDatabasePeering './modules/network/vnet-peering.bicep' = {
  name: 'primary-to-secondary-database-peering'
  scope: resourceGroup(primaryDatabaseResourceGroupName)
  params: {
    localVnetName: primaryDatabaseVnetName
    remoteVnetId: databaseNetwork.outputs.id
    peeringName: 'primary-to-secondary-database'
  }
}

module secondaryDatabaseSqlDnsLink './modules/network/private-dns-zone-link.bicep' = {
  name: 'secondary-database-sql-dns-link'
  scope: resourceGroup(privateDnsZoneResourceGroupName)
  params: {
    privateDnsZoneName: privateDnsZoneName
    virtualNetworkId: databaseNetwork.outputs.id
    linkName: 'secondary-database-link'
    tags: tags
  }
}

module applicationSqlDnsLink './modules/network/private-dns-zone-link.bicep' = {
  name: 'application-sql-dns-link'
  scope: resourceGroup(privateDnsZoneResourceGroupName)
  params: {
    privateDnsZoneName: privateDnsZoneName
    virtualNetworkId: applicationNetwork.outputs.id
    linkName: 'application-link'
    tags: tags
  }
}

// ---- Identity and monitoring ----

module runtimeIdentity './modules/identity/runtime-identity.bicep' = {
  name: 'runtime-identity'
  params: {
    name: '${prefix}-runtime-${suffix}-id'
    location: applicationLocation
    tags: tags
  }
}

module logAnalytics './modules/monitoring/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: '${prefix}-application-${suffix}-log'
    location: applicationLocation
    retentionInDays: logRetentionInDays
    dailyQuotaGb: logDailyQuotaGb
    tags: tags
  }
}

module applicationInsights './modules/monitoring/application-insights.bicep' = {
  name: 'application-insights'
  params: {
    name: '${prefix}-application-${suffix}-appi'
    location: applicationLocation
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    tags: tags
  }
}

// ---- App dependencies, each reachable only through a private endpoint in the application VNet ----

module keyVault './modules/security/key-vault.bicep' = {
  name: 'application-key-vault'
  params: {
    name: '${nameToken}${suffix}-akv'
    location: applicationLocation
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionInDays
    tags: tags
  }
}

module keyVaultDnsZone './modules/network/private-dns-zone.bicep' = {
  name: 'key-vault-private-dns-zone'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    virtualNetworkLinks: [
      {
        name: 'application-link'
        virtualNetworkId: applicationNetwork.outputs.id
      }
    ]
    tags: tags
  }
}

module keyVaultPrivateEndpoint './modules/network/private-endpoint.bicep' = {
  name: 'key-vault-private-endpoint'
  params: {
    name: '${keyVault.outputs.name}-pe'
    location: applicationLocation
    subnetId: applicationNetwork.outputs.privateEndpointSubnetId
    privateLinkServiceId: keyVault.outputs.id
    groupId: 'vault'
    privateDnsZoneId: keyVaultDnsZone.outputs.id
    tags: tags
  }
}

module dataProtectionStorage './modules/storage/data-protection-storage.bicep' = {
  name: 'data-protection-storage'
  params: {
    name: '${nameToken}dp${suffix}'
    location: applicationLocation
    tags: tags
  }
}

module blobDnsZone './modules/network/private-dns-zone.bicep' = {
  name: 'blob-private-dns-zone'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkLinks: [
      {
        name: 'application-link'
        virtualNetworkId: applicationNetwork.outputs.id
      }
    ]
    tags: tags
  }
}

module storagePrivateEndpoint './modules/network/private-endpoint.bicep' = {
  name: 'data-protection-storage-private-endpoint'
  params: {
    name: '${dataProtectionStorage.outputs.name}-blob-pe'
    location: applicationLocation
    subnetId: applicationNetwork.outputs.privateEndpointSubnetId
    privateLinkServiceId: dataProtectionStorage.outputs.id
    groupId: 'blob'
    privateDnsZoneId: blobDnsZone.outputs.id
    tags: tags
  }
}

module redis './modules/cache/redis.bicep' = {
  name: 'session-cache'
  params: {
    name: '${prefix}-${suffix}-redis'
    location: applicationLocation
    skuName: redisSkuName
    highAvailability: redisHighAvailability
    dataAccessPrincipalId: runtimeIdentity.outputs.principalId
    tags: tags
  }
}

module redisDnsZone './modules/network/private-dns-zone.bicep' = {
  name: 'redis-private-dns-zone'
  params: {
    name: 'privatelink.redis.azure.net'
    virtualNetworkLinks: [
      {
        name: 'application-link'
        virtualNetworkId: applicationNetwork.outputs.id
      }
    ]
    tags: tags
  }
}

module redisPrivateEndpoint './modules/network/private-endpoint.bicep' = {
  name: 'session-cache-private-endpoint'
  params: {
    name: '${redis.outputs.name}-pe'
    location: applicationLocation
    subnetId: applicationNetwork.outputs.privateEndpointSubnetId
    privateLinkServiceId: redis.outputs.id
    groupId: 'redisEnterprise'
    privateDnsZoneId: redisDnsZone.outputs.id
    tags: tags
  }
}

// ---- Runtime identity data-plane roles (resource-scoped) ----

module runtimeKeyVaultSecretsUser './modules/rbac/key-vault-role.bicep' = {
  name: 'runtime-key-vault-secrets-user'
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: runtimeIdentity.outputs.principalId
    roleDefinitionId: roleDefinitionIds.keyVaultSecretsUser
  }
}

module runtimeDataProtectionKeyUser './modules/rbac/key-vault-key-role.bicep' = {
  name: 'runtime-data-protection-key-crypto-user'
  params: {
    keyVaultName: keyVault.outputs.name
    keyName: keyVault.outputs.dataProtectionKeyName
    principalId: runtimeIdentity.outputs.principalId
    roleDefinitionId: roleDefinitionIds.keyVaultCryptoServiceEncryptionUser
  }
}

module runtimeDataProtectionBlobContributor './modules/rbac/storage-container-role.bicep' = {
  name: 'runtime-data-protection-blob-contributor'
  params: {
    storageAccountName: dataProtectionStorage.outputs.name
    containerName: dataProtectionStorage.outputs.containerName
    principalId: runtimeIdentity.outputs.principalId
    roleDefinitionId: roleDefinitionIds.storageBlobDataContributor
  }
}

// ---- Container Apps ----

module containerAppsEnvironment './modules/app/managed-environment.bicep' = {
  name: 'container-apps-environment'
  params: {
    name: '${applicationName}-cae'
    location: applicationLocation
    infrastructureSubnetId: applicationNetwork.outputs.containerAppsSubnetId
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
    tags: tags
  }
}

// The retail app's configuration contract (caldova-retail Hosting/AzureIntegration.cs). Every value is
// an endpoint or identifier, never a credential: the app authenticates with the runtime identity.
var appEnvironmentVariables = [
  {
    name: 'ASPNETCORE_ENVIRONMENT'
    value: 'Production'
  }
  {
    name: 'ASPNETCORE_FORWARDEDHEADERS_ENABLED'
    value: 'true'
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: runtimeIdentity.outputs.clientId
  }
  {
    name: 'ConnectionStrings__StoreDbContext'
    value: 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;User Id=${runtimeIdentity.outputs.clientId};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
  {
    name: 'KeyVault__Uri'
    value: keyVault.outputs.uri
  }
  {
    name: 'DataProtection__BlobUri'
    value: dataProtectionStorage.outputs.keyRingBlobUri
  }
  {
    name: 'DataProtection__KeyVaultKeyUri'
    value: keyVault.outputs.dataProtectionKeyUri
  }
  {
    name: 'DataProtection__ApplicationName'
    value: dataProtectionApplicationName
  }
  {
    name: 'Redis__Endpoint'
    value: redis.outputs.endpoint
  }
]

module containerApp './modules/app/container-app.bicep' = {
  name: 'retail-container-app'
  // The first revision of any image must find its data-plane access and private endpoints in place.
  dependsOn: [
    runtimeKeyVaultSecretsUser
    runtimeDataProtectionKeyUser
    runtimeDataProtectionBlobContributor
    keyVaultPrivateEndpoint
    storagePrivateEndpoint
    redisPrivateEndpoint
    applicationSqlDnsLink
    applicationToPrimaryDatabasePeering
    primaryDatabaseToApplicationPeering
  ]
  params: {
    name: '${applicationName}-app'
    location: applicationLocation
    environmentId: containerAppsEnvironment.outputs.id
    registryServer: registry.properties.loginServer
    runtimeIdentityResourceId: runtimeIdentity.outputs.id
    image: containerImage
    targetPort: targetPort
    cpu: containerCpu
    memory: containerMemory
    minReplicas: minReplicas
    maxReplicas: effectiveMaxReplicas
    httpConcurrentRequests: httpConcurrentRequests
    healthProbePath: healthProbePath
    environmentVariables: appEnvironmentVariables
    applicationInsightsName: applicationInsights.outputs.name
    tags: tags
  }
}

module applicationRegistryPull './modules/rbac/acr-role.bicep' = {
  name: 'application-acr-pull'
  scope: resourceGroup(containerRegistryResourceGroupName)
  params: {
    containerRegistryName: containerRegistryName
    principalId: containerApp.outputs.systemPrincipalId
    roleDefinitionId: roleDefinitionIds.acrPull
  }
}

module codeDeploymentAppContributor './modules/rbac/container-app-role.bicep' = {
  name: 'code-deployment-container-app-contributor'
  params: {
    containerAppName: containerApp.outputs.name
    principalId: codeDeploymentPrincipalId
    roleDefinitionId: roleDefinitionIds.containerAppsContributor
  }
}

output containerAppName string = containerApp.outputs.name
output containerAppFqdn string = containerApp.outputs.fqdn
output containerAppsEnvironmentId string = containerAppsEnvironment.outputs.id
output containerAppsEnvironmentName string = containerAppsEnvironment.outputs.name
output applicationVnetId string = applicationNetwork.outputs.id
output applicationVnetName string = applicationNetwork.outputs.name
output databaseVnetId string = databaseNetwork.outputs.id
output databaseVnetName string = databaseNetwork.outputs.name
output managedInstanceSubnetId string = databaseNetwork.outputs.managedInstanceSubnetId

// Additional outputs (not part of the documented contract). None is a credential.
output runtimeIdentityResourceId string = runtimeIdentity.outputs.id
output runtimeIdentityClientId string = runtimeIdentity.outputs.clientId
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
output dataProtectionStorageAccountName string = dataProtectionStorage.outputs.name
output redisHostName string = redis.outputs.hostName
output applicationInsightsName string = applicationInsights.outputs.name
output retailDatabaseName string = sqlDatabaseName
