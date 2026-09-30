resource "azurerm_container_app_environment" "this" {
  name                       = "cae-olga-${var.environment}-${var.suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  infrastructure_subnet_id   = var.container_apps_subnet_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }
}

resource "azurerm_role_assignment" "core_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = var.core_identity_principal_id
}

resource "azurerm_role_assignment" "nlp_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = var.nlp_identity_principal_id
}

resource "azurerm_role_assignment" "nlp_worker_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = var.worker_identity_principal_id
}

resource "azurerm_role_assignment" "core_deploy_acr_push" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPush"
  principal_id                     = var.core_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "nlp_deploy_acr_push" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPush"
  principal_id                     = var.nlp_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "database_migration_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = var.database_migration_identity_principal_id
}

resource "azurerm_role_assignment" "database_deploy_acr_push" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPush"
  principal_id                     = var.database_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_container_app_job" "database_migration" {
  name                         = "job-olga-database-${var.environment}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 0
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.database_migration_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.database_migration_identity_id
  }

  secret {
    name                = "postgresql"
    key_vault_secret_id = var.postgres_connection_secret_uri
    identity            = var.database_migration_identity_id
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name    = "database-migration"
      image   = "mcr.microsoft.com/azurelinux/base/core:3.0"
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["/bin/sh", "-c"]
      args    = ["echo 'No migration image supplied; refusing to run.' >&2; exit 1"]

      env {
        name        = "OLGA_POSTGRES_CONNECTION_STRING"
        secret_name = "postgresql"
      }

      env {
        name  = "SEED_MVP_POLICIES"
        value = "0"
      }
    }
  }

  depends_on = [azurerm_role_assignment.database_migration_acr_pull]
}

