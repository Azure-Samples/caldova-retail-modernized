// Two private VMs in the primary database VNet: a Windows SQL Server source (SSMS + SHIR) and an
// Ubuntu test VM. Neither gets a public IP; Azure Bastion is the only management path.

param prefix string
param suffix string
param location string
param subnetId string

@description('Windows SQL Server source VM size. SQL Server, SSMS and the integration runtime need 8 GiB.')
param windowsVmSize string

@description('Ubuntu test VM size.')
param linuxVmSize string

@secure()
param adminUsername string

@secure()
param adminPassword string

param tags object = {}

var machines = [
  {
    role: 'source'
    computerName: 'lab-source'
    size: windowsVmSize
    operatingSystem: 'Windows'
    imageReference: {
      publisher: 'MicrosoftSQLServer'
      offer: 'sql2022-ws2022'
      sku: 'sqldev-gen2'
      version: 'latest'
    }
  }
  {
    role: 'test'
    computerName: 'lab-test'
    size: linuxVmSize
    operatingSystem: 'Linux'
    imageReference: {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-jammy'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
  }
]

resource nics 'Microsoft.Network/networkInterfaces@2025-05-01' = [
  for machine in machines: {
    name: '${prefix}-${machine.role}-${suffix}-nic'
    location: location
    tags: tags
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: subnetId
            }
          }
        }
      ]
    }
  }
]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2025-04-01' = [
  for (machine, i) in machines: {
    name: '${prefix}-${machine.role}-${suffix}-vm'
    location: location
    tags: union(tags, {
      WorkloadRole: machine.role
      OperatingSystem: machine.operatingSystem
    })
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      hardwareProfile: {
        vmSize: machine.size
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nics[i].id
            properties: {
              primary: true
            }
          }
        ]
      }
      osProfile: {
        computerName: machine.computerName
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: machine.operatingSystem == 'Windows'
          ? {
              enableAutomaticUpdates: true
              provisionVMAgent: true
              patchSettings: {
                patchMode: 'AutomaticByPlatform'
                assessmentMode: 'AutomaticByPlatform'
              }
            }
          : null
        linuxConfiguration: machine.operatingSystem == 'Linux'
          ? {
              // Bastion SSH uses the Key Vault-held password; rotate it there.
              disablePasswordAuthentication: false
              provisionVMAgent: true
              patchSettings: {
                patchMode: 'AutomaticByPlatform'
                assessmentMode: 'AutomaticByPlatform'
              }
            }
          : null
      }
      storageProfile: {
        imageReference: machine.imageReference
        osDisk: {
          name: '${prefix}-${machine.role}-${suffix}-osdisk'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
    }
  }
]

output virtualMachineIds array = [for i in range(0, length(machines)): virtualMachines[i].id]
output virtualMachineNames array = [for i in range(0, length(machines)): virtualMachines[i].name]
output virtualMachinePrincipalIds array = [for i in range(0, length(machines)): virtualMachines[i].identity.principalId]
