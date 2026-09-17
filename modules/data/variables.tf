variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "suffix" { type = string }
variable "tags" { type = map(string) }
variable "private_endpoint_subnet_id" { type = string }
variable "virtual_network_id" { type = string }
variable "postgres_admin_username" { type = string }
variable "postgres_admin_password" {
  type      = string
  sensitive = true
}
variable "postgres_sku_name" { type = string }
variable "postgres_storage_mb" { type = number }
variable "postgres_allowed_extensions" { type = list(string) }
variable "postgres_entra_admin" {
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })
  default  = null
  nullable = true
}
variable "postgres_firewall_rules" {
  type = map(object({
    start_ip_address = string
    end_ip_address   = string
  }))
  default = {}
}
variable "enable_service_bus" { type = bool }
variable "core_identity_principal_id" { type = string }
variable "nlp_identity_principal_id" { type = string }
variable "worker_identity_principal_id" { type = string }
variable "database_migration_identity_principal_id" { type = string }
