variable "cloudflare_api_token" {
  description = "Cloudflare API token for OpenTofu operations"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for shrublab.xyz"
  type        = string
}

variable "dns_record_type" {
  description = "DNS record type used for managed service subdomains"
  type        = string
  default     = "CNAME"
}

variable "edge_record_target" {
  description = "DNS target for service subdomains (for example your edge hostname)"
  type        = string
}

variable "manage_origin_record" {
  description = "Whether OpenTofu manages the origin record used by service CNAME targets"
  type        = bool
  default     = true
}

variable "origin_record_name" {
  description = "Record name for shared origin endpoint (for example: origin)"
  type        = string
  default     = "origin"
}

variable "origin_record_type" {
  description = "DNS record type for origin record (typically A or AAAA)"
  type        = string
  default     = "A"
}

variable "origin_record_content" {
  description = "DNS content for origin record (IP for A/AAAA, hostname for CNAME)"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.manage_origin_record == false
      || (
        var.origin_record_content != null
        && trimspace(var.origin_record_content) != ""
      )
    )
    error_message = "origin_record_content is required when manage_origin_record is true."
  }
}

variable "origin_record_proxied" {
  description = "Whether origin record should be proxied by Cloudflare"
  type        = bool
  default     = false
}

variable "primary_domain" {
  description = "Primary DNS domain for generated service hostnames"
  type        = string
  default     = "shrublab.xyz"
}

variable "aop_enabled" {
  description = "Enable zone-level Authenticated Origin Pulls"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Zero Trust Identity Provider (Kanidm generic OIDC)
# -----------------------------------------------------------------------------

variable "idp_type" {
  description = "Zero Trust IdP name shown on the login page"
  type        = string
  default     = "oidc"
}

variable "idp_name" {
  description = "Zero Trust IdP name shown on the login page"
  type        = string
  default     = "Kanidm"
}

variable "idp_client_id" {
  description = "OIDC client ID for Cloudflare Access upstream IdP"
  type        = string
  default     = null
  nullable    = true

  # validation {
  #   condition = (
  #     var.idp_client_id == null
  #     || (
  #       var.idp_client_secret != null
  #       && trimspace(var.idp_client_secret) != ""
  #     )
  #   )
  #   error_message = "idp_client_secret is required when idp_client_id is set."
  # }
}

variable "idp_client_secret" {
  description = "OIDC client secret for Cloudflare Access upstream IdP"
  type        = string
  sensitive   = true
  default     = null
  nullable    = true

  validation {
    condition = (
      var.idp_client_secret == null
      || (
        var.idp_client_id != null
        && trimspace(var.idp_client_id) != ""
      )
    )
    error_message = "idp_client_id is required when idp_client_secret is set."
  }
}

variable "idp_auth_url" {
  description = "OIDC authorization endpoint URL for the Cloudflare Access upstream IdP"
  type        = string
  default     = "https://kanidm.shrublab.xyz/oauth2/openid/cloudflare-access/authorize"

  # validation {
  #   condition = (
  #     var.idp_client_id == null
  #     || (
  #       var.idp_auth_url != null
  #       && trimspace(var.idp_auth_url) != ""
  #     )
  #   )
  #   error_message = "idp_auth_url is required when idp_client_id is set."
  # }
}

variable "idp_token_url" {
  description = "OIDC token endpoint URL for the Cloudflare Access upstream IdP"
  type        = string
  default     = "https://kanidm.shrublab.xyz/oauth2/token"

  # validation {
  #   condition = (
  #     var.idp_client_id == null
  #     || (
  #       var.idp_token_url != null
  #       && trimspace(var.idp_token_url) != ""
  #     )
  #   )
  #   error_message = "idp_token_url is required when idp_client_id is set."
  # }
}

variable "idp_certs_url" {
  description = "OIDC JWKS endpoint URL for the Cloudflare Access upstream IdP"
  type        = string
  default     = "https://kanidm.shrublab.xyz/oauth2/openid/cloudflare-access/public_key.jwk"

  # validation {
  #   condition = (
  #     var.idp_client_id == null
  #     || (
  #       var.idp_certs_url != null
  #       && trimspace(var.idp_certs_url) != ""
  #     )
  #   )
  #   error_message = "idp_certs_url is required when idp_client_id is set."
  # }
}

# -----------------------------------------------------------------------------
# Zero Trust Access Policy
# -----------------------------------------------------------------------------

variable "admin_email" {
  description = "Email address of the administrator for Access application notifications"
  type        = string
  sensitive   = true
}

variable "temp_access_session_duration" {
  description = "Session duration for temporary access policies requiring approval"
  type        = string
  default     = "24h"
}

variable "access_session_duration" {
  description = "Session duration for regular access policies (e.g. for admins)"
  type        = string
  default     = "730h"
}

# -----------------------------------------------------------------------------
# Zone rulesets (WAF/firewall/cache posture)
# -----------------------------------------------------------------------------

variable "managed_waf_enabled" {
  description = "Enable execution of Cloudflare managed WAF ruleset for in-scope public service hosts"
  type        = bool
  default     = true
}

variable "firewall_country_allowlist_enabled" {
  description = "Enable custom firewall country allow-list enforcement for in-scope public service hosts"
  type        = bool
  default     = false
}

variable "firewall_allowed_countries" {
  description = "ISO 3166-1 alpha-2 country codes allowed when firewall_country_allowlist_enabled is true"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for code in var.firewall_allowed_countries : length(trimspace(code)) == 2
    ])
    error_message = "firewall_allowed_countries entries must be 2-letter ISO country codes (for example: \"AU\", \"GB\")."
  }
}

