# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Script based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-arm-amd#deploy-confidential-vm-template-with-os-disk-confidential-encryption-via-customer-managed-key 
    Used to deploy confidential VM template with OS disk confidential encryption via customer-managed key

    if needed install msgraph 

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Install-Module Microsoft.Graph -Scope CurrentUser -Force

    #>
using namespace System.Collections

param (
    [Parameter(Position = 0, mandatory = $true)]
    [string]
    $vmName = $(Read-Host -prompt "Provide the VMname"),
  
    [SecureString]
    [Parameter(Position = 1, mandatory = $true)]
    $adminPasswordOrKey = $(Read-Host -prompt "Provide the password"),
  

    [Parameter(Position = 2, mandatory = $false)]
    [string]
    $parUniqueSuffix = "b5",

    [Parameter(Position = 3, mandatory = $false)]
    [string]
    $region = "westeurope"
)



$deployNameDes="acc-test-$($parUniqueSuffix)-desDeploy"
$deployNameVm= "acc-test-$($parUniqueSuffix)-vmDeploy"
$resourceGroup="rg-acc-$($parUniqueSuffix)"
$cvmArmTemplate = "deployCPSCVM_cmk.json"
$KeyVault = "kv-acc-test-$($parUniqueSuffix)"
$desName = "des-acc-test-$($parUniqueSuffix)"
$desArmTemplate = "deployDES.json"
$cvmParameterFile = "azuredeploy.parameters.json"

# Grant confidential VM Service Principal Confidential VM Orchestrator to tenant
# For this step you need to be a Global Admin or you need to have the User Access Administrator RBAC role.
# We use the token from the script running. 
# If done seperate comment out 
$AccessToken = ConvertTo-SecureString((Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/").token) -AsPlainText -Force
Connect-MgGraph -AccessToken $AccessToken -NoWelcome

# if Get-MgServicePrincipalEndpoint -AppId bf7b6499-ff71-4aa2-97a4-f372087be7f0  is null then create it 
$checkSpExist = Get-MgServicePrincipal -Filter "AppId eq 'bf7b6499-ff71-4aa2-97a4-f372087be7f0'" |  Format-List Id, DisplayName, AppId, SignInAudience

if (!$checkSpExist) {
    New-MgServicePrincipal -AppId bf7b6499-ff71-4aa2-97a4-f372087be7f0 -DisplayName "Confidential VM Orchestrator"
}

# Create the resource group
az group create --name $resourceGroup --location $region

# Create the Key Vault
az keyvault create --name $KeyVault --resource-group $resourceGroup --location $region --sku Premium --enable-purge-protection

# set the access policies
$cvmAgent = az ad sp show --id "bf7b6499-ff71-4aa2-97a4-f372087be7f0" | Out-String | ConvertFrom-Json
az keyvault set-policy --name $KeyVault --object-id $cvmAgent.Id --key-permissions get release --resource-group $resourceGroup

# Create the Key for disk encryption  
$KeyName = "disk-secure-key"
$KeySize = 3072
az keyvault key create --vault-name $KeyVault --name $KeyName --ops wrapKey unwrapkey --kty RSA-HSM --size $KeySize --exportable true --policy "@.\skr-policy.json" 

# Create the Disk Encryption Set
$encryptionKeyVaultId = ((az keyvault show -n $KeyVault -g $resourceGroup) | ConvertFrom-Json).id
$encryptionKeyURL= ((az keyvault key show --vault-name $KeyVault --name $KeyName ) | ConvertFrom-Json).key.kid

cfs Ms4Sov

az deployment group create `
    -g $resourceGroup `
    -n $deployNameDes `
    -f $desArmTemplate `
    -p desName=$desName `
    -p encryptionKeyURL=$encryptionKeyURL `
    -p encryptionKeyVaultId=$encryptionKeyVaultId `
    -p region=$region

# Grant the Disk Encryption Set access to the Key Vault
$desIdentity= (az disk-encryption-set show -n $desName -g $resourceGroup --query [identity.principalId] -o tsv)
az keyvault set-policy -n $KeyVault `
    -g $resourceGroup `
    --object-id $desIdentity `
    --key-permissions wrapkey unwrapkey get

# Get the Disk Encryption Set ID
$desID = (az disk-encryption-set show -n $desName -g $resourceGroup --query [id] -o tsv)

# Deploy the VM
az deployment group create `
    -g $resourceGroup `
    -n $deployNameVm `
    -f $cvmArmTemplate `
    -p $cvmParameterFile `
    -p diskEncryptionSetId=$desID `
    -p vmName=$vmName `
    -p adminPasswordOrKey=$adminPasswordOrKey `
    -p parKeyVaultName="$($KeyVault)" `
    -p parVmkeyId="$($encryptionKeyURL)"