locals {
  resource_group_name = "rg-olga-external-id-${var.environment}-${var.resource_group_location}"
  tags = {
    product     = "olga-connect"
    environment = var.environment
    owner       = var.owner
    managedBy   = "terraform"
    purpose     = "external-identity"
  }
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.resource_group_location
  tags     = local.tags
}

resource "azapi_resource" "external_tenant" {
  type      = "Microsoft.AzureActiveDirectory/ciamDirectories@2023-05-17-preview"
  name      = var.tenant_subdomain
  parent_id = azurerm_resource_group.this.id
  location  = var.tenant_data_location
  tags      = local.tags

  body = {
    properties = {
      createTenantProperties = {
        countryCode = var.tenant_country_code
        displayName = var.tenant_display_name
      }
    }
    sku = {
      name = "Standard"
      tier = "A0"
    }
  }

  response_export_values = ["properties.tenantId"]

  # The published preview schema has an empty location enum. Input validation
  # above restricts this to the four locations documented by Microsoft.
  schema_validation_enabled = false

  lifecycle {
    prevent_destroy = true
  }
}
