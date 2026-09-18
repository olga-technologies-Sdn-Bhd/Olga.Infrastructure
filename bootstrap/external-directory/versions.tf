terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.9, < 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
    msgraph = {
      source  = "Microsoft/msgraph"
      version = ">= 0.5, < 1.0"
    }
  }

  # Dev is the safe default because this one-time root is being bootstrapped
  # before CI can authenticate to the new External ID tenant. Production must
  # continue to supply backend-prd.hcl explicitly.
  backend "azurerm" {
    resource_group_name  = "rg-olga-tfstate"
    storage_account_name = "stolgatfstatee0bb013f"
    container_name       = "tfstate"
    key                  = "olga/external-directory/dev.tfstate"
    use_azuread_auth     = true
    tenant_id            = "9972baa6-9591-43d7-8b13-59da8e6f1a72"
    subscription_id      = "e0bb013f-a8af-4d60-9c5b-0140b361f257"
  }
}
