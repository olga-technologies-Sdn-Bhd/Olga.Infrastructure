variable "environment" {
  description = "External environment name. Production deliberately uses prd here."
  type        = string

  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "environment must be dev or prd."
  }
}

variable "external_tenant_id" {
  description = "Tenant ID returned by bootstrap/external-tenant."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.external_tenant_id))
    error_message = "external_tenant_id must be a UUID."
  }
}

variable "external_directory_client_id" {
  description = "Optional client ID of the environment-specific GitHub OIDC application in the external tenant. Required only when use_oidc is true."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.external_directory_client_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.external_directory_client_id))
    error_message = "external_directory_client_id must be null or a UUID."
  }
}

variable "use_oidc" {
  description = "Use workload identity federation for non-interactive directory deployment. Local delegated administration remains the default."
  type        = bool
  default     = false

  validation {
    condition     = !var.use_oidc || var.external_directory_client_id != null
    error_message = "external_directory_client_id is required when use_oidc is true."
  }
}

variable "google_identity_provider_id" {
  description = "Optional non-secret Microsoft Graph object ID of the Google identity provider in this external tenant. The Google client secret must never be passed to Terraform."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.google_identity_provider_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.google_identity_provider_id))
    error_message = "google_identity_provider_id must be null or a UUID returned by the Google identity-provider bootstrap for this environment's external tenant."
  }
}

variable "apple_identity_provider_id" {
  description = "Optional non-secret Microsoft Graph object ID of the Apple identity provider in this external tenant. The Apple private key must never be passed to Terraform."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.apple_identity_provider_id == null || var.apple_identity_provider_id == "Apple-Managed-OIDC"
    error_message = "apple_identity_provider_id must be null or Apple-Managed-OIDC as returned by the Apple identity-provider bootstrap."
  }
}

variable "tenant_subdomain" {
  description = "External tenant subdomain without onmicrosoft.com."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.tenant_subdomain))
    error_message = "tenant_subdomain must be a valid lowercase tenant subdomain."
  }
}

variable "tenant_primary_domain" {
  description = "Primary onmicrosoft.com domain of the external tenant."
  type        = string

  validation {
    condition     = var.tenant_primary_domain == "${var.tenant_subdomain}.onmicrosoft.com"
    error_message = "tenant_primary_domain must match tenant_subdomain.onmicrosoft.com."
  }
}

variable "tenant_data_location" {
  description = "External tenant data location returned by the tenant bootstrap."
  type        = string

  validation {
    condition     = length(trimspace(var.tenant_data_location)) > 0
    error_message = "tenant_data_location must not be empty."
  }
}

variable "mobile_redirect_uri" {
  description = "Exact native callback URI claimed by the matching mobile application."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9+.-]*://.+$", var.mobile_redirect_uri))
    error_message = "mobile_redirect_uri must be an absolute URI with a scheme."
  }
}
