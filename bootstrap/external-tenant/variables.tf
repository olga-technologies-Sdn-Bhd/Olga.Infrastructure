variable "subscription_id" {
  description = "Azure subscription used to create and bill the External ID tenant resource."
  type        = string
}

variable "management_tenant_id" {
  description = "Existing Entra tenant containing the Azure subscription and deployment identity."
  type        = string
}

variable "environment" {
  description = "External deployment environment name."
  type        = string

  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "environment must be dev or prd."
  }
}

variable "resource_group_location" {
  description = "Azure region for the resource group that owns the CIAM directory resource."
  type        = string
  default     = "malaysiawest"
}

variable "tenant_subdomain" {
  description = "Globally unique External ID tenant subdomain and CIAM resource name; letters and digits only."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{1,26}$", var.tenant_subdomain))
    error_message = "tenant_subdomain must contain 1-26 letters or digits; hyphens are not supported by this resource type."
  }
}

variable "tenant_display_name" {
  description = "Display name for the External ID tenant."
  type        = string

  validation {
    condition     = length(trimspace(var.tenant_display_name)) > 0
    error_message = "tenant_display_name must not be empty."
  }
}

variable "tenant_country_code" {
  description = "Two-letter country code used when creating the External ID tenant, for example MY."
  type        = string

  validation {
    condition     = can(regex("^[A-Z]{2}$", var.tenant_country_code))
    error_message = "tenant_country_code must be an uppercase two-letter country code."
  }
}

variable "tenant_data_location" {
  description = "External ID data location supported by the CIAM ARM resource."
  type        = string

  validation {
    condition     = contains(["United States", "Europe", "Asia Pacific", "Australia"], var.tenant_data_location)
    error_message = "tenant_data_location must be United States, Europe, Asia Pacific, or Australia."
  }
}

variable "owner" {
  description = "Owner tag applied to bootstrap resources."
  type        = string
}
