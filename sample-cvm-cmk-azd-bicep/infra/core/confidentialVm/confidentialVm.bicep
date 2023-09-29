@description('Location for all resources.')
param parDeploymentLocation string

param parTags object = {
  costcenter: 'IT'
  environment: 'Test'
  application: 'ConfidentialVM'
}

@description('Key vault name')
param parKeyVaultName string

@description('Virtual network that the Confidential VM connects to.')
param parVNetName string

@description('ResourceGroupName of vNet')
param parResourceGroupNameVnet string

@description('Subnet that the Confidential VM connects to.')
param parSubnetName string

@description('The name of the Confidential VM (resource and host name).')
param parVmName string

@description('The size of the virtual machine')
param parVmSize string

@description('OS image for the virtual Machine')
@allowed([
  'Windows Server 2022 Gen 2'
  'Windows Server 2019 Gen 2'
  'Ubuntu 20.04 LTS Gen 2'
])
param parOsImageName string

@description('OS disk type of the VM.')
@allowed([
  'Premium_LRS'
  'Standard_LRS'
  'StandardSSD_LRS'
])
param parOsDiskType string

@description('Username for the virtual machine.')
param parAdminUsername string

@description('Password for the virtual machine. The password must be at least 12 characters long and have lower case, upper characters, digit and a special character (Regex match)')
@secure()
param parAdminPasswordOrKey string

@description('Type of authentication to use on the virtual machine. SSH Public key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param parAuthenticationType string

@description('Secure Boot setting of the virtual machine.')
param parSecureBoot bool

@description('vTPM setting of the virtual machine.')
param parVTPM bool

@description('Disk Encryption Set Id.')
param parDiskEncryptionSetId string

@description('Virtual Machine Key Id')
param parVmkeyId string

@description('MAA Endpoint to attest to.')
param parMaaEndpoint string

@description('The FQDN of the AD domain')
param parDomainToJoin string = ''


@description('Username of the account on the domain')
param parDomainUsername string = ''

@description('Password of the account on the domain')
@secure()
param parDomainPassword string = ''

@description('Organizational Unit path in which the nodes and cluster will be present.')
param parouPath string = ''

@description('Set of bit flags that define the join options. Default value of 3 is a combination of NETSETUP_JOIN_DOMAIN (0x00000001) & NETSETUP_ACCT_CREATE (0x00000002) i.e. will join the domain and create the account on the domain. For more information see https://msdn.microsoft.com/en-us/library/aa392154(v=vs.85).aspx')
param parDomainJoinOptions int = 3

@description('If “Auto-provisioning” for MMA is turned on in Azure Defender configuration, you can skip installation of MMA agent during VM creation as MDC will auto deploy MMA agent with desired configuations.')
param deployMicrosoftMonitoringAgent bool = false

@description('Resource Id of the LA Workspace to push logs from Microsoft Monitoring Agent.')
param parLaWorkSpaceResourceId string 

@description('If “Auto-provisioning” for AMA is turned on in Azure Defender configuration, you can skip installation of AMA agent during VM creation as MDC will auto deploy AMA agent with desired configuations.')
param deployAzureMonitoringAgent bool =true

@description('VM security type.')
@allowed([ 
  'VMGuestStateOnly'
  'DiskWithVMGuestState'
])
param parSecurityType string = 'DiskWithVMGuestState'





var parDiskName = '${parVmName}-osDisk'

var varImageList = {
  'Windows Server 2022 Gen 2': {
    publisher: 'microsoftwindowsserver'
    offer: 'windowsserver'
    sku: '2022-datacenter-g2'
    version: 'latest'
  }
  'Windows Server 2019 Gen 2': {
    publisher: 'microsoftwindowsserver'
    offer: 'windowsserver'
    sku: '2019-datacenter-g2'
    version: 'latest'
  }
  'Ubuntu 20.04 LTS Gen 2': {
    publisher: 'Canonical'
    offer: '0001-com-ubuntu-confidential-vm-focal'
    sku: '20_04-lts-cvm'
    version: 'latest'
  }
}
var varImageReference = varImageList[parOsImageName]
var varAscReportingEndpoint = 'https://sharedeus2.eus2.attest.azure.net/'
var varDisableAlerts = 'false'
var varExtensionName = 'GuestAttestation'
var varExtensionPublisher = varIsWindows ? 'Microsoft.Azure.Security.WindowsAttestation' : 'Microsoft.Azure.Security.LinuxAttestation'
var varExtensionVersion = '1.0'
var varMaaTenantName = 'GuestAttestation'
var varUseAlternateToken = 'false'
var varIsWindows = contains(parOsImageName, 'Windows')
var varLinuxConfiguration = {
  disablePasswordAuthentication: 'true'
  ssh: {
    publicKeys: [
      {
        keyData: parAdminPasswordOrKey
        path: '/home/${parAdminUsername}/.ssh/authorized_keys'
      }
    ]
  }
}
var varWindowsConfiguration = {
  enableAutomaticUpdates: 'true'
  patchSettings: {
    patchMode: 'AutomaticByPlatform'
  }
  provisionVmAgent: 'true'
}

var varEncryptionOperation = 'EnableEncryption'
var varKeyEncryptionAlgorithm = 'RSA-OAEP'
var varKeyVaultResourceID = resourceId(resourceGroup().name, 'Microsoft.KeyVault/vaults/', parKeyVaultName)



// Virtual network and subnet from common module
resource resVnet 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  scope: resourceGroup(parResourceGroupNameVnet)
  name: parVNetName
}

