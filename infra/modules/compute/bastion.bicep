param name string
param location string
param subnetId string
param tags object = {}

resource publicIp 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: '${name}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Basic is the lowest SKU that keeps a dedicated subnet and browser-based RDP and SSH.
resource bastion 'Microsoft.Network/bastionHosts@2025-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    enableShareableLink: false
    enableTunneling: false
    enableIpConnect: false
    enableFileCopy: false
    ipConfigurations: [
      {
        name: 'bastion-ip-configuration'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

output id string = bastion.id
