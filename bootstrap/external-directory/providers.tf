provider "azuread" {
  tenant_id = var.external_tenant_id
}

provider "random" {}

provider "msgraph" {
  tenant_id = var.external_tenant_id
  use_cli   = true
}
