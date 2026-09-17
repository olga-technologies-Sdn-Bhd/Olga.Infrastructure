# Example variable set for the OLGA Connect dev environment. Copy it to an ignored .auto.tfvars file for local use.
subscription_id     = "e0bb013f-a8af-4d60-9c5b-0140b361f257"
tenant_id           = "9972baa6-9591-43d7-8b13-59da8e6f1a72"
environment         = "dev"
location            = "malaysiawest"
owner               = "olga-platform"
cost_center         = "olga-connect"
expiry_date         = "2026-12-01"
budget_amount_usd   = 50
budget_alert_emails = ["sreedharan@ol-ga.com"]

# Enable only after the corresponding regional availability, quota, and product decisions are approved.
enable_azure_openai         = false
enable_api_management       = false
enable_admin_static_web_app = false
enable_content_safety       = false
enable_signalr              = false
enable_notification_hubs    = false
enable_service_bus          = false
