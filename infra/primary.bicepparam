using './primary.bicep'

// Values come from the GitHub environment variables the Lab 04 bootstrap publishes
// (assets/scripts/Initialize-Lab04Repository.ps1). Nothing secret is stored in this file.

param prefix = readEnvironmentVariable('LAB04_PREFIX', 'caldova-lab04')
param suffix = readEnvironmentVariable('LAB04_SUFFIX')
param location = readEnvironmentVariable('LAB04_PRIMARY_LOCATION', 'northcentralus')

param codeDeploymentPrincipalId = readEnvironmentVariable('LAB06_DEPLOY_AZURE_PRINCIPAL_ID', readEnvironmentVariable('LAB06_AZURE_PRINCIPAL_ID', ''))
param codeBuildPrincipalId = readEnvironmentVariable('LAB06_BUILD_AZURE_PRINCIPAL_ID', '')

param sqlEntraAdminObjectId = readEnvironmentVariable('LAB04_SQL_ADMIN_OBJECT_ID')
param sqlEntraAdminLogin = readEnvironmentVariable('LAB04_SQL_ADMIN_LOGIN')

// VM credentials: read from the bootstrap Key Vault at deployment time and exported only for that
// step (as lab04-deploy.yml does with VM_ADMIN_USERNAME / VM_ADMIN_PASSWORD). Never write them here.
param vmAdminUsername = readEnvironmentVariable('VM_ADMIN_USERNAME')
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')

// Lab-sized defaults.
param windowsVmSize = 'Standard_D2s_v5'
param linuxVmSize = 'Standard_B2s'
param sqlDatabaseName = 'eShop'
param sqlDatabaseSkuName = 'S0'
param sqlDatabaseSkuTier = 'Standard'
param sqlBackupStorageRedundancy = 'Local'
param deployMigrationService = true
