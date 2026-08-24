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

output "managed_origin_record" {
  description = "Shared origin record details when managed by OpenTofu"
  value = var.manage_origin_record ? {
    id      = cloudflare_dns_record.origin[0].id
    name    = cloudflare_dns_record.origin[0].name
    type    = cloudflare_dns_record.origin[0].type
    proxied = cloudflare_dns_record.origin[0].proxied
    content = cloudflare_dns_record.origin[0].content
  } : null
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

output "access_policies_allow_admins" {
  description = "Shared allow-admins Access policy"
  value = {
    id   = cloudflare_zero_trust_access_policy.allow_admins.id
    name = cloudflare_zero_trust_access_policy.allow_admins.name
  }
}

output "access_policies_allow_approved" {
  description = "Shared allow-approved Access policy"
  value = {
    id   = cloudflare_zero_trust_access_policy.allow_approved.id
    name = cloudflare_zero_trust_access_policy.allow_approved.name
  }
}

output "access_policy_assignments" {
  description = "Policy names assigned per Access-managed service from canonical policy"
  value = {
    for name, svc in local.access_app_service_records : name => svc.access.policies
  }
}

output "identity_provider" {
  description = "Configured Zero Trust identity provider (if enabled)"
  value = length(cloudflare_zero_trust_access_identity_provider.main) > 0 ? {
    id   = cloudflare_zero_trust_access_identity_provider.main[0].id
    name = cloudflare_zero_trust_access_identity_provider.main[0].name
    type = cloudflare_zero_trust_access_identity_provider.main[0].type
  } : null
}

output "application_allowed_idps" {
  description = "Allowed IdP IDs configured per Access-managed application"
  value = {
    for name, app in cloudflare_zero_trust_access_application.service : name => app.allowed_idps
  }
}

# output "access_groups" {
#   description = "Cloudflare Zero Trust groups managed by OpenTofu"
#   value = {
#     for name, grp in cloudflare_zero_trust_access_group.service : name => {
#       id   = grp.id
#       name = grp.name
#     }
#   }
# }

output "aop_zone_enabled" {
  description = "Whether zone-level Authenticated Origin Pulls is enabled"
  value       = cloudflare_authenticated_origin_pulls_settings.this.enabled
}

output "zone_ssl_mode" {
  description = "Cloudflare zone SSL mode"
  value       = cloudflare_zone_setting.ssl.value
}

output "zone_always_use_https" {
  description = "Cloudflare zone Always Use HTTPS setting"
  value       = cloudflare_zone_setting.always_use_https.value
}

output "zone_security_rulesets" {
  description = "Zone-level firewall/WAF rulesets managed by OpenTofu"
  value = {
    managed_waf = {
      id      = cloudflare_ruleset.zone_firewall_managed.id
      phase   = cloudflare_ruleset.zone_firewall_managed.phase
      enabled = var.managed_waf_enabled
    }
    custom_firewall = {
      id      = cloudflare_ruleset.zone_firewall_custom.id
      phase   = cloudflare_ruleset.zone_firewall_custom.phase
      enabled = var.firewall_country_allowlist_enabled
    }
    rate_limit = {
      id      = cloudflare_ruleset.zone_rate_limit.id
      phase   = cloudflare_ruleset.zone_rate_limit.phase
      enabled = var.rate_limit_enabled
    }
  }
}

output "service_cache_bypass_ruleset" {
  description = "Combined service cache bypass ruleset metadata when any host-scoped bypass is enabled"
  value = length(cloudflare_ruleset.service_cache_bypass) > 0 ? {
    id                       = cloudflare_ruleset.service_cache_bypass[0].id
    phase                    = cloudflare_ruleset.service_cache_bypass[0].phase
    navidrome_bypass_enabled = var.navidrome_cache_bypass_enabled
  } : null
}