variable "navidrome_cache_bypass_enabled" {
  description = "Enable cache bypass ruleset for Navidrome host so streaming is never CDN cached"
  type        = bool
  default     = true
}

variable "rate_limit_enabled" {
  description = "Enable zone-level rate limiting for in-scope public service hosts"
  type        = bool
  default     = true
}

variable "rate_limit_characteristics" {
  description = "Rate limiting characteristics used for counters"
  type        = list(string)
  default     = ["ip.src", "cf.colo.id"]
}

variable "rate_limit_requests_per_period" {
  description = "Allowed requests per period before mitigation"
  type        = number
  default     = 200
}

variable "rate_limit_requests_to_origin" {
  description = "Whether to count only requests that reach origin"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Resend email sending domain
# -----------------------------------------------------------------------------

variable "resend_send_enabled" {
  description = "Enable Resend email DNS records for the send subdomain"
  type        = bool
  default     = false
}

variable "resend_spf_name" {
  description = "SPF record name for the sending domain (e.g., 'send')"
  type        = string
  default     = "send"
}

variable "resend_spf_value" {
  description = "Full SPF TXT value copied from the provider dashboard"
  type        = string
  default     = "v=spf1 include:amazonses.com ~all"
}

variable "resend_mx_name" {
  description = "MX record name for the sending domain (e.g., 'send')"
  type        = string
  default     = "send"
}

variable "resend_mx_target" {
  description = "MX record target copied from the provider dashboard"
  type        = string
  default     = "feedback-smtp.us-east-1.amazonses.com"
}

variable "resend_mx_priority" {
  description = "MX priority copied from the provider dashboard"
  type        = number
  default     = 10
}

variable "resend_dkim_records" {
  description = "DKIM TXT records provided by the provider dashboard (paste dashboard name/value directly)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "resend_dmarc_name" {
  description = "DMARC record name for the sending domain (e.g., '_dmarc.send'). Leave empty to skip DMARC record creation."
  type        = string
  default     = ""
}

variable "resend_dmarc_value" {
  description = "Full DMARC TXT value copied from the provider dashboard. Leave empty to skip DMARC record creation."
  type        = string
  default     = ""
}
