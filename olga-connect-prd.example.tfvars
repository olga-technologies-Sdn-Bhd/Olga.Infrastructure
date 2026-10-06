# Azure OpenAI and NLP application delivery inputs for production.
# Combine with environments/prd.external-identity.tfvars.example and the
# required subscription, ownership, budget, and image values for a full plan.
environment = "prod"
location    = "malaysiawest"

enable_azure_openai                    = true
azure_openai_location                  = "australiaeast"
azure_openai_model_version             = "1"
nlp_model_version                      = "azure-text-embedding-3-small-1536-v1"
azure_openai_embedding_deployment_name = "text-embedding-3-small"
azure_openai_embedding_capacity        = 10

nlp_application_delivery_enabled        = true
nlp_worker_application_delivery_enabled = true
core_api_min_replicas                   = 2
nlp_api_min_replicas                    = 2

postgres_prod_sku_name   = "GP_Standard_D2ds_v5"
postgres_prod_storage_mb = 131072

enable_service_bus = false
