[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][string]$StorageAccountName,
    [Parameter(Mandatory)]
    [ValidateScript({
        if ($_ -cnotin @('dev', 'prd')) {
            throw 'Environment must be exactly dev or prd.'
        }
        $true
    })]
    [string]$Environment,
    [string]$ResourceGroupName = 'rg-olga-tfstate',
    [string]$ContainerName = 'tfstate'
)

$ErrorActionPreference = 'Stop'
az account set --subscription $SubscriptionId
az group create --name $ResourceGroupName --location $Location --tags product=olga-connect managedBy=bootstrap | Out-Null
az storage account create --name $StorageAccountName --resource-group $ResourceGroupName --location $Location --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false | Out-Null
az storage container create --name $ContainerName --account-name $StorageAccountName --auth-mode login | Out-Null

Write-Output "resource_group_name  = `"$ResourceGroupName`""
Write-Output "storage_account_name = `"$StorageAccountName`""
Write-Output "container_name       = `"$ContainerName`""
Write-Output "key                  = `"olga/$Environment.tfstate`""
Write-Output 'use_azuread_auth     = true'
