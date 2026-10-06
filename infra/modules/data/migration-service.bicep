// Azure Database Migration Service in the sqlMigrationServices model, which the self-hosted
// integration runtime on the source VM registers with (Lab 05). It needs no delegated subnet.

param name string
param location string
param tags object = {}

resource migrationService 'Microsoft.DataMigration/sqlMigrationServices@2025-06-30' = {
  name: name
  location: location
  tags: tags
  properties: {}
}

output id string = migrationService.id
output name string = migrationService.name
