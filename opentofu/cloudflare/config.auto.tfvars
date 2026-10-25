# Non-sensitive OpenTofu config only.
# Keep only secrets and infra-sensitive identifiers in encrypted SOPS sources.

# Cloudflare Access upstream IdP (Kanidm generic OIDC)
idp_name      = "Kanidm"
idp_auth_url  = "https://id.shrublab.xyz/ui/oauth2"
idp_token_url = "https://id.shrublab.xyz/oauth2/token"
idp_certs_url = "https://id.shrublab.xyz/oauth2/openid/cloudflare-access/public_key.jwk"

aop_enabled = true

managed_waf_enabled                = true
firewall_country_allowlist_enabled = true
firewall_allowed_countries         = ["AU", "GB", "US"]
rate_limit_enabled                 = true
rate_limit_characteristics         = ["ip.src", "cf.colo.id"]
rate_limit_requests_per_period     = 300
rate_limit_requests_to_origin      = true
navidrome_cache_bypass_enabled     = true

# Resend email sending domain (shrublab.xyz). Paste the dashboard name/value fields directly.
resend_send_enabled = true
resend_dmarc_name   = "_dmarc"
resend_dmarc_value  = "v=DMARC1; p=none;"

resend_cname_records = [
  {
    name  = "rsend"
    value = "rsend-apne1.forge.rmta.net"
  },
  {
    name  = "send"
    value = "send.forge.rmta.net"
  },
]

resend_dkim_records = [
  {
    name  = "resend._domainkey"
    value = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDWBeOoeZAktdJIVDMtb6W6oLBkMDQJdOXvXF4F/3TymtaT/f0eyU5TsZksDjBicQf3b4S6oZI9sFSmImEXZAI+aJkqOhnA4zuCPKG/jfkTO0qrZ9sJckZmtUMnSNlpiAKs7e0AZ0XgZT0W5m16wK9GSAjBLYosTcuzyXmhLOWaJwIDAQAB"
  },
]
