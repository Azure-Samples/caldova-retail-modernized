// The retail Container App. Lab 04 runs a Microsoft sample image on port 8080; Lab 06 replaces
// only the image, so the environment variables below are the app's long-lived Azure contract.

param name string
param location string
param environmentId string
param registryServer string
param runtimeIdentityResourceId string

@description('Placeholder image. The workshop application is deployed in Lab 06, not here.')
param image string

param targetPort int

@description('vCPU per replica, as a string (e.g. "0.5").')
param cpu string

param memory string

@minValue(2)
param minReplicas int

param maxReplicas int

@minValue(1)
param httpConcurrentRequests int

@description('GET path used by the startup, liveness and readiness probes.')
param healthProbePath string

@description('Plain environment variables: [{ name: string, value: string }]. Must not contain credentials.')
param environmentVariables array

@description('Application Insights component in this resource group; its connection string is held as a Container Apps secret.')
param applicationInsightsName string

param tags object = {}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

var appInsightsSecretName = 'appinsights-connection-string'

resource app 'Microsoft.App/containerApps@2025-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        // Inside an internal environment, "external" means reachable from the VNet and the
        // Front Door private endpoint - never from the internet.
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: registryServer
          identity: 'system'
        }
      ]
      secrets: [
        {
          name: appInsightsSecretName
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'placeholder'
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: concat(environmentVariables, [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: appInsightsSecretName
            }
          ])
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: healthProbePath
                port: targetPort
              }
              initialDelaySeconds: 1
              periodSeconds: 3
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {
                path: healthProbePath
                port: targetPort
              }
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: healthProbePath
                port: targetPort
              }
              periodSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: string(httpConcurrentRequests)
              }
            }
          }
        ]
      }
    }
  }
}

output id string = app.id
output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output systemPrincipalId string = app.identity.principalId
