targetScope = 'resourceGroup'

// Primary database region: private VMs behind Bastion, private Entra-only Azure SQL, the migration
// service, the container registry, and the Lab 06 build identity's registry-scoped AcrPush.

import { roleDefinitionIds } from './modules/shared/roles.bicep'

@description('Lowercase lab prefix used in resource names.')
@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@description('Six-character suffix produced by the bootstrap script.')
@minLength(6)
@maxLength(6)
param suffix string

param location string = 'northcentralus'

@description('Lab 06 code-deployment identity. Also receives AcrPush unless codeBuildPrincipalId is set.')
param codeDeploymentPrincipalId string

param sqlEntraAdminObjectId string
param sqlEntraAdminLogin string

@allowed([
  'User'
  'Group'
  'Application'
])
param sqlEntraAdminPrincipalType string = 'User'

@secure()
param vmAdminUsername string

@secure()
param vmAdminPassword string

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
}

// ---- Optional additions (defaults keep the documented contract) ----

@description('Separate Lab 06 build identity for AcrPush. Empty uses codeDeploymentPrincipalId.')
param codeBuildPrincipalId string = ''

param databaseAddressPrefix string = '10.0.0.0/20'
param bastionSubnetPrefix string = '10.0.1.0/26'
param vmSubnetPrefix string = '10.0.2.0/24'
param privateEndpointSubnetPrefix string = '10.0.3.0/24'

param windowsVmSize string = 'Standard_D2s_v5'
param linuxVmSize string = 'Standard_B2s'

param sqlDatabaseName string = 'eShop'
param sqlDatabaseSkuName string = 'S0'
param sqlDatabaseSkuTier string = 'Standard'

@allowed([
  'Local'
  'Zone'
  'Geo'
  'GeoZone'
])
param sqlBackupStorageRedundancy string = 'Local'

@description('Create the Azure Database Migration Service that the source VM integration runtime registers with.')
param deployMigrationService bool = true

var nameToken = take(replace(prefix, '-', ''), 12)
var registryName = toLower('${nameToken}cr${suffix}')
var sqlServerName = toLower('${nameToken}sql${suffix}')
var sqlPrivateDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'
var buildPrincipalId = empty(codeBuildPrincipalId) ? codeDeploymentPrincipalId : codeBuildPrincipalId

module network './modules/network/primary-database-vnet.bicep' = {
  name: 'primary-database-network'
  params: {
    name: '${prefix}-db-primary-${suffix}-vnet'
    location: location
    addressPrefix: databaseAddressPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    vmSubnetPrefix: vmSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    vmNetworkSecurityGroupName: '${prefix}-vm-${suffix}-nsg'
    tags: tags
  }
}

module bastion './modules/compute/bastion.bicep' = {
  name: 'bastion'
  params: {
    name: '${prefix}-${suffix}-bas'
    location: location
    subnetId: network.outputs.bastionSubnetId
    tags: tags
  }
}

module machines './modules/compute/virtual-machines.bicep' = {
  name: 'private-virtual-machines'
  params: {
    prefix: prefix
    suffix: suffix
    location: location
    subnetId: network.outputs.vmSubnetId
    windowsVmSize: windowsVmSize
    linuxVmSize: linuxVmSize
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    tags: tags
  }
}

module sql './modules/data/sql-database.bicep' = {
  name: 'sql-database'
  params: {
    serverName: sqlServerName
    location: location
    databaseName: sqlDatabaseName
    skuName: sqlDatabaseSkuName
    skuTier: sqlDatabaseSkuTier
    backupStorageRedundancy: sqlBackupStorageRedundancy
    entraAdminObjectId: sqlEntraAdminObjectId
    entraAdminLogin: sqlEntraAdminLogin
    entraAdminPrincipalType: sqlEntraAdminPrincipalType
    tags: tags
  }
}

// Owned here; secondary.bicep links the secondary database and application VNets to it.
module sqlDnsZone './modules/network/private-dns-zone.bicep' = {
  name: 'sql-private-dns-zone'
  params: {
    name: sqlPrivateDnsZoneName
    virtualNetworkLinks: [
      {
        name: 'primary-database-link'
        virtualNetworkId: network.outputs.id
      }
    ]
    tags: tags
  }
}

module sqlPrivateEndpoint './modules/network/private-endpoint.bicep' = {
  name: 'sql-private-endpoint'
  params: {
    name: '${sqlServerName}-pe'
    location: location
    subnetId: network.outputs.privateEndpointSubnetId
    privateLinkServiceId: sql.outputs.serverId
    groupId: 'sqlServer'
    privateDnsZoneId: sqlDnsZone.outputs.id
    tags: tags
  }
}

module migration './modules/data/migration-service.bicep' = if (deployMigrationService) {
  name: 'database-migration-service'
  params: {
    name: '${prefix}-${suffix}-dms'
    location: location
    tags: tags
  }
}

module registry './modules/registry/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    name: registryName
    location: location
    tags: tags
  }
}

module codeBuildRegistryPush './modules/rbac/acr-role.bicep' = {
  name: 'code-build-acr-push'
  params: {
    containerRegistryName: registry.outputs.name
    principalId: buildPrincipalId
    roleDefinitionId: roleDefinitionIds.acrPush
  }
}

output containerRegistryName string = registry.outputs.name
output containerRegistryLoginServer string = registry.outputs.loginServer
output privateDnsZoneName string = sqlDnsZone.outputs.name
output sqlServerName string = sql.outputs.serverName
output sqlServerFqdn string = sql.outputs.serverFqdn
output sqlDatabaseName string = sql.outputs.databaseName
output databaseVnetId string = network.outputs.id
output databaseVnetName string = network.outputs.name
output virtualMachineNames array = machines.outputs.virtualMachineNames
output virtualMachineIds array = machines.outputs.virtualMachineIds
output virtualMachinePrincipalIds array = machines.outputs.virtualMachinePrincipalIds

// Additional outputs (not part of the documented contract).
output migrationServiceName string = deployMigrationService ? migration!.outputs.name : ''
