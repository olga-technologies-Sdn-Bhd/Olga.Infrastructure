locals {
  external_identity = {
    tenant_id             = var.external_tenant_id
    tenant_subdomain      = var.tenant_subdomain
    tenant_primary_domain = var.tenant_primary_domain
    location              = var.tenant_data_location
    mobile_redirect_uri   = var.mobile_redirect_uri
    mobile_client_id      = azuread_application_registration.mobile.client_id
    api_client_id         = azuread_application_registration.api.client_id
  }
}

output "external_identity" {
  description = "Object accepted by the main Terraform root."
  value       = local.external_identity
}

output "external_identity_json" {
  description = "Exact non-secret JSON value for the GitHub EXTERNAL_IDENTITY environment variable."
  value       = jsonencode(local.external_identity)
}

output "api_scope" {
  description = "Delegated scope requested by the mobile application."
  value       = "api://${azuread_application_registration.api.client_id}/${azuread_application_permission_scope.access_as_user.value}"
}

output "api_application_client_id" {
  value = azuread_application_registration.api.client_id
}

output "mobile_application_client_id" {
  value = azuread_application_registration.mobile.client_id
}

output "user_flow_id" {
  description = "Microsoft Graph identifier of the email OTP sign-up and sign-in user flow."
  value       = msgraph_resource.signup_signin_user_flow.output.id
}

output "user_flow_name" {
  value = msgraph_resource.signup_signin_user_flow.output.display_name
}
