# Sejilo threat model

Updated: 2026-08-11

## Security objectives

1. Private plaintext and long-term private keys never reach a relay, gateway,
   Redis, PostgreSQL, object store, or AI provider.
2. A stolen relay database does not reveal private-message plaintext.
3. Unauthorized devices cannot read, submit as, acknowledge for, or manage
   another device's resources by changing identifiers.
4. Malformed or replayed traffic is rejected before unbounded work or storage.
5. Messaging and nearby networking keep working when AI is disabled or fails.
6. Security failure is visible and closed; signed plaintext is never labeled E2EE.

## Assets and trust boundaries

| Asset | Trusted boundary | Outside/hostile boundary |
| --- | --- | --- |
| Identity private key | device protected storage / future non-exportable provider | peers, relay, database, logs, AI |
| Private plaintext | authorized sender/recipient UI and E2EE session | BLE/LAN/gateway/Internet, server storage |
| Session tokens | protected client storage and hashed server record | URLs, logs, other devices |
| Public identity/key bundle | cryptographically bound device identity | display name, MAC, IP and Bluetooth name are untrusted |
| Encrypted envelopes | sender and recipient integrity checks | every transport and relay may copy/drop/replay/reorder |
| AI-selected data | local provider unless one-operation cloud consent exists | no implicit history upload or training |

The device OS and UI process are trusted to display plaintext. If an authorized
device is compromised or unlocked for an attacker, Sejilo cannot protect text
visible to that process, prevent screenshots/cameras, or undo already-read data.

## Principal attackers

- hostile Internet clients, credential stuffers, scanners and denial-of-service actors;
- malicious nearby BLE/LAN peers and large Sybil populations;
- packet sniffers, replay attackers, impersonators and route manipulators;
- compromised gateways, relay instances, Redis, PostgreSQL and backups;
- malicious attachments, filenames, links, prompts and diagnostic input;
- stolen access/refresh tokens and compromised build/update infrastructure;
- curious or compromised cloud AI providers.

## Implemented controls

- Ed25519 challenge proof for relay device registration/login; one-use Redis challenges;
- 15-minute access tokens, rotating 30-day refresh tokens, HMAC-hashed tokens at rest, revocation, and disabled-device checks;
- parameterized PostgreSQL queries and object-level recipient checks for pending messages and acknowledgements;
- IP plus authenticated-device/message rate limits, queue count/byte quotas, WebSocket-per-device caps;
- strict Zod and Dart envelope schemas, version/type/ID/destination/time/TTL/hop/payload bounds;
- ciphertext-only Internet relay, idempotent message IDs, expiry cleanup, payload erasure after delivery;
- internal-only PostgreSQL/Redis Docker network, authenticated Redis, non-root read-only backend container with all Linux capabilities dropped;
- authenticated metrics, redacted structured request logs, no CORS enablement, no-store/nosniff/frame-denial response headers;
- BLE signature verification, age/hop limits, bounded fragmentation memory, duplicate suppression and attachment-size/type admission;
- controlled received-attachment directory and generated safe filenames; files are not executed or automatically opened;
- trusted-only, block-peer, attachment-receive, visibility, notification-preview and gateway-off controls;
- optional AI master/feature/cloud controls; local draft-only rewriting; explicit output confirmation; bounded AI input; complete AI-derived-data deletion hook;
- release-mode Android debug signing removed; release signing now fails closed without CI secrets.

## P0 gaps and disabled paths

- No reviewed Signal Protocol/MLS implementation is integrated. Legacy BLE
  direct messaging is therefore disabled rather than misrepresented as E2EE.
- Locality groups and the nearby channel are signed public mesh features, not
  confidential group messaging.
- Android identity bytes are protected by secure-storage wrapping, not yet a
  non-exportable Ed25519 Keystore operation; Windows needs the equivalent CNG boundary.
- Internet transport exists behind a ciphertext-only interface but the normal
  chat Delivery Engine does not route into it.
- No attachment object-storage service, secure updater, gateway forwarding, LAN
  transport, cloud AI provider, model downloader, OCR, transcription,
  translation model, or semantic embedding index is enabled.
- Docker Compose is a hardened development/single-host baseline. Production
  still needs separate database migration/application roles, firewall/TLS edge,
  encrypted backups, restoration drills, alerting, and orchestration policy.

## Metadata after E2EE

E2EE does not conceal every fact. Internet infrastructure may observe device
IP, timing, message sizes, recipient routing identifiers, queue duration and
connection patterns. Nearby observers may detect radio presence, advertising
cadence and approximate proximity. Padding, batching, Tor and private-contact
discovery require separate reviewed designs; they are not claimed today.

## Required E2EE direction

Do not extend `PeerSession` into a home-grown protocol. Integrate a maintained,
reviewed implementation of an asynchronous protocol such as Signal's X3DH/PQXDH
plus Double Ratchet for device-to-device sessions, or MLS for reviewed group
semantics. Bind identity/prekey bundles to verified device identities, persist
ratchet state transactionally before send, rotate signed/one-time prekeys,
protect skipped-key limits, and test multi-device/session reset behavior. QR
safety codes must bind the complete cryptographic identity, not a display name.

## Verification mapping

Security verification should track OWASP MASVS storage, crypto, auth, network,
platform, code, resilience and privacy controls, plus applicable OWASP ASVS API
authentication, access-control, validation, file and WebSocket controls. A
checklist is evidence management, not proof of protocol security.
