targetScope = 'resourceGroup'

// Global entry point: Front Door Premium with one Private Link origin and a WAF policy, plus
// profile-scoped Reader for the Lab 06 deploy identity's endpoint lookup and smoke test.

import { roleDefinitionIds } from './modules/shared/roles.bicep'

@minLength(3)
@maxLength(18)
param prefix string = 'caldova-lab04'

@minLength(6)
@maxLength(6)
param suffix string

param applicationLocation string = 'centralus'
param codeDeploymentPrincipalId string
param originFqdn string
param containerAppsEnvironmentId string

param tags object = {
  Application: 'Caldova'
  Environment: 'Lab'
  ManagedBy: 'Bicep'
}

// ---- Optional additions (defaults keep the documented contract) ----

@description('Origin health probe path (GET).')
param healthProbePath string = '/'

@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Detection'

var nameToken = take(replace(prefix, '-', ''), 12)

module frontDoor './modules/edge/front-door.bicep' = {
  name: 'front-door'
  params: {
    profileName: '${prefix}-${suffix}-afd'
    endpointName: '${nameToken}-${suffix}'
    wafPolicyName: '${nameToken}waf${suffix}'
    originFqdn: originFqdn
    containerAppsEnvironmentId: containerAppsEnvironmentId
    privateLinkLocation: applicationLocation
    healthProbePath: healthProbePath
    wafMode: wafMode
    tags: tags
  }
}

module codeDeploymentReader './modules/rbac/front-door-role.bicep' = {
  name: 'code-deployment-front-door-reader'
  params: {
    profileName: frontDoor.outputs.profileName
    principalId: codeDeploymentPrincipalId
    roleDefinitionId: roleDefinitionIds.reader
  }
}

output frontDoorEndpointHostName string = frontDoor.outputs.endpointHostName
output frontDoorProfileId string = frontDoor.outputs.profileId
