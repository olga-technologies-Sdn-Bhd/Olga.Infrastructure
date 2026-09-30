module "foundation" {
  source = "./modules/foundation"

  resource_group_name          = local.resource_group
  location                     = var.location
  environment                  = var.environment
  suffix                       = local.suffix
  tags                         = local.tags
  budget_amount_usd            = var.budget_amount_usd
  budget_alert_emails          = var.budget_alert_emails
  expiry_date                  = var.expiry_date
  core_deploy_oidc_subject     = local.core_deploy_oidc_subject
  nlp_deploy_oidc_subject      = local.nlp_deploy_oidc_subject
  database_deploy_oidc_subject = local.database_deploy_oidc_subject
}

# Contributor supplies control-plane administration across every module in this
# environment. Azure service data planes use separate assignments below.
resource "azurerm_role_assignment" "platform_administrator_contributor" {
  for_each = local.platform_administrator_principal_ids

  scope                = module.foundation.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_monitoring_reader" {
  for_each = local.platform_administrator_principal_ids

  scope                = module.foundation.resource_group_id
  role_definition_name = "Monitoring Reader"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_acr_push" {
  for_each = local.platform_administrator_principal_ids

  scope                = module.foundation.acr_id
  role_definition_name = "AcrPush"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_acr_delete" {
  for_each = local.platform_administrator_principal_ids

  scope                = module.foundation.acr_id
  role_definition_name = "AcrDelete"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_key_vault" {
  for_each = local.platform_administrator_principal_ids

  scope                = module.data.key_vault_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_blob_data" {
  for_each = local.platform_administrator_principal_ids

  scope                = module.data.storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_servicebus_data" {
  for_each = var.enable_service_bus ? local.platform_administrator_principal_ids : toset([])

  scope                = module.data.servicebus_namespace_id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_content_safety" {
  for_each = var.enable_content_safety ? local.platform_administrator_principal_ids : toset([])

  scope                = module.platform.content_safety_account_id
  role_definition_name = "Cognitive Services User"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_openai" {
  for_each = var.enable_azure_openai ? local.platform_administrator_principal_ids : toset([])

  scope                = module.platform.openai_account_id
  role_definition_name = "Cognitive Services OpenAI Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_signalr" {
  for_each = var.enable_signalr ? local.platform_administrator_principal_ids : toset([])

  scope                = module.platform.signalr_service_id
  role_definition_name = "SignalR Service Owner"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "platform_administrator_notification_hubs" {
  for_each = var.enable_notification_hubs ? local.platform_administrator_principal_ids : toset([])

  scope                = module.platform.notification_hub_namespace_id
  role_definition_name = "Azure Notification Hubs Data Owner"
  principal_id         = each.value
}

module "network" {
  source = "./modules/network"

  resource_group_name = module.foundation.resource_group_name
  location            = var.location
  environment         = var.environment
  tags                = local.tags
}

module "data" {
  source = "./modules/data"

  resource_group_name                      = module.foundation.resource_group_name
  location                                 = var.location
  environment                              = var.environment
  suffix                                   = local.suffix
  tags                                     = local.tags
  private_endpoint_subnet_id               = module.network.private_endpoint_subnet_id
  virtual_network_id                       = module.network.virtual_network_id
  postgres_admin_username                  = var.postgres_admin_username
  postgres_admin_password                  = module.foundation.postgres_admin_password
  postgres_connection_string_override      = var.environment == "dev" ? var.postgres_connection_string_override : null
  postgres_sku_name                        = var.postgres_sku_name
  postgres_storage_mb                      = var.postgres_storage_mb
  postgres_allowed_extensions              = var.postgres_allowed_extensions
  postgres_entra_admin                     = try(local.postgres_access.entra_admin, null)
  postgres_firewall_rules                  = try(local.postgres_access.firewall_rules, {})
  enable_service_bus                       = var.enable_service_bus
  core_identity_principal_id               = module.foundation.core_identity_principal_id
  nlp_identity_principal_id                = module.foundation.nlp_identity_principal_id
  worker_identity_principal_id             = module.foundation.worker_identity_principal_id
  database_migration_identity_principal_id = module.foundation.database_migration_identity_principal_id
}

module "platform" {
  source     = "./modules/platform"
  depends_on = [module.data]

  resource_group_name                      = module.foundation.resource_group_name
  location                                 = var.location
  environment                              = var.environment
  suffix                                   = local.suffix
  tags                                     = local.tags
  container_apps_subnet_id                 = module.network.container_apps_subnet_id
  private_endpoint_subnet_id               = module.network.private_endpoint_subnet_id
  virtual_network_id                       = module.network.virtual_network_id
  log_analytics_workspace_id               = module.foundation.log_analytics_workspace_id
  application_insights_connection_string   = module.foundation.application_insights_connection_string
  acr_id                                   = module.foundation.acr_id
  acr_login_server                         = module.foundation.acr_login_server
  postgres_connection_secret_uri           = module.data.postgres_connection_secret_uri
  service_token_secret_uri                 = module.data.service_token_secret_uri
  identity_master_key_secret_uri           = module.data.identity_master_key_secret_uri
  core_identity_id                         = module.foundation.core_identity_id
  core_identity_principal_id               = module.foundation.core_identity_principal_id
  nlp_identity_id                          = module.foundation.nlp_identity_id
  nlp_identity_client_id                   = module.foundation.nlp_identity_client_id
  nlp_identity_principal_id                = module.foundation.nlp_identity_principal_id
  worker_identity_id                       = module.foundation.worker_identity_id
  worker_identity_client_id                = module.foundation.worker_identity_client_id
  worker_identity_principal_id             = module.foundation.worker_identity_principal_id
  core_deploy_identity_principal_id        = module.foundation.core_deploy_identity_principal_id
  nlp_deploy_identity_principal_id         = module.foundation.nlp_deploy_identity_principal_id
  database_migration_identity_id           = module.foundation.database_migration_identity_id
  database_migration_identity_principal_id = module.foundation.database_migration_identity_principal_id
  database_deploy_identity_principal_id    = module.foundation.database_deploy_identity_principal_id
  core_api_image                           = var.core_api_image
  nlp_api_image                            = var.nlp_api_image
  nlp_worker_image                         = var.nlp_worker_image
  core_application_delivery_enabled        = local.core_delivery_enabled
  core_health_probes_enabled               = var.core_health_probes_enabled
  nlp_application_delivery_enabled         = local.nlp_delivery_enabled
  nlp_worker_application_delivery_enabled  = var.nlp_worker_application_delivery_enabled
  nlp_health_probes_enabled                = var.nlp_health_probes_enabled
  enable_api_management                    = var.enable_api_management
  apim_publisher_name                      = var.apim_publisher_name
  apim_publisher_email                     = var.apim_publisher_email
  enable_admin_static_web_app              = var.enable_admin_static_web_app
  enable_azure_openai                      = var.enable_azure_openai
  azure_openai_location                    = var.azure_openai_location
  azure_openai_model_version               = var.azure_openai_model_version
  azure_openai_embedding_deployment_name   = var.azure_openai_embedding_deployment_name
  azure_openai_embedding_capacity          = var.azure_openai_embedding_capacity
  enable_content_safety                    = var.enable_content_safety
  enable_signalr                           = var.enable_signalr
  enable_notification_hubs                 = var.enable_notification_hubs
}
