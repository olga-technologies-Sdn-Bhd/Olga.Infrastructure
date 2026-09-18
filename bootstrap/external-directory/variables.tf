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
