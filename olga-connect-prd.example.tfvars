# Azure OpenAI and NLP application delivery inputs for production.
# Combine with environments/prd.external-identity.tfvars.example and the
# required subscription, ownership, budget, and image values for a full plan.
environment = "prod"
location    = "malaysiawest"

enable_admin_static_web_app   = true
admin_static_web_app_location = "eastasia"
admin_static_web_app_sku_tier = "Standard"

enable_azure_openai                    = true
azure_openai_location                  = "australiaeast"
azure_openai_model_version             = "1"
nlp_model_version                      = "azure-text-embedding-3-small-1536-v1"
azure_openai_embedding_deployment_name = "text-embedding-3-small"
azure_openai_embedding_capacity        = 10

nlp_application_delivery_enabled        = true
nlp_worker_application_delivery_enabled = true
core_api_min_replicas                   = 2
core_worker_min_replicas                = 2
nlp_api_min_replicas                    = 2

postgres_prod_sku_name                     = "GP_Standard_D2ds_v5"
postgres_prod_storage_mb                   = 131072
postgres_prod_geo_redundant_backup_enabled = false

# Service Bus and the Core worker are required for production. SignalR and
# Notification Hubs stay off until their application integrations are released;
# setting either to true is an explicit cost-bearing production decision.
enable_service_bus       = true
enable_signalr           = true
enable_notification_hubs = true

# Content Safety is not enabled until the Core worker consumes and enforces its
# verdicts; local image validation alone is not an attachment-safety boundary.
enable_content_safety = true

# Set true only for a Core image that validates External ID access tokens and
# rejects X-Member-Id/default-member identity selection. Production is blocked otherwise.
core_authentication_enforced = false
