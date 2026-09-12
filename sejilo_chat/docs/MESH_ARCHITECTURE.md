# Native peer-to-peer mesh architecture

This project targets native Windows and Android applications.
Browser runtimes are not supported because they cannot provide reliable
background BLE advertising, scanning, or store-and-forward relay behavior.

## Trust boundary

1. `MeshClient` owns message routing, packet validation, and encryption policy.
2. `SecureStore` owns private keys and encrypted local message history.
3. `MeshTransport` only discovers nearby peers and carries encrypted packets.
4. Platform implementations must not log plaintext messages or secret keys.

## Required implementations

| Target | Secure store | BLE adapter |
| --- | --- | --- |
| Windows | DPAPI / Credential Locker | WinRT Bluetooth LE |
| Android | Android Keystore | Android Bluetooth LE |

## Security requirements before release

- Use a reviewed encryption library; never create custom cryptography.
- Authenticate every peer identity and encrypt every payload before transport.
- Add replay protection, message expiry, size limits, rate limits, and hop limits.
- Encrypt local message history using a device-bound key.
- Obtain an independent security review before users rely on the app.

## Delivery constraint

Bluetooth mesh is only local range. Multi-hop delivery works only where nearby
devices running Sejilo can relay packets. It provides no country-wide guarantee
without a dense, physical network of relay devices.

## Reliability contracts

- Origin outboxes retain signed messages for a bounded 24-hour encounter window.
- Signed envelopes up to 144 KiB are admitted consistently by content, fragment,
  and relay layers. This includes the supported attachment envelope.
- BLE fragments for one logical packet are transmitted contiguously so control
  packets and retries cannot interleave an attachment transfer.
- Reassembly is bounded per message, by active transfer count, and by a 1 MiB
  process-wide buffer. Conflicting duplicate fragments discard the poisoned set
  so a clean retransmission can recover immediately.
- A verified direct recipient is preferred for direct messages. If that link is
  stale or rejects the write, delivery falls back to bounded mesh flooding.
- Relays exclude the ingress BLE link when notifying connected centrals, reducing
  immediate echoes while preserving duplicate suppression on alternate paths.

These contracts are intentionally compatible with the current Sejilo wire
format. Source-route topology gossip is not implemented; adding it requires a
versioned protocol change and cross-client golden-vector tests.
