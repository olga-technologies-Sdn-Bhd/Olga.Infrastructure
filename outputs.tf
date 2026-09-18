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

output "EXPO_PUBLIC_ENTRA_CLIENT_ID" {
  description = "Public native-client application ID for the active External ID environment."
  value       = var.external_identity.mobile_client_id
}

output "EXPO_PUBLIC_ENTRA_TENANT_ID" {
  description = "External tenant ID for the active environment."
  value       = var.external_identity.tenant_id
}

output "EXPO_PUBLIC_ENTRA_AUTHORITY" {
  description = "Microsoft Entra External ID authority used by the mobile public client."
  value       = "https://${var.external_identity.tenant_subdomain}.ciamlogin.com/"
}

output "EXPO_PUBLIC_ENTRA_REDIRECT_URI" {
  description = "Environment-specific native redirect URI registered on the matching mobile application."
  value       = var.external_identity.mobile_redirect_uri
}

output "EXPO_PUBLIC_OLGA_API_SCOPE" {
  description = "Delegated OLGA API scope requested by the matching mobile application."
  value       = "api://${var.external_identity.api_client_id}/access_as_user"
}

output "AzureAd__Instance" {
  description = "Future Core API Microsoft.Identity.Web instance; not currently connected to authentication middleware."
  value       = "https://${var.external_identity.tenant_subdomain}.ciamlogin.com/"
}

output "AzureAd__TenantId" {
  description = "Future Core API External ID tenant ID."
  value       = var.external_identity.tenant_id
}

output "AzureAd__ClientId" {
  description = "Future Core API application client ID."
  value       = var.external_identity.api_client_id
}

output "AzureAd__Audience" {
  description = "Future Core API access-token audience."
  value       = "api://${var.external_identity.api_client_id}"
}

output "AzureAd__RequiredScope" {
  description = "Future Core API delegated scope requirement."
  value       = "access_as_user"
}

output "AzureAd__Issuer" {
  description = "Future Core API v2 token issuer; confirm it against the environment's OpenID discovery metadata before enabling enforcement."
  value       = "https://${var.external_identity.tenant_id}.ciamlogin.com/${var.external_identity.tenant_id}/v2.0"
}
