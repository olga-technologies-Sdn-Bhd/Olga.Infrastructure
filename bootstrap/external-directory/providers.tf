provider "azuread" {
  tenant_id = var.external_tenant_id
  client_id = var.external_directory_client_id
  use_oidc  = var.use_oidc
  use_cli   = !var.use_oidc
}

provider "random" {}

provider "msgraph" {
  tenant_id = var.external_tenant_id
  client_id = var.external_directory_client_id
  use_oidc  = var.use_oidc
  use_cli   = !var.use_oidc
}
