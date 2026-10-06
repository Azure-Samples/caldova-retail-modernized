using './secondary.bicep'

// Values come from the bootstrap's GitHub environment variables. Names produced by primary.bicep are
// deterministic, so they are derived here instead of copied from its outputs.

var subscriptionId = readEnvironmentVariable('AZURE_SUBSCRIPTION_ID')
var primaryResourceGroup = readEnvironmentVariable('LAB04_PRIMARY_RESOURCE_GROUP')
var labPrefix = readEnvironmentVariable('LAB04_PREFIX', 'caldova-lab04')
var labSuffix = readEnvironmentVariable('LAB04_SUFFIX')
var nameToken = take(replace(labPrefix, '-', ''), 12)
var primaryVnetName = '${labPrefix}-db-primary-${labSuffix}-vnet'

param prefix = labPrefix
param suffix = labSuffix
param location = readEnvironmentVariable('LAB04_SECONDARY_LOCATION', 'centralus')
param applicationLocation = readEnvironmentVariable('LAB04_APPLICATION_LOCATION', 'centralus')

param codeDeploymentPrincipalId = readEnvironmentVariable('LAB06_DEPLOY_AZURE_PRINCIPAL_ID', readEnvironmentVariable('LAB06_AZURE_PRINCIPAL_ID', ''))

param containerRegistryName = toLower('${nameToken}cr${labSuffix}')
param containerRegistryResourceGroupName = primaryResourceGroup
param privateDnsZoneResourceGroupName = primaryResourceGroup
param primaryDatabaseResourceGroupName = primaryResourceGroup
param primaryDatabaseVnetName = primaryVnetName
param primaryDatabaseVnetId = '/subscriptions/${subscriptionId}/resourceGroups/${primaryResourceGroup}/providers/Microsoft.Network/virtualNetworks/${primaryVnetName}'

// Lab-sized defaults: two always-on replicas, bounded HTTP scale-out, smallest cache tier, capped logs.
param containerImage = 'mcr.microsoft.com/dotnet/samples:aspnetapp'
param targetPort = 8080
param containerCpu = '0.5'
param containerMemory = '1Gi'
param minReplicas = 2
param maxReplicas = 5
param httpConcurrentRequests = 50
param healthProbePath = '/'
param sqlDatabaseName = 'eShop'
param redisSkuName = 'Balanced_B0'
param redisHighAvailability = 'Disabled'
param logRetentionInDays = 30
param logDailyQuotaGb = 1
param keyVaultSoftDeleteRetentionInDays = 7
