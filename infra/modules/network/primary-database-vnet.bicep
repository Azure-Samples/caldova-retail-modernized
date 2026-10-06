@description('Primary database VNet name.')
param name string
param location string
param addressPrefix string
param bastionSubnetPrefix string
param vmSubnetPrefix string
param privateEndpointSubnetPrefix string
param vmNetworkSecurityGroupName string
param tags object = {}

// Remote management reaches the VMs only from the Bastion subnet; everything else is denied,
// including traffic from peered VNets that the default AllowVnetInBound rule would admit.
resource vmNsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: vmNetworkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRdpSshFromBastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'DenyRdpSshFromOtherSources'
        properties: {
          priority: 4000
          access: 'Deny'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: 'snet-vms'
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: {
            id: vmNsg.id
          }
          // New subnets are private by default. The SQL/SHIR VM needs outbound HTTPS to register the
          // integration runtime and receive updates; a NAT gateway is the production alternative.
          defaultOutboundAccess: true
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output bastionSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'AzureBastionSubnet')
output vmSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-vms')
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-private-endpoints')
