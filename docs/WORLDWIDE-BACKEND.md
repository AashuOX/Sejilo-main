# Worldwide encrypted relay architecture

## Trust boundary

Sejilo clients are the trusted endpoints. The API, WebSocket nodes, PostgreSQL,
Redis, object storage, load balancer, and opt-in gateways are transport and
delivery infrastructure. They must not receive plaintext private messages,
private identity keys, session keys, or attachment plaintext.

The current Flutter BLE direct-message format is signed but readable by relays.
It is therefore **not eligible for Internet submission**. The Internet adapter
accepts only the new opaque universal envelope and will remain outside the
normal send path until reviewed authenticated key agreement is integrated.

## Delivery flow

```text
client ciphertext -> HTTPS durable submit -> PostgreSQL transaction
                                     |
                                     +-> Redis live notification
                                              |
                                              +-> recipient WebSocket

recipient acknowledgement -> PostgreSQL receipt/state -> payload erasure
reconnect                   -> PostgreSQL pending reconciliation
```

Redis Pub/Sub is only a low-latency hint and is safe to lose. PostgreSQL is the
durable queue; every WebSocket authentication/reconnect queries it for pending
envelopes. This avoids treating Redis Pub/Sub's at-most-once behavior as a
delivery guarantee.

## Device authentication

1. Client requests a short-lived challenge with purpose `register` or `login`.
2. Server returns canonical UTF-8 bytes to sign.
3. Client signs those exact bytes with its Ed25519 identity key.
4. Registration additionally supplies the raw 32-byte public key. The server
   derives the device ID as base64url(SHA-256(public key)); callers cannot pick
   another identity.
5. The server issues a random opaque session token. Only its SHA-256 hash is
   stored in PostgreSQL; tokens expire and can be revoked.

No username, IP address, MAC address, or Bluetooth name authenticates a device.

## Durable schema

Migrations under `backend/migrations` define devices and key history, hashed
sessions, encrypted envelopes, per-recipient delivery state, receipts,
conversation/group metadata, trust/block records, attachment metadata, gateway
preferences, and abuse counters. Foreign keys and indexes cover pending-device
delivery, expiration cleanup, sender idempotency, session lookup, and group
membership.

Encrypted payloads have hard size/expiry bounds. A submission is
`SERVER_ACCEPTED` only after its PostgreSQL transaction commits. It becomes
`DELIVERED_TO_DEVICE` only after the recipient acknowledges it. Payload bytes
are erased after every recipient is delivered, while minimal receipt metadata
can remain for the configured retention period.

## Deployment

Copy `.env.example` to `.env`, replace every development secret, then run:

```shell
docker compose up --build
```

The backend runs migrations before accepting traffic. PostgreSQL and Redis use
isolated persistent volumes and health checks. Production must terminate TLS at
a trusted reverse proxy/load balancer and expose only HTTPS/WSS. Never publish
PostgreSQL or Redis ports publicly.

## Retention and quotas

- Encrypted messages default to seven days and may never exceed 30 days.
- Delivered payload bytes are removed by the cleanup worker.
- Expired undelivered envelopes are deleted in bounded batches.
- Per-device queued bytes/count and per-request payload limits are enforced.
- Attachments belong in private object storage using short-lived authorized
  URLs; PostgreSQL stores only ciphertext metadata and object IDs.

## Backup and restore

Back up PostgreSQL with encrypted `pg_dump`/managed snapshots and test restores
regularly. Back up object storage according to its ciphertext retention policy.
Redis presence, rate-limit counters, and live fan-out hints are disposable and
are rebuilt after restart; Redis must never be the only copy of an undelivered
message.

## Evidence boundary

Backend unit/integration tests prove schema, validation, authentication,
idempotency, queueing, acknowledgement, and reconnect behavior. Worldwide
messaging is not considered shipped until Android and Windows clients complete
real TLS/WebSocket tests across different networks and simultaneous
Internet/mesh duplicate delivery is verified receiver-side.
