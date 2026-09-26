output "postgres_server_fqdn" { value = azurerm_postgresql_flexible_server.this.fqdn }
output "postgres_database_name" { value = azurerm_postgresql_flexible_server_database.this.name }
output "key_vault_id" { value = azurerm_key_vault.this.id }
output "key_vault_uri" { value = azurerm_key_vault.this.vault_uri }
output "postgres_connection_secret_uri" { value = "${azurerm_key_vault.this.vault_uri}secrets/${azapi_resource.postgres_connection.name}" }
output "service_token_secret_uri" { value = "${azurerm_key_vault.this.vault_uri}secrets/${azapi_resource.service_token.name}" }
output "identity_master_key_secret_uri" { value = "${azurerm_key_vault.this.vault_uri}secrets/${azapi_resource.identity_protection_master_key.name}" }
output "core_admin_api_key_secret_uri" { value = var.environment == "prod" ? null : "${azurerm_key_vault.this.vault_uri}secrets/${azapi_resource.core_admin_api_key[0].name}" }
output "storage_account_id" { value = azurerm_storage_account.this.id }
output "servicebus_namespace_id" { value = try(azurerm_servicebus_namespace.this[0].id, null) }
