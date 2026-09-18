output "environment" {
  value = var.environment
}

output "tenant_id" {
  value = azapi_resource.external_tenant.output.properties.tenantId
}

output "tenant_subdomain" {
  value = var.tenant_subdomain
}

output "tenant_primary_domain" {
  value = "${var.tenant_subdomain}.onmicrosoft.com"
}

output "tenant_data_location" {
  value = var.tenant_data_location
}

output "tenant_authority" {
  value = "https://${var.tenant_subdomain}.ciamlogin.com/"
}

output "ciam_resource_id" {
  value = azapi_resource.external_tenant.id
}
