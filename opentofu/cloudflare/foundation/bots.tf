resource "cloudflare_bot_management" "zone" {
  zone_id    = var.cloudflare_zone_id
  fight_mode = false
}

import {
  to = cloudflare_bot_management.zone
  id = var.cloudflare_zone_id
}
