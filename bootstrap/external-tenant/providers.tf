provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  tenant_id           = var.management_tenant_id
  storage_use_azuread = true
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.management_tenant_id
}
