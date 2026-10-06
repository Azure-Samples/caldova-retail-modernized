@description('Secondary database VNet name. sqlmi.bicep and the SQL MI workflow look it up by this name.')
param name string
param location string
param addressPrefix string
param managedInstanceSubnetPrefix string
param managedInstanceSubnetName string = 'snet-sqlmi'
@description('Must contain "-sqlmi-": Enable-Lab04SqlMiPublicAccess.ps1 discovers the NSG by that token.')
param networkSecurityGroupName string
param routeTableName string
param tags object = {}

// SQL MI service-aided subnet configuration adds and maintains its own management rules and routes
// after delegation; these resources only declare the workload intent and must not block those entries.
resource managedInstanceNsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSqlFromVirtualNetwork'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '1433'
            '11000-11999'
          ]
        }
      }
    ]
  }
}

resource managedInstanceRouteTable 'Microsoft.Network/routeTables@2025-05-01' = {
  name: routeTableName
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: []
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
        name: managedInstanceSubnetName
        properties: {
          addressPrefix: managedInstanceSubnetPrefix
          networkSecurityGroup: {
            id: managedInstanceNsg.id
          }
          routeTable: {
            id: managedInstanceRouteTable.id
          }
          delegations: [
            {
              name: 'managed-instance'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output managedInstanceSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, managedInstanceSubnetName)
