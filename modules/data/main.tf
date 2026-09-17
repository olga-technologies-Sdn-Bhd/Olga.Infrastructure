data "azurerm_client_config" "current" {}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "link-postgresql-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.virtual_network_id
  tags                  = var.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "psql-olga-${var.suffix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "17"
  public_network_access_enabled = length(var.postgres_firewall_rules) > 0
  administrator_login           = var.postgres_admin_username
  administrator_password        = var.postgres_admin_password
  sku_name                      = var.postgres_sku_name
  storage_mb                    = var.postgres_storage_mb
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  tags                          = var.tags

  authentication {
    active_directory_auth_enabled = var.postgres_entra_admin != null
    password_auth_enabled         = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  lifecycle {
    ignore_changes = [zone]
  }

}

resource "azurerm_postgresql_flexible_server_firewall_rule" "dbeaver" {
  for_each = var.postgres_firewall_rules

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  count = var.postgres_entra_admin == null ? 0 : 1

  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.postgres_entra_admin.object_id
  principal_name      = var.postgres_entra_admin.principal_name
  principal_type      = var.postgres_entra_admin.principal_type
}

resource "azurerm_private_endpoint" "postgres" {
  name                = "pe-postgresql-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-postgresql"
    private_connection_resource_id = azurerm_postgresql_flexible_server.this.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "postgresql"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres.id]
  }
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = "olga_connect_${var.environment}"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value = join(",", sort(distinct([
    for extension in var.postgres_allowed_extensions : upper(trimspace(extension))
  ])))
}

resource "azurerm_postgresql_flexible_server_configuration" "log_lock_waits" {
  name      = "log_lock_waits"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "ON"
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-olga-${var.suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = length(var.postgres_firewall_rules) > 0
  purge_protection_enabled      = var.environment == "prod"
  soft_delete_retention_days    = 7
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules = [
      for rule in values(var.postgres_firewall_rules) : "${rule.start_ip_address}/32"
    ]
  }
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "link-key-vault-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = var.virtual_network_id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-key-vault-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-key-vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "key-vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "random_password" "service_token" {
  length  = 48
  special = false
}

locals {
  postgres_connection_string = "Host=${azurerm_postgresql_flexible_server.this.fqdn};Port=5432;Database=${azurerm_postgresql_flexible_server_database.this.name};Username=${var.postgres_admin_username};Password=${var.postgres_admin_password};SSL Mode=VerifyFull;Trust Server Certificate=false;Maximum Pool Size=25"
}

# Secrets use the ARM control plane so private-only vaults do not require a public CI runner exception.
resource "azapi_resource" "postgres_connection" {
  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  parent_id = azurerm_key_vault.this.id
  name      = "postgresql-connection"
  body = {
    properties = {
      value = local.postgres_connection_string
    }
  }
}

resource "azurerm_role_assignment" "database_administrator_connection_secret_reader" {
  count = var.postgres_entra_admin == null ? 0 : 1

  scope                = azapi_resource.postgres_connection.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.postgres_entra_admin.object_id
}

resource "azapi_resource" "service_token" {
  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  parent_id = azurerm_key_vault.this.id
  name      = "service-authorization-token"
  body = {
    properties = {
      value = random_password.service_token.result
    }
  }
}

resource "azurerm_storage_account" "this" {
  name                            = "stolga${var.suffix}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
  shared_access_key_enabled = false
  tags                      = var.tags
}

resource "azapi_update_resource" "blob_service" {
  type        = "Microsoft.Storage/storageAccounts/blobServices@2023-05-01"
  resource_id = "${azurerm_storage_account.this.id}/blobServices/default"
  body = {
    properties = {
      deleteRetentionPolicy          = { enabled = true, days = 7 }
      containerDeleteRetentionPolicy = { enabled = true, days = 7 }
    }
  }
}

resource "azapi_resource" "container" {
  for_each = toset(["chat-files", "verification-evidence", "privacy-exports", "evaluation-reports"])

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  parent_id = azapi_update_resource.blob_service.id
  name      = each.value
  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = var.virtual_network_id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_servicebus_namespace" "this" {
  count = var.enable_service_bus ? 1 : 0

  name                = "sb-olga-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  minimum_tls_version = "1.2"
  local_auth_enabled  = false
  tags                = var.tags
}

resource "azurerm_servicebus_queue" "work" {
  for_each = var.enable_service_bus ? toset(["embedding", "content-scan", "notification", "privacy-retention", "outbox"]) : toset([])

  name                                    = each.value
  namespace_id                            = azurerm_servicebus_namespace.this[0].id
  max_delivery_count                      = 5
  lock_duration                           = "PT1M"
  dead_lettering_on_message_expiration    = true
  requires_duplicate_detection            = true
  duplicate_detection_history_time_window = "PT10M"
}

locals {
  application_principals = {
    core   = var.core_identity_principal_id
    nlp    = var.nlp_identity_principal_id
    worker = var.worker_identity_principal_id
  }
  key_vault_principals = merge(local.application_principals, {
    database_migration = var.database_migration_identity_principal_id
  })
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  for_each = local.key_vault_principals

  scope                            = azurerm_key_vault.this.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "blob_data_contributor" {
  for_each = local.application_principals

  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "servicebus_data_sender" {
  for_each = var.enable_service_bus ? local.application_principals : {}

  scope                            = azurerm_servicebus_namespace.this[0].id
  role_definition_name             = "Azure Service Bus Data Sender"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "servicebus_data_receiver" {
  for_each = var.enable_service_bus ? toset([var.nlp_identity_principal_id, var.worker_identity_principal_id]) : toset([])

  scope                            = azurerm_servicebus_namespace.this[0].id
  role_definition_name             = "Azure Service Bus Data Receiver"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}
