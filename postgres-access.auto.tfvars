# Non-secret PostgreSQL administrator access shared by local and GitHub Terraform runs.
# Each firewall rule is deliberately a single public IPv4 address. Update the
# relevant environment entry and apply Terraform when the administrator IP changes.
postgres_access_by_environment = {
  dev = {
    entra_admin = {
      object_id      = "12cb9c4b-2756-4084-9298-0ad4ebb0a06a"
      principal_name = "sreedharan_ol-ga.com#EXT#@sreedharanolga.onmicrosoft.com"
      principal_type = "User"
    }
    firewall_rules = {
      sreedharan_dbeaver = {
        start_ip_address = "49.43.231.239"
        end_ip_address   = "49.43.231.239"
      }
    }
  }

  prod = {
    entra_admin = {
      object_id      = "12cb9c4b-2756-4084-9298-0ad4ebb0a06a"
      principal_name = "sreedharan_ol-ga.com#EXT#@sreedharanolga.onmicrosoft.com"
      principal_type = "User"
    }
    firewall_rules = {
      sreedharan_dbeaver = {
        start_ip_address = "49.43.231.239"
        end_ip_address   = "49.43.231.239"
      }
    }
  }
}
