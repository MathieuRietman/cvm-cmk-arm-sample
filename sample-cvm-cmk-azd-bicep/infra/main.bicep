targetScope = 'subscription'

// The main bicep module to provision Azure resources.
// For a more complete walkthrough to understand how this file works with azd,
// see https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/make-azd-compatible?pivots=azd-create

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param parLocation string

// Optional parameters to override the default azd resource naming conventions.
// Add the following to main.parameters.json to provide values:
// "resourceGroupName": {
//      "value": "myGroupName"
// }
param parResourceGroupName string = ''

@description('Name of the attestation service to deploy option alse name of the environment')
param parAttestationName string = ''

@description('Name of the keyVault is empty then based on environment')
param parKeyVaultName string = ''

@description('Name of the DiskEncryptionSet if empty then based on environment')
param parDiskEncryptionSetName string = ''

@secure()
@description('The local admin password')
param parSecretPassword string 

@description('The name of the VM')
param parVmName string 

@description('The Type of the VM')
param parVmSize string 

@description('The name of the Vnet where to add the VM')
param parVNetName string

@description('The name of the Vnet resource group')
param parResourceGroupNameVnet string

@description('The name of the Vnet subnetName')
param parSubnetName string


// tags that should be applied to all resources.
param tags object = {
  // Tag all resources with the environment name.
  'azd-env-name': environmentName 
  application: environmentName 
  environment: 'dev'
  costcenter: '10100'


}

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

@secure()
@description('The domain Join password')
param parDomainPassword string

param parDomainToJoin string

param parDomainUsername string

@description('Username for the virtual machine.')
param parAdminUsername string

@description('objectId for Confidential VM Orchestrator.')
param parObjectConfidentialVMOrchestrator string

@description('The resource id of the workspace to be used for the deployment.'	)
param parLaWorkSpaceResourceId string

var abbrs = loadJsonContent('./abbreviations.json')

// Generate a unique token to be used in naming resources.
// Remove linter suppression after using.
#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, parLocation))

// Name of the service defined in azure.yaml
// A tag named azd-service-name with this value should be applied to the service host resource, such as:
//   Microsoft.Web/sites for appservice, function
// Example usage:
//   tags: union(tags, { 'azd-service-name': apiServiceName })


// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(parResourceGroupName) ? parResourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: parLocation
  tags: tags
}

// Add resources to be provisioned below.

module modAttestation './core/attestation/attestation.bicep' = {
  name: 'deploy-Attestation'
  scope: rg
  params: {
    parLocation: parLocation
    attestationProviderName: toLower(!empty(parAttestationName) ? parAttestationName : '${abbrs.attestation}${environmentName}${resourceToken}')
    policySigningCertificates: ''
  
    parTags: tags
  }
}

module modDiskEncryptionSet './core/diskEncryptionSetName/diskEncryptionSet.bicep' ={
  name: 'deploy-diskEncryptionSet'
  scope: rg
  params: {
    parLocation: parLocation
    parKeyVaultName :  !empty(parKeyVaultName) ? parKeyVaultName :'${abbrs.keyVaultVaults}${environmentName}${resourceToken}'
    parDiskEncryptionSetName: !empty(parDiskEncryptionSetName) ? parDiskEncryptionSetName :'${abbrs.computeDiskEncryptionSets}${environmentName}${resourceToken}'
    parVmDiskKey: 'key${abbrs.computeDiskEncryptionSets}${environmentName}${resourceToken}'
    parObjectConfidentialVMOrchestrator:  parObjectConfidentialVMOrchestrator
    parTags: tags
    
    
  }

}


module modConvidentialVM './core/confidentialVm/confidentialVm.bicep' = {
  name: 'confidentialVm'
  scope: rg
  params: {
    parTags: tags
    parAdminPasswordOrKey: parSecretPassword
    parAdminUsername: parAdminUsername
    parAuthenticationType: 'password'
    parDeploymentLocation: parLocation
    parDiskEncryptionSetId:  modDiskEncryptionSet.outputs.outResEncryptionSet
    parKeyVaultName: modDiskEncryptionSet.outputs.outKeyVaultName 
    parMaaEndpoint: modAttestation.outputs.attestationUri
    parOsDiskType: parOsDiskType
    parOsImageName: parOsImageName
    parSecureBoot: true
    parVmkeyId: modDiskEncryptionSet.outputs.outVmKey
    parVmName: parVmName
    parVmSize: parVmSize
    parVNetName: parVNetName
    parResourceGroupNameVnet: parResourceGroupNameVnet
    parSubnetName: parSubnetName
    parVTPM: true
    parDomainPassword: parDomainPassword
    parDomainToJoin: parDomainToJoin
    parDomainUsername: parDomainUsername
    parLaWorkSpaceResourceId: parLaWorkSpaceResourceId
    deployAzureMonitoringAgent: false
  }
}

// Add outputs from the deployment here, if needed.
//
// This allows the outputs to be referenced by other bicep deployments in the deployment pipeline,
// or by the local machine as a way to reference created resources in Azure for local development.
// Secrets should not be added here.
//
// Outputs are automatically saved in the local azd environment .env file.
// To see these outputs, run `azd env get-values`,  or `azd env get-values --output json` for json output.
output AZURE_LOCATION string = parLocation
output AZURE_TENANT_ID string = tenant().tenantId
