# Production readiness and evidence gates

This document is a claim ledger. A capability is not considered shipped until
its implementation and its evidence gate are both complete.

## Current implementation

| Area | Implemented | Still required before release |
| --- | --- | --- |
| Transport | Android BLE advertiser/GATT server binding; Windows WinRT advertiser/GATT server binding compiles; v2 wire fragmentation, strict packet bounds, TTL relay and duplicate suppression are connected to BLE | Lifecycle/background handling; source routing and adaptive fanout; physical-device proof |
| Security | Ed25519 device identity; identity-bound signed presence/public messages; runtime TOFU key pin; QR input; encrypted local message records; per-peer AEAD/replay primitives | Private-message X25519 handshake integration, persistent TOFU pins/counters, signed QR validation, key-change UX, external audit |
| Reliability | Authenticated public-message acknowledgements, in-memory bounded retry/backoff, wire fragmentation/reassembly and multi-hop relay | Persist queue atomically, read receipts, restart recovery, offline courier/history sync, congestion and expiry policy |
| Privacy | Encrypted message records and clear-local-history control | Encrypt copied attachments, app lock, panic wipe, portable export/delete, metadata retention controls |
| Usability | Contact profiles, QR scanner on Android, attachment/voice UI, private search, reactions, pins and stored delivery state | Reply composer, transport-driven delivery indicators and notification preferences |
| Operations | No-content design for protocol state | Crash-safe database, redacted structured logging, release signing/update runbook, backup/recovery drills |

## Mandatory hardware test matrix

Record device model, OS build, Bluetooth chipset/driver, app build hash, start
and end times, and a content-free result log for every run.

| Topology | Foreground | Background | Range loss/rejoin | Sender offline/rejoin |
| --- | --- | --- | --- | --- |
| Android A to Android B | Required | Required | Required | Required |
| Windows A to Windows B | Required | Required | Required | Required |
| Android A to Windows A | Required | Required | Required | Required |
| Android B through Windows A to Windows B | Required | Required | Required | Required |

Each scenario must demonstrate: discovery, verified pairing, encrypted send,
fragment reassembly, acknowledgement, no duplicate delivery, bounded retry,
relay hop enforcement, and delivery after reconnect. Retain packet sizes,
timings, state transitions, and error codes only; never retain message content,
keys, QR payloads, contact names, or stable peer identifiers.

## Security release gate

Before describing the product as secure, commission an independent review of
the protocol, Android and Windows platform bindings, local storage, attachment
handling, build/update chain, and deletion behavior. Track findings to closure
and publish the scope, tested version, limitations, and remediation status.