resource "azurerm_role_assignment" "database_deploy_job" {
  scope                            = azurerm_container_app_job.database_migration.id
  role_definition_name             = "Container Apps Jobs Operator"
  principal_id                     = var.database_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_container_app" "core_api" {
  name                         = "ca-olga-core-api-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.core_identity_id]
  }

  secret {
    name                = "postgresql"
    key_vault_secret_id = var.postgres_connection_secret_uri
    identity            = var.core_identity_id
  }

  secret {
    name                = "service-token"
    key_vault_secret_id = var.service_token_secret_uri
    identity            = var.core_identity_id
  }

  secret {
    name                = "identity-protection-master-key"
    key_vault_secret_id = var.identity_master_key_secret_uri
    identity            = var.core_identity_id
  }

  dynamic "registry" {
    for_each = var.core_application_delivery_enabled ? [1] : []
    content {
      server   = var.acr_login_server
      identity = var.core_identity_id
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "core-api"
      image  = var.core_api_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = var.environment == "prod" ? "Production" : "Development"
      }
      env {
        name        = "ConnectionStrings__PostgreSql"
        secret_name = "postgresql"
      }
      env {
        name        = "ServiceAuthorization__Token"
        secret_name = "service-token"
      }
      env {
        name        = "IdentityProtection__MasterKeyBase64"
        secret_name = "identity-protection-master-key"
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.application_insights_connection_string
      }

      dynamic "liveness_probe" {
        for_each = var.core_health_probes_enabled ? [1] : []
        content {
          transport               = "HTTP"
          port                    = 8080
          path                    = "/health"
          initial_delay           = 10
          interval_seconds        = 30
          failure_count_threshold = 3
        }
      }

      dynamic "readiness_probe" {
        for_each = var.core_health_probes_enabled ? [1] : []
        content {
          transport               = "HTTP"
          port                    = 8080
          path                    = "/ready"
          initial_delay           = 10
          interval_seconds        = 10
          failure_count_threshold = 6
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.core_application_delivery_enabled ? 8080 : 80
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.core_acr_pull]
}

resource "azurerm_role_assignment" "core_deploy_container_app" {
  scope                            = azurerm_container_app.core_api.id
  role_definition_name             = "Container Apps Contributor"
  principal_id                     = var.core_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_container_app" "nlp_api" {
  name                         = "ca-olga-nlp-api-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.nlp_identity_id]
  }

  secret {
    name                = "postgresql"
    key_vault_secret_id = var.postgres_connection_secret_uri
    identity            = var.nlp_identity_id
  }

  secret {
    name                = "service-token"
    key_vault_secret_id = var.service_token_secret_uri
    identity            = var.nlp_identity_id
  }

  dynamic "registry" {
    for_each = var.nlp_application_delivery_enabled ? [1] : []
    content {
      server   = var.acr_login_server
      identity = var.nlp_identity_id
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "nlp-api"
      image  = var.nlp_api_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = var.environment == "prod" ? "Production" : "Development"
      }
      env {
        name  = "Hosting__AzureContainerAppsIngress"
        value = "true"
      }
      env {
        name        = "ConnectionStrings__PostgreSql"
        secret_name = "postgresql"
      }
      env {
        name        = "ServiceAuthorization__Token"
        secret_name = "service-token"
      }
      env {
        name  = "EmbeddingProvider"
        value = "Azure"
      }
      env {
        name  = "EmbeddingProcessing__Mode"
        value = "Queued"
      }
      env {
        name  = "AzureOpenAI__Endpoint"
        value = try(azurerm_cognitive_account.openai[0].endpoint, "")
      }
      env {
        name  = "AzureOpenAI__DeploymentName"
        value = var.azure_openai_embedding_deployment_name
      }
      env {
        name  = "AzureOpenAI__Dimensions"
        value = "1536"
      }
      env {
        name  = "AzureOpenAI__ManagedIdentityClientId"
        value = var.nlp_identity_client_id
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.application_insights_connection_string
      }

      dynamic "liveness_probe" {
        for_each = var.nlp_health_probes_enabled ? [1] : []
        content {
          transport               = "HTTP"
          port                    = 8080
          path                    = "/health"
          initial_delay           = 10
          interval_seconds        = 30
          failure_count_threshold = 3
        }
      }

      dynamic "readiness_probe" {
        for_each = var.nlp_health_probes_enabled ? [1] : []
        content {
          transport               = "HTTP"
          port                    = 8080
          path                    = "/ready"
          initial_delay           = 10
          interval_seconds        = 10
          failure_count_threshold = 6
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.nlp_application_delivery_enabled ? 8080 : 80
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.nlp_acr_pull,
    azurerm_role_assignment.nlp_openai_user,
    azurerm_cognitive_deployment.embedding,
    azurerm_private_endpoint.openai,
  ]
}

resource "azurerm_role_assignment" "nlp_deploy_container_app" {
  scope                            = azurerm_container_app.nlp_api.id
  role_definition_name             = "Container Apps Contributor"
  principal_id                     = var.nlp_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_container_app" "nlp_worker" {
  name                         = "ca-olga-nlp-worker-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.worker_identity_id]
  }

  secret {
    name                = "postgresql"
    key_vault_secret_id = var.postgres_connection_secret_uri
    identity            = var.worker_identity_id
  }

  dynamic "registry" {
    for_each = var.nlp_worker_application_delivery_enabled ? [1] : []
    content {
      server   = var.acr_login_server
      identity = var.worker_identity_id
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "nlp-worker"
      image  = var.nlp_worker_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "DOTNET_ENVIRONMENT"
        value = var.environment == "prod" ? "Production" : "Development"
      }
      env {
        name        = "ConnectionStrings__PostgreSql"
        secret_name = "postgresql"
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.application_insights_connection_string
      }
      env {
        name  = "EmbeddingProvider"
        value = "Azure"
      }
      env {
        name  = "AzureOpenAI__Endpoint"
        value = try(azurerm_cognitive_account.openai[0].endpoint, "")
      }
      env {
        name  = "AzureOpenAI__DeploymentName"
        value = var.azure_openai_embedding_deployment_name
      }
      env {
        name  = "AzureOpenAI__Model"
        value = "text-embedding-3-small"
      }
      env {
        name  = "AzureOpenAI__Dimensions"
        value = "1536"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = var.worker_identity_client_id
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.nlp_worker_acr_pull,
    azurerm_role_assignment.nlp_worker_openai_user,
    azurerm_cognitive_deployment.embedding,
    azurerm_private_endpoint.openai,
  ]
}

resource "azurerm_role_assignment" "nlp_deploy_worker_container_app" {
  scope                            = azurerm_container_app.nlp_worker.id
  role_definition_name             = "Container Apps Contributor"
  principal_id                     = var.nlp_deploy_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_signalr_service" "this" {
  count = var.enable_signalr ? 1 : 0

  name                          = "sigr-olga-${var.suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = true
  connectivity_logs_enabled     = true
  messaging_logs_enabled        = true
  service_mode                  = "Default"
  tags                          = var.tags

  sku {
    name     = "Free_F1"
    capacity = 1
  }
}

resource "azurerm_notification_hub_namespace" "this" {
  count = var.enable_notification_hubs ? 1 : 0

  name                = "nhns-olga-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  namespace_type      = "NotificationHub"
  sku_name            = "Free"
  tags                = var.tags
}

resource "azurerm_notification_hub" "this" {
  count = var.enable_notification_hubs ? 1 : 0

  name                = "nh-olga-${var.environment}"
  namespace_name      = azurerm_notification_hub_namespace.this[0].name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_cognitive_account" "content_safety" {
  count = var.enable_content_safety ? 1 : 0

  name                          = "cs-olga-${var.suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "ContentSafety"
  sku_name                      = "F0"
  custom_subdomain_name         = "cs-olga-${var.suffix}"
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_cognitive_account" "openai" {
  count = var.enable_azure_openai ? 1 : 0

  name                          = "aoai-olga-${var.suffix}"
  location                      = var.azure_openai_location
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = "aoai-olga-${var.suffix}"
  local_auth_enabled            = false
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_cognitive_deployment" "embedding" {
  count = var.enable_azure_openai ? 1 : 0

  name                 = var.azure_openai_embedding_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-small"
    version = var.azure_openai_model_version
  }

  sku {
    name     = "Standard"
    capacity = var.azure_openai_embedding_capacity
  }
}

resource "azurerm_private_dns_zone" "openai" {
  count = var.enable_azure_openai ? 1 : 0

  name                = "privatelink.openai.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  count = var.enable_azure_openai ? 1 : 0

  name                  = "link-openai-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.openai[0].name
  virtual_network_id    = var.virtual_network_id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "openai" {
  count = var.enable_azure_openai ? 1 : 0

  name                = "pe-aoai-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-aoai"
    private_connection_resource_id = azurerm_cognitive_account.openai[0].id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "openai"
    private_dns_zone_ids = [azurerm_private_dns_zone.openai[0].id]
  }

  # Cognitive account creation can return while Azure still reports the
  # provisioning state as Accepted. The successful model deployment proves
  # the account data plane is ready; the DNS link also completes before the
  # endpoint is attached, avoiding the initial control-plane race.
  depends_on = [
    azurerm_cognitive_deployment.embedding,
    azurerm_private_dns_zone_virtual_network_link.openai,
  ]
}

resource "azurerm_role_assignment" "nlp_openai_user" {
  count = var.enable_azure_openai ? 1 : 0

  scope                = azurerm_cognitive_account.openai[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.nlp_identity_principal_id
}

resource "azurerm_role_assignment" "nlp_worker_openai_user" {
  count = var.enable_azure_openai ? 1 : 0

  scope                = azurerm_cognitive_account.openai[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.worker_identity_principal_id
}

resource "azurerm_api_management" "this" {
  count = var.enable_api_management ? 1 : 0

  name                = "apim-olga-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "Consumption_0"
  tags                = var.tags
}

resource "azurerm_static_web_app" "admin" {
  count = var.enable_admin_static_web_app ? 1 : 0

  name                = "stapp-olga-admin-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = var.tags
}
