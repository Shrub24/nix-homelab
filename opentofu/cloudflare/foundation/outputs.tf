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

output "machine_access_token" {
  description = "Cloudflare Access service token for machine clients; write it to secrets/services/gatus.yaml"
  sensitive   = true
  value = {
    client_id     = cloudflare_zero_trust_access_service_token.monitoring.client_id
    client_secret = cloudflare_zero_trust_access_service_token.monitoring.client_secret
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

output "service_access" {
  description = "Non-secret policy and identity references consumed by service publication"
  value = {
    policies = {
      allow_admins   = cloudflare_zero_trust_access_policy.allow_admins.id
      allow_approved = cloudflare_zero_trust_access_policy.allow_approved.id
      allow_users    = try(cloudflare_zero_trust_access_policy.allow_users[0].id, null)
      allow_machine  = cloudflare_zero_trust_access_policy.allow_machine.id
    }
    allowed_idps     = cloudflare_zero_trust_access_identity_provider.main[*].id
    session_duration = var.access_session_duration
  }
}
