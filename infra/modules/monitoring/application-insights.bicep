// Workspace-based Application Insights. App setting contract: APPLICATIONINSIGHTS_CONNECTION_STRING.
// Local auth stays enabled because the app exports with the connection string alone; switching to
// Entra-only ingestion needs an app change (pass a credential) plus Monitoring Metrics Publisher.

param name string
param location string
param logAnalyticsWorkspaceId string
param tags object = {}

resource component 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
    IngestionMode: 'LogAnalytics'
    DisableLocalAuth: false
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = component.id
output name string = component.name
