provider "cloudflare" {
  # API token is read from the CLOUDFLARE_API_TOKEN environment variable.
}

locals {
  api_fqdn = "${var.api_subdomain}.${var.domain}"
  app_fqdn = "${var.app_subdomain}.${var.domain}"
}

# ── Zone security posture ───────────────────────────────────────────────
resource "cloudflare_zone_settings_override" "sejilo" {
  zone_id = var.zone_id

  settings {
    ssl                      = "strict"        # Full (Strict) — requires Origin CA cert on origin
    always_use_https         = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    http3                    = "on"
    automatic_https_rewrites = "on"
    browser_check            = "on"
    challenge_ttl            = 1800
    security_level           = "medium"
    privacy_pass             = "on"
  }
}

# ── DNS ────────────────────────────────────────────────────────────────
# Only created once an origin IP is supplied (and the token has DNS:Edit).
resource "cloudflare_dns_record" "api" {
  count   = var.origin_ip != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.api_subdomain
  content = var.origin_ip
  type    = "A"
  proxied = true   # orange-cloud: WAF + CDN + Rate Limit apply
  ttl     = 1
}

resource "cloudflare_dns_record" "app" {
  count   = var.origin_ip != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.app_subdomain
  content = var.origin_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "root" {
  count   = var.origin_ip != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.domain
  content = var.origin_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

# ── WAF Rate Limit (mirrors backend ThrottlerModule 120/min/user) ───────
resource "cloudflare_waf_rate_limit" "api" {
  zone_id                = var.zone_id
  name                   = "sejilo-api-default"
  description            = "Global ceiling aligned with backend 120 req/min throttle"
  period                 = 60
  requests_to_origin     = true
  count_response_code    = 429
  mitigation_timeout     = 60

  match {
    request {
      methods     = ["GET", "POST", "PUT", "PATCH", "DELETE"]
      schemes     = ["HTTP", "HTTPS"]
      url_pattern = "${local.api_fqdn}/*"
    }
  }

  action {
    response {
      content      = "Rate limited by Cloudflare edge."
      content_type = "text/plain"
    }
  }

  thresholds {
    limit        = 120
    period       = 60
    action       = "challenge"
    response_code = 429
  }
}

# ── Cache Rules ─────────────────────────────────────────────────────────
# API must never be cached; static web assets can be.
resource "cloudflare_ruleset" "cache" {
  zone_id    = var.zone_id
  name       = "sejilo-cache-rules"
  description = "Cache behaviour for SejiloChat"
  kind       = "zone"
  phase      = "http_request_cache_settings"

  rules {
    action = "set_cache_settings"
    expression = "starts_with(http.request.uri.path, \"/api/\") || starts_with(http.request.uri.path, \"/v1/\")"
    description = "Never cache API responses"
    action_parameters {
      cache = false
    }
  }

  rules {
    action = "set_cache_settings"
    expression = "http.host eq \"${local.app_fqdn}\" && starts_with(http.request.uri.path, \"/assets/\")"
    description = "Cache Flutter web assets"
    action_parameters {
      cache = true
      edge_ttl {
        mode = "override_origin"
        default = 86400
      }
      browser_ttl {
        mode = "override_origin"
        default = 86400
      }
    }
  }
}

# ── Transform Rule: edge security headers (belt-and-suspenders with Helmet)
resource "cloudflare_ruleset" "response_headers" {
  zone_id    = var.zone_id
  name       = "sejilo-edge-headers"
  description = "Harden edge responses"
  kind       = "zone"
  phase      = "http_response_headers_transform"

  rules {
    action = "set_response_headers"
    description = "Add HSTS preload + framing/type options"
    expression = "true"
    action_parameters {
      headers {
        name      = "Strict-Transport-Security"
        value     = "max-age=63072000; includeSubDomains; preload"
        operation = "set"
      }
      headers {
        name      = "X-Content-Type-Options"
        value     = "nosniff"
        operation = "set"
      }
      headers {
        name      = "Referrer-Policy"
        value     = "strict-origin-when-cross-origin"
        operation = "set"
      }
    }
  }
}

output "api_endpoint" {
  value = "https://${local.api_fqdn}"
}

output "app_endpoint" {
  value = "https://${local.app_fqdn}"
}
