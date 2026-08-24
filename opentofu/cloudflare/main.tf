terraform {
  required_version = ">= 1.6.0"

  backend "s3" {}

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }
}

locals {
  web_services_policy = jsondecode(file("../../generated/policy/web-services.json"))
  cloudflare_hosts    = try(local.web_services_policy.cloudflare.hosts, {})
  web_service_routes  = try(local.web_services_policy.routes, local.web_services_policy)

  # All declared-public, non-tailscale-only public hosts get one DNS record.
  public_service_records = local.cloudflare_hosts

  # Public hosts that need a Cloudflare Access application.
  # access = null/absent → no Access app (e.g. navidrome, vaultwarden).
  access_app_service_records = {
    for public_host, host in local.public_service_records : public_host => host
    if try(host.access.requireCloudflareAccess, false) == true
  }

  policy_resources_by_name = {
    allow_admins   = cloudflare_zero_trust_access_policy.allow_admins.id
    allow_approved = cloudflare_zero_trust_access_policy.allow_approved.id
  }

  firewall_allowed_countries_expression = length(var.firewall_allowed_countries) > 0 ? format(
    "ip.geoip.country in {%s}",
    join(" ", [for cc in var.firewall_allowed_countries : format("\"%s\"", upper(cc))])
  ) : "ip.geoip.country in {\"__none__\"}"

  navidrome_service = try(local.web_service_routes.navidrome, null)
  navidrome_host    = local.navidrome_service != null ? local.navidrome_service.publicHost : null

  cache_bypass_rules = (var.navidrome_cache_bypass_enabled && local.navidrome_host != null) ? [
    {
      ref         = "navidrome_bypass_cache"
      description = "Disable cache for Navidrome host"
      expression  = format("http.host eq \"%s\"", local.navidrome_host)
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = false
      }
    }
  ] : []

}

# ---------------------------------------------------------------------------
# DNS records
# ---------------------------------------------------------------------------

resource "cloudflare_dns_record" "service" {
  for_each = local.public_service_records

  zone_id = var.cloudflare_zone_id
  name    = each.value.hostname
  type    = var.dns_record_type
  ttl     = 1
  content = var.edge_record_target
  proxied = try(each.value.proxied, true)

  comment = "Managed by OpenTofu from policy/web-services.nix"
}

resource "cloudflare_dns_record" "origin" {
  count = var.manage_origin_record ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.origin_record_name
  type    = var.origin_record_type
  ttl     = 1
  content = var.origin_record_content
  proxied = var.origin_record_proxied

  comment = "Managed by OpenTofu as shared origin endpoint"
}

# ---------------------------------------------------------------------------
# Zero Trust groups
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Access applications
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "service" {
  for_each = local.access_app_service_records

  account_id = var.cloudflare_account_id
  name       = each.value.publicHost
  domain     = each.value.publicHost
  type       = "self_hosted"

  policies = [
    for idx, policy_name in each.value.access.policies : {
      id         = local.policy_resources_by_name[policy_name]
      precedence = idx + 1
    }
  ]

  allowed_idps = length(cloudflare_zero_trust_access_identity_provider.main) > 0 ? [
    cloudflare_zero_trust_access_identity_provider.main[0].id
  ] : null

  app_launcher_visible     = false
  enable_binding_cookie    = false
  options_preflight_bypass = false

  session_duration          = var.access_session_duration
  auto_redirect_to_identity = true
}

# ---------------------------------------------------------------------------
# Access policies (standalone, reusable across applications)
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_policy" "allow_admins" {
  account_id = var.cloudflare_account_id
  name       = "allow_admins"
  decision   = "allow"

  include = [
    { email = { email = var.admin_email } }
  ]

  session_duration = var.access_session_duration
}

resource "cloudflare_zero_trust_access_policy" "allow_approved" {
  account_id = var.cloudflare_account_id
  name       = "allow_approved"
  decision   = "allow"

  purpose_justification_required = true
  purpose_justification_prompt   = "Who are you and why do you want access to my homelab?"
  approval_required              = true

  include = [
    { geo = { country_code = "AU" } },
    { geo = { country_code = "GB" } },
  ]

  approval_groups = [{
    approvals_needed = 1
    email_addresses  = [var.admin_email]
  }]

  session_duration = var.temp_access_session_duration
}

# ---------------------------------------------------------------------------
# Global zone-level AOP
# ---------------------------------------------------------------------------

