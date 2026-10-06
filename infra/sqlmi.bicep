targetScope = 'resourceGroup'

// Optional, separate deployment: an Entra-only SQL Managed Instance in the delegated subnet that
// secondary.bicep creates. Never chained from the base deployment; run only through
// .github/workflows/lab04-deploy-sqlmi.yml (6-hour timeout) when an instructor asks for it.

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@minLength(6)
@maxLength(6)
param suffix string

param location string = 'centralus'
param databaseVnetName string = '${prefix}-db-secondary-${suffix}-vnet'
param managedInstanceSubnetName string = 'snet-sqlmi'
param sqlEntraAdminObjectId string
param sqlEntraAdminLogin string

@allowed([
  'Freemium'
  'Regular'
])
param pricingModel string = 'Freemium'

@allowed([
  'User'
  'Group'
  'Application'
])
param sqlEntraAdminPrincipalType string = 'User'

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
  Optional: 'SqlManagedInstance'
}

// ---- Optional additions (defaults keep the documented contract) ----

param vCores int = 4
param storageSizeInGB int = 64

var nameToken = take(replace(prefix, '-', ''), 12)

resource databaseVnet 'Microsoft.Network/virtualNetworks@2025-05-01' existing = {
  name: databaseVnetName
}

resource managedInstanceSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' existing = {
  parent: databaseVnet
  name: managedInstanceSubnetName
}

module managedInstance './modules/data/sql-managed-instance.bicep' = {
  name: 'sql-managed-instance'
  params: {
    name: toLower('${nameToken}mi${suffix}')
    location: location
    subnetId: managedInstanceSubnet.id
    entraAdminObjectId: sqlEntraAdminObjectId
    entraAdminLogin: sqlEntraAdminLogin
    entraAdminPrincipalType: sqlEntraAdminPrincipalType
    pricingModel: pricingModel
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    tags: tags
  }
}

output managedInstanceName string = managedInstance.outputs.name
output managedInstanceFqdn string = managedInstance.outputs.fullyQualifiedDomainName
output managedInstancePublicEndpoint string = managedInstance.outputs.publicEndpoint
