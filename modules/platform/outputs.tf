output "core_api_url" { value = "https://${azurerm_container_app.core_api.latest_revision_fqdn}" }
output "core_swagger_url" { value = "https://${azurerm_container_app.core_api.latest_revision_fqdn}/swagger/index.html" }
output "nlp_api_url" { value = "https://${azurerm_container_app.nlp_api.latest_revision_fqdn}" }
output "nlp_swagger_url" { value = "https://${azurerm_container_app.nlp_api.latest_revision_fqdn}/swagger/index.html" }
output "nlp_api_fqdn" { value = azurerm_container_app.nlp_api.latest_revision_fqdn }
output "nlp_worker_container_app_name" { value = azurerm_container_app.nlp_worker.name }
output "nlp_worker_identity_client_id" { value = var.worker_identity_client_id }
output "container_apps_environment_id" { value = azurerm_container_app_environment.this.id }
output "database_migration_job_name" { value = azurerm_container_app_job.database_migration.name }
output "signalr_service_id" { value = try(azurerm_signalr_service.this[0].id, null) }
output "notification_hub_namespace_id" { value = try(azurerm_notification_hub_namespace.this[0].id, null) }
output "content_safety_account_id" { value = try(azurerm_cognitive_account.content_safety[0].id, null) }
output "openai_account_id" { value = try(azurerm_cognitive_account.openai[0].id, null) }
output "azure_openai_account_id" { value = try(azurerm_cognitive_account.openai[0].id, null) }
output "azure_openai_endpoint" { value = try(azurerm_cognitive_account.openai[0].endpoint, null) }
output "azure_openai_embedding_deployment_name" {
  value = var.enable_azure_openai ? azurerm_cognitive_deployment.embedding[0].name : null
}
