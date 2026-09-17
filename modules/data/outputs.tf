output "postgres_server_fqdn" { value = azurerm_postgresql_flexible_server.this.fqdn }
output "postgres_database_name" { value = azurerm_postgresql_flexible_server_database.this.name }
output "key_vault_id" { value = azurerm_key_vault.this.id }
output "key_vault_uri" { value = azurerm_key_vault.this.vault_uri }
output "postgres_connection_secret_uri" { value = "${azurerm_key_vault.this.vault_uri}secrets/${azapi_resource.postgres_connection.name}" }
output "service_token_secret_uri" { value = "${azurerm_key_vault.this.vault_uri}secrets/${azapi_resource.service_token.name}" }
output "storage_account_id" { value = azurerm_storage_account.this.id }
output "servicebus_namespace_id" { value = try(azurerm_servicebus_namespace.this[0].id, null) }
