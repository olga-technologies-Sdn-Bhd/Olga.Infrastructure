output "resource_group_name" {
  value = module.foundation.resource_group_name
}

output "container_registry" {
  value = module.foundation.acr_login_server
}

output "core_api_url" {
  value = module.platform.core_api_url
}

output "core_swagger_url" {
  description = "Browser URL for the Core API Swagger UI."
  value       = module.platform.core_swagger_url
}

output "nlp_api_url" {
  value = module.platform.nlp_api_url
}

output "nlp_swagger_url" {
  description = "Browser URL for the NLP API Swagger UI."
  value       = module.platform.nlp_swagger_url
}

output "nlp_api_fqdn" {
  value = module.platform.nlp_api_fqdn
}

output "postgres_server_fqdn" {
  value = module.data.postgres_server_fqdn
}

output "postgres_database_name" {
  value = module.data.postgres_database_name
}

output "key_vault_uri" {
  value = module.data.key_vault_uri
}

output "postgres_migration_connection_secret_uri" {
  description = "Versionless Key Vault URI for the migration-administrator connection secret."
  value       = module.data.postgres_migration_connection_secret_uri
}

output "postgres_dml_connection_secret_uri" {
  description = "Versionless Key Vault URI for the runtime DML connection secret."
  value       = module.data.postgres_dml_connection_secret_uri
}

output "core_deployment_identity_client_id" {
  description = "Set this as AZURE_CLIENT_ID in the Core repository GitHub environment."
  value       = module.foundation.core_deploy_identity_client_id
}

output "core_deployment_oidc_subject" {
  value = local.core_deploy_oidc_subject
}

output "nlp_deployment_identity_client_id" {
  description = "Set this as AZURE_CLIENT_ID in the NLP repository GitHub environment."
  value       = module.foundation.nlp_deploy_identity_client_id
}

output "nlp_deployment_oidc_subject" {
  value = local.nlp_deploy_oidc_subject
}

output "database_migration_job_name" {
  description = "Container Apps Job started by the database deployment workflow."
  value       = module.platform.database_migration_job_name
}

output "database_deployment_identity_client_id" {
  description = "Set this as AZURE_CLIENT_ID in the database repository GitHub environment."
  value       = module.foundation.database_deploy_identity_client_id
}

output "database_deployment_oidc_subject" {
  value = local.database_deploy_oidc_subject
}
