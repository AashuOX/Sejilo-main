# SejiloChat — Cloudflare Infrastructure (STEP 29)

This directory contains infrastructure-as-code for the production edge in front of
the SejiloChat backend (Docker / `docker-compose.yml`, API on `:8080`) and the
Flutter web build.

> These files are **authoring artifacts** — they require your Cloudflare account
> credentials and a registered domain. Apply with `terraform apply` (DNS/WAF/cache)
> and/or `wrangler deploy` (edge Worker). Nothing here is deployed automatically.

## Current deployment state (filled in from the provided token)
- **Zone:** `sejilochat.com` (id `698b9ea60e6c41a9d796a4e815c33088`)
- **Account:** `8ee63532600880649356088255325364` (`Aashuuzx09@gmail.com's Account`)
- **Zone status:** `pending` — the registrar nameservers have **not** been pointed at
  Cloudflare yet (`erin.ns.cloudflare.com`, `terin.ns.cloudflare.com`). Cloudflare
  config has no effect until the zone is **active**.
- **DNS A records created (staged):** `sejilochat.com`, `api.sejilochat.com`,
  `app.sejilochat.com` → `120.89.104.63`, all proxied (orange-cloud). They go
  live when the zone is activated. (Created via the Cloudflare API; the Terraform
  `cloudflare_dns_record` resources are guarded by `count` and will need
  `terraform import` if you later manage them with Terraform.)
- **Token scope:** the supplied `CLOUDFLARE_API_TOKEN` (zone API key) has **DNS**
  permissions (DNS read/write succeed) but still returns `403` on **Zone
  Settings** and **Rulesets**. So DNS records can be managed, but SSL mode,
  cache rules, WAF rate-limit, and response-header transforms require a token
  with **Zone:SSL/TLS:Edit**, **Zone:Settings:Edit**, and **Zone:Rulesets:Edit**
  (or Account:Cloudflare Tunnel for `tunnel.yml`).
- The token + ids are stored in the repo-root `.env` (gitignored) as
  `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_ACCOUNT_ID`.

## Topology

```
Browser / Flutter app
        │  HTTPS (Edge: WAF, Rate Limit, Cache, HSTS)
        ▼
   Cloudflare  ──(Cloudflare Tunnel / origin cert)──►  origin: api.sejilo.chat:8080
   (DNS, WAF,                                       (Docker `sejilo-backend-1`)
    Cache Rules,
    Transform Hdr)
```

- **API**: `api.sejilo.chat` → proxied (orange-cloud) → Cloudflare Tunnel (`cloudflared`) → backend container on `:8080`.
- **Static web build** (optional Flutter web): `app.sejilo.chat` or `@` → R2 / Pages, cached at edge.
- **TLS**: Full (Strict) using a Cloudflare Origin CA certificate installed on the origin. Backend already sends Helmet security headers; the Worker/Transform Rule below hardens edge responses (HSTS preload, CSP) and enforces API cache bypass.

## Files
- `cloudflare.tf` — provider + zone settings, DNS records, WAF rate-limit (matches backend `120 req/min`), cache rules (`/api/*` never cached), transform-rule security headers.
- `variables.tf` — required inputs (zone id, account id, origin IP, domain).
- `wrangler.toml` — optional edge Worker (security headers + `/api` reverse proxy to the Tunnel / origin). Use instead of (or in addition to) Transform Rules.
- `tunnel.yml` — `cloudflared` configuration snippet for the zero-trust Tunnel to the backend.

## Apply
```bash
export CLOUDFLARE_API_TOKEN="<token with Zone:Edit + Account:Cloudflare Tunnel>"
terraform init
terraform plan -var="cloudflare_account_id=..." -var="zone_id=..." -var="domain=sejilo.chat" -var="origin_ip=203.0.113.10"
terraform apply
```

## Origin certificate (one-time)
Generate an Origin CA cert (Dashboard → SSL/TLS → Origin Server, or `cloudflare_origin_ca_certificate`
in Terraform) and mount it into the backend container as `SSL_CERT_FILE` / `SSL_KEY_FILE`, then set
`PORT=8080` + TLS termination at the origin (or terminate at Cloudflare and use the Tunnel, which is preferred).
