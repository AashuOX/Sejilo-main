# Sejilo security policy

Security is a P0 architecture requirement. Treat the network as hostile, relay
peers as untrusted, servers as eventually breachable, and every decoded field
as attacker-controlled.

## Current security status

Sejilo is under active development and has not received an independent audit.
Do not describe it as highly secure or use it for sensitive communications.

The Flutter client authenticates BLE envelopes with Ed25519, bounds packet and
attachment sizes, suppresses duplicates, limits hops and age, and encrypts its
local message record. Authentication is not confidentiality: the legacy BLE v3
direct-message body is signed but readable by relays. The hardened client now
fails closed for that format: it cannot send, deliver, acknowledge, or relay
legacy direct messages. Public nearby and locality-group messages remain public
to participating peers.

The Internet relay accepts only opaque ciphertext envelopes and authenticates
device possession with an Ed25519 challenge. It does not make the current BLE
chat E2EE. App-level Internet routing remains disabled until an independently
reviewed asynchronous E2EE protocol implementation is integrated and tested.

Device identity keys are wrapped by platform secure storage today, but the
Ed25519 private bytes enter the Flutter process. Non-exportable Android
Keystore/Windows CNG identity operations are still required for the strongest
device-compromise boundary. This limitation must not be hidden.

See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) for assets, boundaries,
attacks, mitigations, metadata, and explicitly unsupported guarantees.

## Reporting a vulnerability

Use GitHub private vulnerability reporting:
https://github.com/permissionlesstech/sejilochat/security/advisories/new

Do not open a public issue containing an exploitable vulnerability before a fix
is available. Include the affected commit/build, attacker prerequisites,
reproduction steps, and a minimal proof or failing test. Never include real
private messages, tokens, keys, or identifying production data.

## Supported versions

Only the latest `main` revision and most recent distributed build receive
security fixes. No production security support commitment exists yet.

## Release requirements

A production candidate must have all of the following:

- reviewed E2EE protocol/library integration with forward secrecy and replay protection;
- non-exportable platform identity-key operations where supported;
- Android and Windows release signing with protected offline recovery keys;
- TLS/WSS at the public edge and authenticated non-public metrics;
- separate least-privilege database migration and application roles;
- dependency, static-analysis, secret, and container scans reviewed by a human;
- encrypted backup restoration and credential/session-revocation drills;
- independent security review and penetration testing;
- resolved P0/P1 findings documented with regression tests.

Debug signing, test credentials, cleartext public relay URLs, unauthenticated
Redis/PostgreSQL exposure, automatic update execution, and cloud AI keys inside
client binaries are release blockers.

## Logging and privacy

Security logs may record event category, coarse timestamp, request ID, status,
and truncated/non-reversible identifiers needed for abuse response. They must
never record plaintext messages, drafts, AI inputs, private keys, bearer or
refresh tokens, signatures used as credentials, full public keys, complete IP
history, attachment bodies, or encrypted payloads.

## Incident response

Follow [docs/INCIDENT-RESPONSE.md](docs/INCIDENT-RESPONSE.md). Preserve evidence
without copying message content, revoke sessions, rotate affected secrets, stop
unsafe distribution, notify affected users honestly, and publish a regression
test and post-incident analysis after containment.