resource "cloudflare_authenticated_origin_pulls_settings" "this" {
  zone_id = var.cloudflare_zone_id
  enabled = var.aop_enabled
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# ---------------------------------------------------------------------------
# Zero Trust Identity Provider
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_identity_provider" "main" {
  count      = var.idp_client_id != null ? 1 : 0
  name       = var.idp_name
  type       = var.idp_type
  account_id = var.cloudflare_account_id

  config = {
    pkce_enabled  = true
    client_id     = var.idp_client_id
    client_secret = var.idp_client_secret
    auth_url      = var.idp_auth_url
    token_url     = var.idp_token_url
    certs_url     = var.idp_certs_url
  }
}

# ---------------------------------------------------------------------------
# Cloudflare security and cache controls
# ---------------------------------------------------------------------------

resource "cloudflare_ruleset" "zone_firewall_managed" {
  zone_id     = var.cloudflare_zone_id
  name        = "zone-managed-waf"
  description = "Execute managed WAF ruleset zone-wide"
  phase       = "http_request_firewall_managed"
  kind        = "zone"

  rules = [{
    ref         = "execute_managed_waf"
    description = "Execute managed WAF for all requests in this zone"
    expression  = "true"
    action      = "execute"
    enabled     = var.managed_waf_enabled
    action_parameters = {
      id = "77454fe2d30c4220b5701f6fdfb893ba"
    }
  }]
}

resource "cloudflare_ruleset" "zone_firewall_custom" {
  zone_id     = var.cloudflare_zone_id
  name        = "zone-custom-firewall"
  description = "Custom firewall controls zone-wide"
  phase       = "http_request_firewall_custom"
  kind        = "zone"

  rules = [
    {
      ref         = "block_non_allowlisted_countries"
      description = "Block requests from countries not in the allow list (zone-wide)"
      expression  = "not (${local.firewall_allowed_countries_expression})"
      action      = "block"
      enabled     = var.firewall_country_allowlist_enabled
    },
  ]
}

resource "cloudflare_ruleset" "zone_rate_limit" {
  zone_id     = var.cloudflare_zone_id
  name        = "zone-rate-limit"
  description = "Rate limit requests zone-wide"
  phase       = "http_ratelimit"
  kind        = "zone"

  rules = [{
    ref         = "rate_limit_public_services"
    description = "Apply rate limiting for all requests except the sovereign binary cache"
    expression  = "not (http.host eq \"cache.shrublab.xyz\" or http.host eq \"build-cache.shrublab.xyz\")"
    action      = "block"
    enabled     = var.rate_limit_enabled
    ratelimit = {
      characteristics     = var.rate_limit_characteristics
      period              = 10
      requests_per_period = var.rate_limit_requests_per_period
      mitigation_timeout  = 10
      requests_to_origin  = var.rate_limit_requests_to_origin
    }
  }]
}

resource "cloudflare_ruleset" "service_cache_bypass" {
  zone_id     = var.cloudflare_zone_id
  name        = "zone-cache-settings"
  description = "Cache configuration for service hosts"
  phase       = "http_request_cache_settings"
  kind        = "zone"

  rules = concat(
    local.cache_bypass_rules,
    [{
      ref         = "cache_narinfo_nar"
      description = "Enable edge caching for Nix binary cache subdomain"
      expression  = "(http.host eq \"cache.shrublab.xyz\")"
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 3600
        }
      }
    }]
  )

  count = 1
}

# ---------------------------------------------------------------------------
# Resend email sending domain DNS
# ---------------------------------------------------------------------------

resource "cloudflare_dns_record" "resend_send_spf" {
  count   = var.resend_send_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.resend_spf_name
  type    = "TXT"
  ttl     = 1
  content = var.resend_spf_value
  comment = "Managed by OpenTofu: Resend SPF for send.shrublab.xyz"
}

resource "cloudflare_dns_record" "resend_send_mx" {
  count    = var.resend_send_enabled ? 1 : 0
  zone_id  = var.cloudflare_zone_id
  name     = var.resend_mx_name
  type     = "MX"
  ttl      = 1
  content  = var.resend_mx_target
  priority = var.resend_mx_priority
  comment  = "Managed by OpenTofu: Resend return-path MX for send.shrublab.xyz"
}

resource "cloudflare_dns_record" "resend_send_dkim" {
  for_each = var.resend_send_enabled ? { for k in var.resend_dkim_records : k.name => k } : {}
  zone_id  = var.cloudflare_zone_id
  name     = each.value.name
  type     = "TXT"
  ttl      = 1
  content  = each.value.value
  comment  = "Managed by OpenTofu: Resend DKIM record ${each.key}"
}

resource "cloudflare_dns_record" "resend_send_dmarc" {
  count   = var.resend_send_enabled && trimspace(var.resend_dmarc_value) != "" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.resend_dmarc_name
  type    = "TXT"
  ttl     = 1
  content = var.resend_dmarc_value
  comment = "Managed by OpenTofu: Resend DMARC for send.shrublab.xyz"
}
