using './global.bicep'

// originFqdn and containerAppsEnvironmentId are secondary.bicep outputs (containerAppFqdn,
// containerAppsEnvironmentId); export them as these variables before deploying.

param prefix = readEnvironmentVariable('LAB04_PREFIX', 'caldova-lab04')
param suffix = readEnvironmentVariable('LAB04_SUFFIX')
param applicationLocation = readEnvironmentVariable('LAB04_APPLICATION_LOCATION', 'centralus')
param codeDeploymentPrincipalId = readEnvironmentVariable('LAB06_DEPLOY_AZURE_PRINCIPAL_ID', readEnvironmentVariable('LAB06_AZURE_PRINCIPAL_ID', ''))
param originFqdn = readEnvironmentVariable('LAB04_CONTAINER_APP_FQDN')
param containerAppsEnvironmentId = readEnvironmentVariable('LAB04_CONTAINER_APPS_ENVIRONMENT_ID')

param healthProbePath = '/'
param wafMode = 'Detection'
