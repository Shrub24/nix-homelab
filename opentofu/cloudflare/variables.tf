variable "cloudflare_api_token" {
  description = "Cloudflare API token for service publication"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "dns_record_type" {
  description = "DNS record type for service subdomains"
  type        = string
  default     = "CNAME"
}

variable "edge_record_target" {
  description = "DNS target for service subdomains"
  type        = string
}

variable "foundation_access" {
  description = "Non-secret references exported from the foundation state before publication"
  type = object({
    policies         = map(string)
    allowed_idps     = list(string)
    session_duration = string
  })
}
