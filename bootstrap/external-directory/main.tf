data "azuread_client_config" "current" {}

locals {
  api_display_name    = "olga_api_${var.environment}"
  mobile_display_name = "olga_mobile_${var.environment}"
}

resource "random_uuid" "access_as_user_scope" {}

resource "azuread_application_registration" "api" {
  display_name                   = local.api_display_name
  description                    = "OLGA ${var.environment} API"
  sign_in_audience               = "AzureADMyOrg"
  requested_access_token_version = 2

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application_owner" "api" {
  application_id  = azuread_application_registration.api.id
  owner_object_id = data.azuread_client_config.current.object_id
}

resource "azuread_application_identifier_uri" "api" {
  application_id = azuread_application_registration.api.id
  identifier_uri = "api://${azuread_application_registration.api.client_id}"
}

resource "azuread_application_permission_scope" "access_as_user" {
  application_id = azuread_application_registration.api.id
  scope_id       = random_uuid.access_as_user_scope.result
  value          = "access_as_user"
  type           = "User"

  admin_consent_description  = "Allow this application to access OLGA as the signed-in user."
  admin_consent_display_name = "Access OLGA as the signed-in user"
  user_consent_description   = "Allow this application to access OLGA on your behalf."
  user_consent_display_name  = "Access OLGA on your behalf"
}

resource "azuread_service_principal" "api" {
  client_id                    = azuread_application_registration.api.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_registration" "mobile" {
  display_name     = local.mobile_display_name
  description      = "OLGA ${var.environment} public mobile application"
  sign_in_audience = "AzureADMyOrg"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application_owner" "mobile" {
  application_id  = azuread_application_registration.mobile.id
  owner_object_id = data.azuread_client_config.current.object_id
}

resource "azuread_application_redirect_uris" "mobile" {
  application_id = azuread_application_registration.mobile.id
  type           = "PublicClient"
  redirect_uris  = [var.mobile_redirect_uri]
}

resource "azuread_application_api_access" "mobile_api" {
  application_id = azuread_application_registration.mobile.id
  api_client_id  = azuread_application_registration.api.client_id
  scope_ids      = [azuread_application_permission_scope.access_as_user.scope_id]
}

resource "azuread_application_pre_authorized" "mobile" {
  application_id       = azuread_application_registration.api.id
  authorized_client_id = azuread_application_registration.mobile.client_id
  permission_ids       = [azuread_application_permission_scope.access_as_user.scope_id]
}

resource "azuread_service_principal" "mobile" {
  client_id                    = azuread_application_registration.mobile.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_delegated_permission_grant" "mobile_api" {
  service_principal_object_id          = azuread_service_principal.mobile.object_id
  resource_service_principal_object_id = azuread_service_principal.api.object_id
  claim_values                         = [azuread_application_permission_scope.access_as_user.value]
}

resource "msgraph_resource" "signup_signin_user_flow" {
  url         = "identity/authenticationEventsFlows"
  api_version = "v1.0"

  body = {
    "@odata.type" = "#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow"
    displayName   = "olga_signup_signin_${var.environment}"
    description   = "OLGA ${var.environment} customer email OTP sign-up and sign-in"
    conditions = {
      applications = {
        includeApplications = [
          {
            appId = azuread_application_registration.mobile.client_id
          }
        ]
      }
    }
    onAuthenticationMethodLoadStart = {
      "@odata.type" = "#microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp"
      identityProviders = [
        {
          id = "EmailOtpSignup-OAUTH"
        }
      ]
    }
    onInteractiveAuthFlowStart = {
      "@odata.type"   = "#microsoft.graph.onInteractiveAuthFlowStartExternalUsersSelfServiceSignUp"
      isSignUpAllowed = true
    }
    onAttributeCollection = {
      "@odata.type" = "#microsoft.graph.onAttributeCollectionExternalUsersSelfServiceSignUp"
      attributes = [
        {
          id                    = "email"
          displayName           = "Email Address"
          description           = "Email address of the user"
          userFlowAttributeType = "builtIn"
          dataType              = "string"
        },
        {
          id                    = "displayName"
          displayName           = "Display Name"
          description           = "Display name of the user"
          userFlowAttributeType = "builtIn"
          dataType              = "string"
        }
      ]
      attributeCollectionPage = {
        views = [
          {
            inputs = [
              {
                attribute        = "email"
                label            = "Email Address"
                inputType        = "text"
                hidden           = true
                editable         = false
                writeToDirectory = true
                required         = true
                validationRegEx  = "^.+@.+\\..+$"
              },
              {
                attribute        = "displayName"
                label            = "Display Name"
                inputType        = "text"
                hidden           = false
                editable         = true
                writeToDirectory = true
                required         = false
                validationRegEx  = "^[a-zA-Z_][0-9a-zA-Z_ ]*[0-9a-zA-Z_]+$"
              }
            ]
          }
        ]
      }
    }
  }

  response_export_values = {
    id           = "id"
    display_name = "displayName"
  }

  lifecycle {
    prevent_destroy = true
  }
}
