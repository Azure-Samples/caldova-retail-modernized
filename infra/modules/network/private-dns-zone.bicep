@description('Private DNS zone name, e.g. privatelink.vaultcore.azure.net.')
param name string

@description('VNets to link: [{ name: string, virtualNetworkId: string }].')
param virtualNetworkLinks array = []

param tags object = {}

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: name
  location: 'global'
  tags: tags
}

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for link in virtualNetworkLinks: {
    parent: zone
    name: link.name
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: link.virtualNetworkId
      }
    }
  }
]

output id string = zone.id
output name string = zone.name
