output "managed_service_dns_records" {
  description = "Managed service DNS records derived from canonical policy"
  value = {
    for name, rec in cloudflare_dns_record.service : name => {
      name    = rec.name
      proxied = rec.proxied
      type    = rec.type
    }
  }
}

output "managed_service_names" {
  description = "Service keys currently managed as Cloudflare DNS records"
  value       = sort(keys(cloudflare_dns_record.service))
}

output "access_applications" {
  description = "Cloudflare Zero Trust Access applications managed for access-protected services"
  value = {
    for name, app in cloudflare_zero_trust_access_application.service : name => {
      id     = app.id
      name   = app.name
      domain = app.domain
    }
  }
}

output "access_policy_assignments" {
  description = "Policy names assigned per Access-managed service from canonical policy"
  value = {
    for name, svc in local.access_app_service_records : name => concat(svc.access.policies, ["allow_machine"])
  }
}

output "application_allowed_idps" {
  description = "Allowed IdP IDs configured per Access-managed application"
  value = {
    for name, app in cloudflare_zero_trust_access_application.service : name => app.allowed_idps
  }
}
