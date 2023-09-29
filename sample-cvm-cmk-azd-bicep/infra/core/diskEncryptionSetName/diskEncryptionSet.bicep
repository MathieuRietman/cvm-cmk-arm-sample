// Todo is go back to vault access policy as release is not a fine grained permission
@minLength(1)
@description('Primary location for all resources')
param parLocation string


@description('Name of the KeyVault')
param parKeyVaultName string = ''

param parDiskEncryptionSetName string 

param parVmDiskKey string 

param parTags object = {}

param utcValue string = utcNow()

@description('The key size in bits. For example: 2048, 3072, or 4096 for RSA.')
@allowed([
  2048
  3072
  4096
])
param parKeySize int = 3072

@description('The type of key to create')
@allowed([
  'EC'
  'EC-HSM'
  'RSA'
  'RSA-HSM'
])
param parKty string = 'RSA-HSM'

// @description('JSON web key operations. Operations include: \'encrypt\', \'decrypt\', \'sign\', \'verify\', \'wrapKey\', \'unwrapKey\'')
// param parKeyops array = ['encrypt', 'decrypt', 'sign', 'verify', 'wrapKey', 'unwrapKey']

@description('Expiry date in seconds since 1970-01-01T00:00:00Z.  Defaults to 1 year from today.')
param parExp int = dateTimeToEpoch(dateTimeAdd(utcNow(), 'P10Y'))

@description('objectId for Confidential VM Orchestrator.')
param parObjectConfidentialVMOrchestrator string

var base64Policy = base64(loadTextContent('skr-policy.json'))




//create an var with parEnvironmentName and parResourceToken

var sleepSeconds = 20


var sleepName = '${parDiskEncryptionSetName}-sleep'



//create an user assigned identity called diskencryptionset
resource resUserAssignedIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: parDiskEncryptionSetName
  location: parLocation
  tags: parTags
}

//Create a keyvault to store customer managed keys
resource resKeyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: parKeyVaultName
  tags: parTags
  location: parLocation
  properties: {

    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true // Required by disk encryption set
    softDeleteRetentionInDays: 7
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    networkAcls: {
      // defaultAction: 'Deny'
      // ipRules: []
    }

    // accessPolicies: [
    //   {
    //     tenantId: subscription().tenantId
    //     objectId: parObjectIdCurrentUser 
    //     permissions: {
    //       keys: [
    //         'get'
    //         'list'
    //       ]
    //       secrets: [
    //         'get'
    //         'list'
    //       ]
    //     }
    //   }
    // ]
  }
}

resource resSecret 'Microsoft.KeyVault/vaults/keys@2021-11-01-preview' = {
  parent: resKeyVault
  name: parVmDiskKey
  properties: {
    kty: parKty
    keyOps: []
    keySize: parKeySize
    attributes: {
      exp: parExp
      exportable: true
    }
    curveName: ''
    release_policy: {
    data: base64Policy
    }
  }
}




//Create disk encryption set
resource resDiskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2022-07-02' = {
  name: parDiskEncryptionSetName
  location: parLocation
  tags: parTags
  dependsOn: [
    resSecret
  ]
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    activeKey: {
      sourceVault: {
        id: resKeyVault.id
      }
      keyUrl: resSecret.properties.keyUriWithVersion
    }
    encryptionType: 'ConfidentialVmEncryptedWithCustomerKey'
    // rotationToLatestKeyVersionEnabled: true  // only when user assigned identity  }
  }
}



//Set permission on RBAC methodd for keyvault and disk encryption set
resource keyPermissions 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resSecret.id, 'Key Vault Crypto User', resDiskEncryptionSet.id)
  dependsOn: [
    resDiskEncryptionSet
  ]
  scope: resKeyVault
  properties: {
    principalId: resDiskEncryptionSet.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6') // Key Vault Crypto Service Encryption User
    principalType: 'ServicePrincipal'
  }
}

//Set permission on RBAC methodd for Confidential VM Orchestrator should be --key-permissions get release but is now admin role go back to access policies

resource keyPermissionsConfidentialVMOrchestrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resSecret.id, 'ConfidentialVMOrchestrator', resDiskEncryptionSet.id)
  dependsOn: [
    resDiskEncryptionSet
  ]
  scope: resKeyVault
  properties: {
    principalId: parObjectConfidentialVMOrchestrator
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault  Administrator
    principalType: 'ServicePrincipal'
  }
}


resource resSleepDelay 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: sleepName
  location: parLocation
  tags: parTags
  kind: 'AzurePowerShell'  
  properties: {
    forceUpdateTag: utcValue
    azPowerShellVersion: '8.3'
    timeout: 'PT10M'    
    arguments: '-seconds ${sleepSeconds}'    
    scriptContent: '''
    param ( [string] $seconds )    
    Write-Output Sleeping for: $seconds ....
    Start-Sleep -Seconds $seconds   
    Write-Output Sleep over - resuming ....
    '''
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}



output outResEncryptionSet string = resDiskEncryptionSet.id
output outKeyVaultId string = resKeyVault.id
output outKeyVaultName string = resKeyVault.name
output outVmKey string = resSecret.id