resource resSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  parent: resVnet
  name: parSubnetName
}

// Virtual machine
resource resVm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: parVmName
  location: parDeploymentLocation
  tags: parTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: parVmSize
    }
    osProfile: {
      computerName: parVmName
      adminUsername: parAdminUsername
      adminPassword: parAdminPasswordOrKey
      linuxConfiguration: ((parAuthenticationType == 'password') ? json('null') : varLinuxConfiguration)
      windowsConfiguration: (varIsWindows ? varWindowsConfiguration : json('null'))
    }
    storageProfile: {
      osDisk: {
        name: parDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: parOsDiskType
          securityprofile: {

            securityEncryptionType: parSecurityType
            diskEncryptionSet: {
              id: parDiskEncryptionSetId
            }
          }
        }
      }
    
      imageReference: varImageReference
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resNIC.id
        }
      ]
    }
    securityProfile: {
      encryptionAtHost: true
      uefiSettings: {
        secureBootEnabled: parSecureBoot
        vTpmEnabled: parVTPM
      }
      securityType: 'ConfidentialVM'
    }
  }
}


// VM NIC
resource resNIC 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: 'nic-${parVmName}'
  location: parDeploymentLocation
  tags: parTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resSubnet.id
          }
        }
      }
    ]
  }
}

resource vmName_extension 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = if (parVTPM && parSecureBoot) {
  parent: resVm
  name: varExtensionName
  location: parDeploymentLocation
  properties: {
    publisher: varExtensionPublisher
    type: varExtensionName
    typeHandlerVersion: varExtensionVersion
    autoUpgradeMinorVersion: true
    forceUpdateTag: '1.0'
    settings: {
      maaEndpoint: parMaaEndpoint
      maaTenantName: varMaaTenantName
      ascReportingEndpoint: varAscReportingEndpoint
      useAlternateToken: varUseAlternateToken
      disableAlerts: varDisableAlerts
      EncryptionOperation: varEncryptionOperation
      KeyVaultURL: reference(varKeyVaultResourceID, '2022-07-01').vaultUri
      KeyVaultResourceId: varKeyVaultResourceID
      KeyEncryptionKeyURL: reference(parVmkeyId, '2022-07-01', 'Full').properties.keyUriWithVersion
      KekVaultResourceId: varKeyVaultResourceID
      KeyEncryptionAlgorithm: varKeyEncryptionAlgorithm
      VolumeType: 'All'
      ResizeOSDisk: false
    }
  }
}


resource virtualMachineExtension 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = if (parDomainToJoin != '')  {
  parent: resVm
  name: 'joindomain'
  location: parDeploymentLocation
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      name: parDomainToJoin
      parouPath: parouPath
      user: parDomainUsername
      restart: true
      options: parDomainJoinOptions
    }
    protectedSettings: {
      Password: parDomainPassword
    }
  }
}


//[Azure_VirtualMachine_SI_Deploy_GuestConfig_Extension]
resource vmExtension_AzurePolicyforWindows 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = {
  parent: resVm
  name: 'AzurePolicyforWindows'
  location: parDeploymentLocation
  properties: {
    publisher: 'Microsoft.GuestConfiguration'
    type: 'ConfigurationforWindows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {}
    protectedSettings: {}
  }
}

resource vmName_AzureMonitorWindowsAgent 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = if (deployAzureMonitoringAgent) {
  parent: resVm
  name: 'AzureMonitorWindowsAgent'
  location: parDeploymentLocation
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: ( varIsWindows ? 'AzureMonitorWindowsAgent' : 'AzureMonitorLinuxAgent')
    typeHandlerVersion: ( varIsWindows ? '1.18.0' : '1.5')
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {}
  }
}



//[Azure_VirtualMachine_SI_Enable_Monitoring_Agent]
resource vmExtension_MicrosoftMonitoringAgent 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = if (deployMicrosoftMonitoringAgent) {
  parent: resVm
  name: 'MicrosoftMonitoringAgent'
  location: parDeploymentLocation
  properties: {
    publisher: 'Microsoft.EnterpriseCloud.Monitoring'
    type: 'MicrosoftMonitoringAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      workspaceId: (deployMicrosoftMonitoringAgent ? reference(parLaWorkSpaceResourceId, '2020-08-01').customerId : 'NotRequired')
     }
    protectedSettings: {
      workspaceKey: (deployMicrosoftMonitoringAgent ? listKeys(parLaWorkSpaceResourceId, '2020-08-01').primarySharedKey : 'NotRequired')
    }
  }
}
