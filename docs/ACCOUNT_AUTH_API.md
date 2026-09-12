# SejiloChat account and profile API

This API adds optional online accounts without changing accountless nearby mesh
identity or its Ed25519 relay authentication.

## Account endpoints

- `POST /v1/users`: `{email,password,username,displayName}` creates a user and
  returns `{token,expiresAt,profile}`.
- `POST /v1/auth/password/login`: `{email,password}` returns a fresh opaque
  session token and profile.
- `DELETE /v1/auth/password/session`: revokes the authenticated account session.
- `GET /v1/me`: returns the authenticated profile.
- `PATCH /v1/me`: updates any of `username`, `displayName`, `bio`, and `avatar`.
  Avatar is `{mimeType,data}` where data is unpadded base64url PNG/JPEG/WebP
  below 256 KiB; use `null` to remove it.
- `POST /v1/auth/password/reset-requests`: always accepts a valid email when
  Resend is configured, without exposing whether it is registered.
- `POST /v1/auth/password/resets`: `{token,password}` consumes the 30-minute,
  single-use reset token and revokes every existing account session.

Account session tokens are opaque 256-bit values, stored only as HMAC hashes in
PostgreSQL. Passwords are salted Node scrypt hashes and are never logged.

## Deployment

Set `RESEND_API_KEY`, `PASSWORD_RESET_FROM`, and `PASSWORD_RESET_URL` in the
backend environment. The reset URL must be HTTPS in production. For a browser
client hosted separately, set `WEB_ALLOWED_ORIGIN` to the exact HTTPS origin.
