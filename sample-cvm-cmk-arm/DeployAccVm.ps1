# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Script based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-arm-amd#deploy-confidential-vm-template-with-azure-cli 
    Used to deploy confidential VM template no disk encryption


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
        $parUniqueSuffix = "a2",

        [Parameter(Position = 3, mandatory = $false)]
        [string]
        $region = "westeurope"

    )

$deployName="acc-test-$($parUniqueSuffix)-vmDeploy"
$resourceGroup="rg-acc-$($parUniqueSuffix)"
$cvmArmTemplate = "deployCPSCVM2.json"
$cvmParameterFile = "azuredeploy.parameters.json"

az group create -n $resourceGroup -l $region

az deployment group create `
 -g $resourceGroup `
 -n $deployName `
 -f $cvmArmTemplate `
 -p $cvmParameterFile `
 -p vmLocation=$region `
 -p vmName=$vmName `
 -p adminPasswordOrKey=$adminPasswordOrKey