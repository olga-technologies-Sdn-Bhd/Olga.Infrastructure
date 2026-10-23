output "resource_group_name" {
  value = module.foundation.resource_group_name
}

output "container_registry" {
  value = module.foundation.acr_login_server
}

output "core_api_url" {
  description = "Stable HTTPS ingress URL for the Core API."
  value       = module.platform.core_api_url
}

output "core_swagger_url" {
  description = "Browser URL for the Core API Swagger UI."
  value       = module.platform.core_swagger_url
}

output "nlp_api_url" {
  description = "Stable HTTPS ingress URL for the NLP API."
  value       = module.platform.nlp_api_url
}

output "nlp_swagger_url" {
  description = "Browser URL for the NLP API Swagger UI."
  value       = module.platform.nlp_swagger_url
}

output "nlp_api_fqdn" {
  description = "Stable ingress FQDN for the NLP API."
  value       = module.platform.nlp_api_fqdn
}

output "nlp_worker_container_app_name" {
  value = module.platform.nlp_worker_container_app_name
}

output "nlp_worker_identity_client_id" {
  value = module.platform.nlp_worker_identity_client_id
}

output "core_worker_container_app_name" {
  description = "Dedicated Core worker Container App updated by the Core deployment workflow, or null when Service Bus is disabled."
  value       = module.platform.core_worker_container_app_name
}

output "core_worker_identity_client_id" {
  description = "User-assigned managed identity client ID used by the Core worker for Azure SDK authentication."
  value       = module.platform.core_worker_identity_client_id
}

output "servicebus_fully_qualified_namespace" {
  description = "Non-secret Service Bus namespace host supplied as ServiceBus__FullyQualifiedNamespace."
  value       = module.data.servicebus_fully_qualified_namespace
}

output "servicebus_integration_topic_name" {
  value = var.enable_service_bus ? "integration-events" : null
}

output "servicebus_core_nlp_completion_subscription_name" {
  value = var.enable_service_bus ? "core-nlp-completions" : null
}

output "servicebus_content_scan_queue_name" {
  value = var.enable_service_bus ? "content-scan" : null
}

output "storage_blob_endpoint" {
  description = "Private-network Blob service endpoint supplied to the Core API and Core worker."
  value       = module.data.storage_blob_endpoint
}

output "signalr_endpoint" {
  description = "Non-secret HTTPS SignalR endpoint, or null when enable_signalr is false."
  value       = module.platform.signalr_endpoint
}

output "notification_hub_namespace_name" {
  description = "Notification Hubs namespace name, or null when enable_notification_hubs is false."
  value       = module.platform.notification_hub_namespace_name
}

output "notification_hub_name" {
  description = "Notification Hub name, or null when enable_notification_hubs is false."
  value       = module.platform.notification_hub_name
}

output "notification_hub_send_connection_secret_uri" {
  description = "Non-secret Key Vault URI for the send-only Notification Hubs connection prepared for the later Core integration."
  value       = module.platform.notification_hub_send_connection_secret_uri
}

output "notification_hub_apns_key_vault_secret_name" {
  description = "Reserved Key Vault secret name for the manually protected APNS credential; no secret value is managed or output by Terraform."
  value       = var.enable_notification_hubs ? "notification-hubs-apns-credential" : null
}

output "notification_hub_fcm_v1_key_vault_secret_name" {
  description = "Reserved Key Vault secret name for the manually protected FCM v1 credential; no secret value is managed or output by Terraform."
  value       = var.enable_notification_hubs ? "notification-hubs-fcm-v1-credential" : null
}

output "admin_static_web_app_name" {
  description = "Azure Static Web App resource that hosts the admin portal, or null when disabled."
  value       = module.platform.admin_static_web_app_name
}

output "admin_static_web_app_default_host_name" {
  description = "Default admin portal hostname used for Entra SPA redirects and Core API CORS, or null when disabled."
  value       = module.platform.admin_static_web_app_default_host_name
}

output "admin_static_web_app_url" {
  description = "Default HTTPS URL for the admin portal, or null when disabled."
  value       = module.platform.admin_static_web_app_url
}

output "azure_openai_endpoint" {
  value = module.platform.azure_openai_endpoint
}

output "azure_openai_embedding_deployment_name" {
  value = module.platform.azure_openai_embedding_deployment_name
}

output "azure_openai_account_id" {
  value = module.platform.azure_openai_account_id
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
  description = "Core API Microsoft Entra External ID instance."
  value       = "https://${var.external_identity.tenant_subdomain}.ciamlogin.com/"
}

output "AzureAd__TenantId" {
  description = "Core API External ID tenant ID."
  value       = var.external_identity.tenant_id
}

output "AzureAd__ClientId" {
  description = "Core API application client ID."
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

output "AzureAd__RequiredRoles" {
  description = "Optional External ID application roles required by the Core API."
  value       = var.external_identity_required_roles
}

output "AzureAd__Issuer" {
  description = "Core API v2 token issuer; confirm it against the environment's OpenID discovery metadata before enabling enforcement."
  value       = "https://${var.external_identity.tenant_id}.ciamlogin.com/${var.external_identity.tenant_id}/v2.0"
}
