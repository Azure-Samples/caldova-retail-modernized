// Links a VNet to an existing private DNS zone, typically one owned by another resource group.

param privateDnsZoneName string
param virtualNetworkId string
param linkName string
param tags object = {}

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: privateDnsZoneName
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: linkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

output id string = link.id
