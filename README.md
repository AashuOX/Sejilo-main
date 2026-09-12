# SejiloChat

SejiloChat is a Flutter messenger project targeting **Windows desktop** and
**Android** only. The legacy macOS/iOS Swift application has been removed.

The application source is in [`sejilo_chat/`](sejilo_chat/).

## Supported platforms

- Windows desktop
- Android

macOS, iOS, and web are not supported project targets.

## Run on Windows

Install Flutter and Visual Studio with the **Desktop development with C++**
workload, then run:

```powershell
cd sejilo_chat
flutter pub get
flutter run -d windows
```

## Run on Android

Install Android Studio and the Android SDK, connect an Android device with USB
debugging enabled (or start an emulator), then run:

```powershell
cd sejilo_chat
flutter doctor
flutter run
```

## Current implementation

The app provides a local-first chat UI, device identity setup, encrypted local
message storage, contact profiles, attachment selection, voice notes, signed
BLE messaging, fragmentation, bounded relay flooding, retry queues, and
acknowledgements. Android and Windows native BLE bindings are included.

The repository also contains a versioned ciphertext envelope, common delivery
transport contract, route scoring, and an authenticated Internet relay adapter.
Direct BLE messages now use authenticated E2EE: static X25519 key-agreement
keys are exchanged at peer discovery, and every direct message body is
encrypted with ChaCha20-Poly1305 under a per-peer ephemeral session
(protocol version 4, backward compatible with version 3). Legacy readable
direct payloads and attachments fail closed. See
[`SEJILO_UPGRADE_PROGRESS.md`](SEJILO_UPGRADE_PROGRESS.md) for verified
capabilities and remaining work.

## Worldwide relay backend

The [`backend/`](backend/) service stores only opaque encrypted envelopes. It
uses PostgreSQL for durable queues and receipts, Redis for disposable presence,
rate limits and WebSocket hints, and JWT authentication. It also exposes
presigned media uploads (S3/MinIO compatible), phone-OTP authentication with
SMS delivery, FCM push notifications to offline members, and a device-key API
(`POST /v1/device-keys`, `GET /v1/users/:userId/device-keys`) that publishes
and serves signed X25519 key bundles so mesh E2EE peers can bootstrap encrypted
chats from the server.

```powershell
Copy-Item .env.example .env
# Replace every placeholder secret in .env, then:
docker compose up -d --build
Invoke-RestMethod http://127.0.0.1:8080/health/ready
```

Production deployment requires TLS termination, secret management, monitored
backups, and the controls described in
[`docs/WORLDWIDE-BACKEND.md`](docs/WORLDWIDE-BACKEND.md). A client build can be
configured with `--dart-define=SEJILO_API_BASE_URL=https://relay.example`.
The retired `backend_new/` (NestJS 10, port 3000, socket.io) is kept only for
reference; its capabilities have been ported into `backend/`.

### Hosting it online without paying

[`docs/FREE_HOSTING.md`](docs/FREE_HOSTING.md) deploys the same backend to a
permanent `https://*.onrender.com` URL on free plans — Render for the service,
Supabase for Postgres, Upstash for Redis — so it stays reachable with this machine
turned off. The `render.yaml` blueprint at the repository root drives it.

That replaces `scripts/go-online.ps1`, which publishes the *local* backend through
a Cloudflare quick tunnel: useful for a demo, but the URL rotates on every restart
and dies with the process. `scripts/check-online.ps1 -BaseUrl <url>` verifies either
one end to end.

## License

This project is released into the public domain. See [`LICENSE`](LICENSE).
