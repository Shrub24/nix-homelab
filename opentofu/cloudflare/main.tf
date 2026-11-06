terraform {
  required_version = ">= 1.6.0"

  backend "s3" {}

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.26.0, < 6.0"
    }
  }
}

locals {
  web_services_policy    = jsondecode(file("../../generated/policy/web-services.json"))
  public_service_records = local.web_services_policy.cloudflare.hosts
  access_app_service_records = {
    for public_host, host in local.public_service_records : public_host => host
    if try(host.access.requireCloudflareAccess, false)
  }
  policy_resources_by_name = var.foundation_access.policies
}

resource "cloudflare_dns_record" "service" {
  for_each = local.public_service_records

  zone_id = var.cloudflare_zone_id
  name    = each.value.hostname
  type    = var.dns_record_type
  ttl     = 1
  content = var.edge_record_target
  proxied = try(each.value.proxied, true)

  # A zone apex cannot be a bare CNAME; Cloudflare flattens it to address records.
  settings = {
    flatten_cname = try(each.value.apex, false)
  }

  comment = "Managed by OpenTofu from policy/web-services.nix"
}

resource "cloudflare_zero_trust_access_application" "service" {
  for_each = local.access_app_service_records

  account_id = var.cloudflare_account_id
  name       = each.value.publicHost
  domain     = each.value.publicHost
  type       = "self_hosted"

  policies = concat(
    [
      for idx, policy_name in each.value.access.policies : {
        id         = local.policy_resources_by_name[policy_name]
        precedence = idx + 1
      }
    ],
    [{
      id         = var.foundation_access.policies.allow_machine
      precedence = 100
    }]
  )

  allowed_idps = length(var.foundation_access.allowed_idps) > 0 ? var.foundation_access.allowed_idps : null

  app_launcher_visible     = false
  enable_binding_cookie    = false
  options_preflight_bypass = false

  session_duration          = var.foundation_access.session_duration
  auto_redirect_to_identity = true
}
