variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID (Dashboard → My Profile → API Tokens)."
  default     = "8ee63532600880649356088255325325364"
}

variable "zone_id" {
  type        = string
  description = "Cloudflare Zone ID for the managed domain."
  default     = "698b9ea60e6c41a9d796a4e815c33088"
}

variable "domain" {
  type        = string
  description = "Primary domain, e.g. sejilochat.com"
  default     = "sejilochat.com"
}

variable "origin_ip" {
  type        = string
  description = "Public IPv4 of the origin host running docker-compose (used by DNS A records). Required only for DNS records."
  default     = ""
}

variable "api_subdomain" {
  type    = string
  default = "api"
}

variable "app_subdomain" {
  type    = string
  default = "app"
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.5"
}
