# Security & Privacy Guide

This document covers data protection, encryption architecture, privacy controls, and security considerations for SejiloChat.

## Table of Contents

1. [Overview](#overview)
2. [Encryption & Cryptography](#encryption--cryptography)
3. [Data Protection](#data-protection)
4. [Authentication & Trust](#authentication--trust)
5. [Privacy Controls](#privacy-controls)
6. [Threat Model](#threat-model)
7. [Security Limitations](#security-limitations)
8. [Incident Response](#incident-response)

---

## Overview

SejiloChat is designed with **privacy by default**:

- **No centralized server**: No single point of collection or compromise
- **Local-first storage**: All messages stored encrypted on your device
- **End-to-end encryption**: Direct messages encrypted between sender and recipient
- **No logging of content**: Operational logs contain no message bodies, keys, or identities
- **User control**: You decide what data persists and what gets wiped

**Important**: An independent security audit is not yet complete. Do not use for highly sensitive information until review is published.

---

## Encryption & Cryptography

### Cryptographic Primitives

SejiloChat uses well-reviewed, industry-standard algorithms:

| Component | Algorithm | Library | Key Size | Purpose |
|-----------|-----------|---------|----------|---------|
| Device Identity | Ed25519 | libsodium / Dart cryptography | 256-bit | Sign and authenticate all peer messages |
| Direct Message Encryption | XChaCha20-Poly1305 | libsodium / Dart cryptography | 256-bit | Encrypt direct messages (authenticated encryption) |
| Key Exchange | X25519 | libsodium / Dart cryptography | 256-bit | Establish shared keys for direct messages |
| Local Message Storage | AES-256-GCM | platform keystore | 256-bit | Encrypt messages at rest on device |
| Device Key Storage | OS Keystore | DPAPI (Windows) / Android Keystore | Varies | Secure key material storage |

### Device Identity

Each device generates two cryptographic key pairs upon first launch:

#### Ed25519 Identity Keypair

```
Generated: First launch, never regenerated (unless reset)
Storage: Android Keystore, Windows Credential Locker
Usage: Sign all outgoing messages and presence announcements
Public: Shared with peers, forms the basis of device identity
Private: Never exported, device-bound
```

**Flow**:
```
Device A                          Device B
   ↓                                 ↓
Generate Ed25519 pair         Generate Ed25519 pair
   ↓                                 ↓
Public key = Device ID        Public key = Device ID
   ↓                                 ↓
Announce: "Hello, I'm         Scan: "Found device Lx3K2..."
  Lx3K2...9jP4"                     ↓
                              Verify signature with
                              received public key
```

#### X25519 Key Exchange Pair

```
Generated: First launch, bound to Ed25519 keypair
Storage: Android Keystore, Windows Credential Locker
Usage: Establish encrypted session keys via ECDH
Public: Embedded in signed presence packets
Private: Never exported
```

### Public Message Signing

All public messages to the mesh are **signed** but **not encrypted**:

```
Message: "Is anyone available for help?"
   ↓
Sign with Ed25519 private key
   ↓
Broadcast: {
  "body": "Is anyone available for help?",
  "author": "alice",
  "signature": "4dXg9K...",
  "publicKey": "Lx3K2...9jP4"
}
   ↓
Receiver verifies signature:
  Verify(signature, publicKey, message) = True ✓
  Accept message from "alice"
```

### Direct Message Encryption (X25519-ECDH)

Direct messages between verified contacts use **static ECDH** for key establishment:

```
Device A                          Device B
(Sender)                        (Recipient)

Generate ephemeral key
   ↓
EC_DH(Device A's X25519, Device B's X25519)
            = shared_secret
   ↓
Derive session key from shared_secret
   ↓
Encrypt message with XChaCha20-Poly1305
   ↓
Send encrypted envelope
                    ────────────→
                                  ↓
                    Receive encrypted envelope
                                  ↓
                    EC_DH(Device B's X25519, Device A's X25519)
                              = shared_secret
                                  ↓
                    Derive same session key
                                  ↓
                    Decrypt message
                                  ✓ Authenticated
```

### Local Message Storage Encryption

All messages stored locally are encrypted with device-bound keys:

```
Message received/sent
   ↓
Encrypt with AES-256-GCM
  Key derived from: OS keystore + device ID
  Unique per device
   ↓
Store ciphertext in SQLite database
   ↓
[Encrypted on-disk: user@device:~/.local/share/sejilo/messages.db]
```

---

## Data Protection

### What SejiloChat Stores

**On Your Device (Encrypted)**:
- Message content and metadata (body, timestamps, attachments)
- Conversation history
- Peer identities (public keys, verification codes)
- User profile (username, display name, avatar)
- Read receipts and delivery state
- Reactions and pins

**Not Stored**:
- Messages are not backed up to cloud
- Chat history is not synced across devices
- Private keys are never exported
- Plaintext message copies outside the app database

### Data Retention

**Default**:
- Messages retained indefinitely until manually deleted
- Peer identities retained until contact is blocked/removed

**Manual Deletion**:
- Delete single message: Removes from local storage only
- Delete conversation: Removes all messages in that chat
- Clear history: Wipes all messages app-wide
- Emergency data wipe: Resets app to clean state

**Automatic Expiration**:
- Queued messages expire after 24 hours
- Relay server messages (if deployed) expire after 24 hours
- No permanent server-side storage

### Attachment Handling

**Incoming Attachments**:
- Downloaded to device storage (encrypted if local storage is encrypted)
- May be copied to device clipboard or photo library (unencrypted)
- Policy: Accept All / Ask Me / Reject All (user-configurable)

**Outgoing Attachments**:
- Encrypted before transmission (if direct message)
- Size limit: 10 MB per attachment
- Cleared from outbox after successful delivery
- Not retained on relay server (expires after 24 hours)

### Device Identifier

Each device is identified by its **Ed25519 public key**:

```
Raw bytes (32)     → "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK"
Base64-URL encoded → "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK"
Human-friendly     → Verification code "JKPM-2B"
```

**Who has your identifier**:
- ✓ You (displayed in Profile)
- ✓ Devices you've verified (contacts)
- ✓ Nearby devices scanning for peers
- ✓ Relay server operator (if deployed, encrypted)

**Who cannot see your identifier**:
- ✗ Internet service provider
- ✗ WiFi network operator
- ✗ Bluetooth network analyzer (encrypted in Bluetooth frames)

### Location Privacy

**What SejiloChat knows about location**:
- **Implicit**: Nearby peers in Bluetooth range (but not exact position)
- **Optional**: Locality group (requires explicit location permission on Android)
- **Never**: GPS coordinates, address, or precise location

**Bluetooth range indicators**:
- Typical range: 10–100 meters (varies by hardware)
- Devices connect only to physically nearby peers
- Relay server knows only that a device exists, not where it is

**Location permission (Android)**:
- Only requested if user creates a Locality Group
- Used only to suggest geographic group names
- Not shared with other peers
- Not sent to server

---

## Authentication & Trust

### Trust Model: Trust on First Use (TOFU)

SejiloChat implements **Trust on First Use** for peer verification:

```
First encounter:
─────────────────
1. Scan nearby mesh for Device B
2. Receive Device B's public key + verification code
3. You decide: "This looks right" → Add as contact
4. Future messages from that public key are trusted

Key pinning:
───────────
All future messages from Device B are verified with the same public key.
If Device B's key changes, you get a warning.
You must re-verify the new key.
```

### Verification Codes

Your verification code is derived from your public key:

```
Ed25519 public key (32 bytes)
         ↓
    Take first 5 bytes
         ↓
   Convert to base-32
         ↓
 Format as "XXXX-XX"
         ↓
Verification code: "JKPM-2B"
```

**Why compare verification codes**:
- ✓ Detects impersonation (forgery attempt gets different code)
- ✓ Works over any channel (phone call, in-person, etc.)
- ✓ Human-readable and memorable
- ✗ Does not prevent network eavesdropping (but Bluetooth is local)
- ✗ Does not authenticate through relay server

### QR Codes

Your device also generates a QR code containing:

```
QR Payload:
────────────
{
  "publicKey": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
  "username": "alice",
  "deviceId": "JKPM-2B",
  "timestamp": "2024-08-24T14:30:00Z",
  "signature": "..."
}
```

**Use cases**:
- Quickly add a contact by scanning QR code
- Verify identity (QR code should remain the same)
- Share with trusted party to establish initial contact

**Security notes**:
- QR code should be kept private
- Anyone with your QR can impersonate you (until you re-verify)
- QR code changes if device identity is reset

### Session Establishment

When you add a verified contact:

```
Step 1: Receive public key + verification code
        Tap "Add Contact"

Step 2: Compare codes in person
        "Your code: JKPM-2B"
        "Their code: JKPM-2B" ← Match!

Step 3: Confirm verification
        "Trust this device"

Step 4: Exchange session keys (X25519)
        Direct messages now encrypted

Step 5: Pin keys
        Future messages must use these keys
        Key change = warning ⚠
```

---

## Privacy Controls

### Message Privacy

**Read Receipts**:
- **Off (default)**: Peer cannot see if you've read their message
- **On**: Peer sees "read" status after you open message
- Toggle: Profile → Privacy Settings

**Message Encryption**:
- Public messages: Signed, not encrypted (visible to all peers)
- Direct messages: End-to-end encrypted (visible only to recipient)
- Voice notes: Encrypted when sent to contact (not to public)

**Attachment Policy**:
- Accept All: Download all attachments automatically
- Ask Me: Prompt before downloading
- Reject All: Do not download (metadata only)
- Configure: Profile → Privacy Settings

### Chat Privacy

**Mute Conversations**:
- Suppress notifications for a specific chat
- Messages still received and stored
- Can still search and read history

**Archive Conversations**:
- Hide conversation from main list
- Can still access via search or history
- Does not delete message content

**Block Contact**:
- Peer cannot send you messages
- Blocked peer does not see your presence
- You can unblock anytime

### Profile Privacy

**What you can hide**:
- Display name (still shows username)
- Avatar (default used instead)
- Last seen status
- Typing indicators
- Online status

**What you must share**:
- Username (required for mesh discovery)
- Verification code (derived from public key, cannot hide)
- Public key (basis of device identity)

### Data Export & Deletion

**Clear Chat History**:
- Permanently delete all local messages
- Cannot be undone
- Device identity is preserved
- Contacts see you as offline

**Emergency Data Wipe**:
- Reset app to clean state
- New device identity generated
- All contacts lost
- All messages deleted
- As if app were freshly installed

**Export Data**:
- Currently not supported in-app
- Manual workaround: Take screenshots or export SQLite database manually

### Search Privacy

**Local search only**:
- Search runs on-device only
- Results never sent to network
- Previous searches not stored
- Search index encrypted

---

## Threat Model

### Threats SejiloChat Protects Against

**Nearby eavesdropping**:
- ✓ Bluetooth traffic encrypted
- ✓ Messages signed and authenticated
- ✓ Passive eavesdropper cannot read content

**Message tampering**:
- ✓ Ed25519 signatures prevent modification
- ✓ Tampered messages rejected with signature failure
- ✓ GCM tag prevents decryption tampering

**Device impersonation**:
- ✓ Verification codes identify devices
- ✓ You verify codes in person to establish trust
- ✓ Key pinning prevents later impersonation

**Message replay**:
- ✓ Timestamps in messages
- ✓ Nonce in encryption prevents replay
- ✓ Relay deduplication prevents relay-based replay

**Passive metadata collection**:
- ✓ No server knows who you talk to
- ✓ Relay knows only that traffic occurred, not content
- ✓ Nearby peers see only Bluetooth proximity, not your location

### Threats SejiloChat Does NOT Protect Against

**Compromised device**:
- ✗ If device OS is compromised, attacker accesses all local storage
- ✗ Attacker can read decrypted messages in RAM
- **Mitigation**: Use OS-level encryption, strong device PIN, biometric lock

**Compromised Bluetooth adapter**:
- ✗ If Bluetooth driver/firmware is malicious, it could intercept traffic
- **Mitigation**: Use only trusted devices, keep OS updated

**Compromised relay server** (if deployed):
- ✗ Relay operator could log encrypted envelopes and replay them
- ✗ Relay operator could send forged messages (not verifiable without key pin)
- **Mitigation**: Trust only your own relay server, cryptographic verification of peer keys

**Global network adversary**:
- ✗ Cannot target with nationwide cellular metadata (Bluetooth is local)
- ✗ Can observe Bluetooth traffic at scale in densely populated areas
- ✗ Cannot read content (encrypted)
- **Mitigation**: Avoid high-profile locations during sensitive coordination

**Quantum computing**:
- ✗ Ed25519 and XChaCha20 are not quantum-resistant
- **Mitigation**: Post-quantum key exchange not yet implemented; may add in future

### Attack Scenarios

**Scenario 1: Man-in-the-Middle (MITM)**

```
Attacker Device:
  - Generates own Ed25519 keypair
  - Advertises as "alice"
  - Intercepts your incoming messages

Defense:
  - Verification codes prevent impersonation
  - Attacker's code = different from real alice's code
  - You notice mismatch and reject connection
```

**Scenario 2: Replay Attack**

```
Attacker:
  - Captures encrypted message between you and alice
  - Resends message to you later

Defense:
  - Nonce in XChaCha20 encryption prevents decryption
  - Timestamp in message indicates old message
  - Relay deduplication prevents multiple-hop replays
```

**Scenario 3: Device Cloning**

```
Attacker:
  - Clones your device private keys
  - Sends messages as you to your contacts

Defense:
  - Each device must be physically secured
  - If keys are compromised, use Emergency Data Wipe
  - Your contacts can re-verify your new device identity
```

---

## Security Limitations

### Known Limitations

1. **End-to-end encryption not complete**
   - Direct message encryption is implemented
   - Independent security audit is pending
   - Status: Do not use for highly sensitive information until audit complete

2. **No group encryption**
   - Locality groups are broadcast (not encrypted)
   - Only direct 1:1 messages are encrypted

3. **No voice/video calls**
   - Communication limited to text, images, voice notes
   - No real-time streaming encryption

4. **No perfect forward secrecy**
   - Session keys derived from static key exchange
   - Compromise of X25519 keys affects past messages
   - **Future**: Ephemeral key ratcheting to be added

5. **Bluetooth range limited**
   - No long-distance encryption
   - Intended for local communication only

6. **No platform hardening yet**
   - App can be debugged with debugger on development device
   - Platform-specific exploit possible (e.g., Windows Debug Privilege)
   - **Future**: App hardening with pointer authentication, code signing

### Recommended Controls for High-Security Deployments

**Device Hardening**:
- Use OS-level encryption (BitLocker on Windows, default on modern Android)
- Set strong device PIN (minimum 8 characters)
- Enable biometric authentication if available
- Disable USB debugging (if supported by app)

**Network Hardening**:
- Deploy relay server on trusted network only
- Use TLS 1.3 for relay connections
- Restrict relay access by IP whitelist
- Monitor relay logs for anomalies

**Operational Hardening**:
- Verify all device identities in person before communicating
- Use "Emergency Data Wipe" if device is compromised
- Keep app and device OS updated
- Regularly delete sensitive conversations
- Rotate device identities quarterly

---

## Incident Response

### If Your Device is Compromised

1. **Stop using SejiloChat immediately**
2. **Perform Emergency Data Wipe**:
   - Open Profile → Privacy Settings
   - Tap "Emergency Data Wipe"
   - Confirm multiple times
   - App resets to clean state
   - New device identity generated
3. **Reinstall OS** (recommended):
   - Format device and reinstall OS from trusted media
   - This ensures no rootkit persistence
4. **Notify contacts** (if trusted channel available):
   - Use phone call or in-person communication
   - "My device was compromised; I've generated a new identity"
   - Share new device verification code
5. **Verify new device**:
   - Contacts should compare new verification code with you in person

### If Your Contacts are Compromised

1. **You notice unusual messages** from their device
2. **Check their verification code**:
   - Does it match what you verified in person?
   - If code changed, device identity may be compromised
3. **Contact them out-of-band** (phone call, SMS, etc.)
   - "I received suspicious messages from your device"
   - Ask if they performed Emergency Data Wipe
4. **Block them temporarily** until verified
5. **Resume communication** only after they confirm new device identity

### If the Relay Server is Compromised (if deployed)

1. **Relay is optional**, not required
2. **Offline communication unaffected** (Bluetooth mesh still works)
3. **For relay-dependent users**:
   - Switch to offline-only communication
   - Deploy new relay server
   - Migrate users over 48 hours
4. **Rotate credentials**:
   - Update relay access tokens
   - Review audit logs for unauthorized access
   - Report incident to relevant authorities

---

## Best Practices

### For End Users

- **Verify in person**: Always compare verification codes face-to-face with new contacts
- **Use QR codes**: Scan QR codes for quick, secure contact exchange
- **Enable device encryption**: Use OS-level encryption
- **Delete sensitive conversations**: After reading, delete messages you don't need
- **Use panic wipe**: If device is lost, use Emergency Data Wipe remotely if possible
- **Keep app updated**: Security patches in new releases

### For Administrators

- **Document verification procedures**: Formalize how users verify identities
- **Audit relay server**: Monthly review of relay logs
- **Monitor device inventory**: Track device identities and verify they match users
- **Incident response plan**: Test procedures for device compromise, relay downtime
- **Security training**: Educate users on verification and privacy controls

### For Developers

- **Never create custom cryptography**: Use libsodium, NIST-approved algorithms only
- **Encrypt all data at rest**: Use device keystore and GCM for local storage
- **Verify all signatures**: Never accept unsigned messages from peers
- **No plaintext logging**: Logs should contain no message bodies, keys, or identities
- **Regular security review**: Third-party code review at least annually

---

## Compliance & Standards

### Standards Followed

- **NIST SP 800-38D**: GCM authenticated encryption
- **RFC 7748**: Elliptic curves for security (X25519, Ed25519)
- **RFC 8032**: Edwards-curve signatures
- **OWASP Top 10**: Application security best practices
- **GDPR**: Local data storage, user control, deletion on request

### Certifications

- **Security audit**: In progress (expected Q4 2024)
- **Penetration testing**: Pending
- **Code review**: Community-driven (open source)

---

## Resources

- **Cryptography Library**: Dart cryptography package (https://pub.dev/packages/cryptography)
- **Security Research**: https://paragonie.com/blog/2015/10/how-implement-ed25519-signature-authentication
- **Bluetooth Security**: https://www.bluetooth.com/specifications/security-specifications/
- **OWASP**: https://owasp.org/www-project-top-ten/

---

## Version Information

- **Guide Version**: 1.0
- **SejiloChat Version**: 0.5.0+
- **Last Updated**: August 2024
- **Next Review**: January 2025

---

## Questions or Concerns?

If you have security concerns, please report them responsibly:

1. **Do not post security issues publicly**
2. **Contact the development team** at security@sejilo.org (if available)
3. **Allow time for response and patch**
4. **Coordinate responsible disclosure** before public announcement
