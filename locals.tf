locals {
  workload                     = "olga"
  suffix                       = substr(lower(replace("${var.environment}-${var.location}-${var.subscription_id}", "/[^0-9a-z]/", "")), 0, 16)
  resource_group               = "rg-${local.workload}-${var.environment}-${var.location}"
  github_environment           = var.environment == "prod" ? "prd" : var.environment
  core_deploy_oidc_subject     = "repo:${var.github_organization_subject}/${var.core_github_repository_subject}:environment:${local.github_environment}"
  nlp_deploy_oidc_subject      = "repo:${var.github_organization_subject}/${var.nlp_github_repository_subject}:environment:${local.github_environment}"
  database_deploy_oidc_subject = "repo:${var.github_organization_subject}/${var.database_github_repository_subject}:environment:${local.github_environment}"
  core_delivery_enabled        = var.use_acr_images || var.core_application_delivery_enabled
  nlp_delivery_enabled         = var.use_acr_images || var.nlp_application_delivery_enabled
  postgres_access              = try(var.postgres_access_by_environment[var.environment], null)
  tags = {
    product     = "olga-connect"
    environment = var.environment
    owner       = var.owner
    costCenter  = var.cost_center
    dataClass   = "confidential"
    expiryDate  = var.expiry_date
    managedBy   = "terraform"
  }
}
