# Azure OpenAI and NLP application delivery inputs for production.
# Combine with environments/prd.external-identity.tfvars.example and the
# required subscription, ownership, budget, and image values for a full plan.
environment = "prod"
location    = "malaysiawest"

enable_azure_openai                     = true
azure_openai_location                   = "australiaeast"
azure_openai_model_version              = "1"
azure_openai_embedding_deployment_name = "text-embedding-3-small"
azure_openai_embedding_capacity        = 10

nlp_application_delivery_enabled        = true
nlp_worker_application_delivery_enabled = true

enable_service_bus = false
