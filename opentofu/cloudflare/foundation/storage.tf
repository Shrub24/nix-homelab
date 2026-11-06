variable "r2_buckets" {
  description = "Existing buckets adopted by foundation; object contents are not managed here"
  type        = set(string)
}

variable "r2_custom_domains" {
  description = "Public R2 domain to bucket mapping"
  type        = map(string)
}

resource "cloudflare_r2_bucket" "managed" {
  for_each   = var.r2_buckets
  account_id = var.cloudflare_account_id
  name       = each.value

  lifecycle {
    prevent_destroy = true
  }
}

# Adoption must fail rather than create an empty replacement for a misspelled bucket.
import {
  for_each = var.r2_buckets
  to       = cloudflare_r2_bucket.managed[each.value]
  id       = "${var.cloudflare_account_id}/${each.value}/default"
}

resource "cloudflare_r2_custom_domain" "public" {
  for_each    = var.r2_custom_domains
  account_id  = var.cloudflare_account_id
  zone_id     = var.cloudflare_zone_id
  bucket_name = cloudflare_r2_bucket.managed[each.value].name
  domain      = each.key
  enabled     = true
}
