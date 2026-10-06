// Optional Entra-only SQL Managed Instance, deployed only through sqlmi.bicep and its manual workflow.

param name string
param location string
param subnetId string
param entraAdminObjectId string
param entraAdminLogin string

@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdminPrincipalType string

@allowed([
  'Freemium'
  'Regular'
])
param pricingModel string

param vCores int = 4
param storageSizeInGB int = 64
param tags object = {}

resource managedInstance 'Microsoft.Sql/managedInstances@2023-08-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: vCores
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdminLogin
      principalType: entraAdminPrincipalType
      sid: entraAdminObjectId
      tenantId: subscription().tenantId
    }
    subnetId: subnetId
    pricingModel: pricingModel
    isGeneralPurposeV2: true
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    licenseType: 'LicenseIncluded'
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    timezoneId: 'UTC'
    minimalTlsVersion: '1.2'
    proxyOverride: 'Redirect'
    // Public endpoint (TCP 3342) is enabled, but no broad ingress is created here: participants add
    // their own /32 NSG rule with Enable-Lab04SqlMiPublicAccess.ps1.
    publicDataEndpointEnabled: true
    requestedBackupStorageRedundancy: 'Local'
    managedInstanceCreateMode: 'Default'
  }
}

output id string = managedInstance.id
output name string = managedInstance.name
output fullyQualifiedDomainName string = managedInstance.properties.fullyQualifiedDomainName
output publicEndpoint string = '${replace(managedInstance.properties.fullyQualifiedDomainName, '${managedInstance.name}.', '${managedInstance.name}.public.')},3342'
