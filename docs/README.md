# SejiloChat Documentation Index

Complete documentation suite for SejiloChat — a local-first Bluetooth mesh chat application for nearby communication without internet, accounts, or servers.

## Quick Navigation

### For End Users
- **[USER_GUIDE.md](USER_GUIDE.md)** — Getting started, mesh setup, core features, privacy controls
  - System requirements, installation, username setup
  - Mesh networking basics, peer discovery, contact verification
  - Messaging features, conversations, search, reactions, pins
  - Privacy settings, data retention, troubleshooting

### For Administrators & Operators
- **[ADMIN_DASHBOARD.md](ADMIN_DASHBOARD.md)** — User management, moderation, analytics
  - Device identity management and organizational registration
  - Moderation tools and abuse reporting
  - Analytics, metrics, and system monitoring
  - Incident response procedures

- **[OPERATOR_RUNBOOK.md](OPERATOR_RUNBOOK.md)** — Deployment, operations, maintenance
  - Relay server installation and configuration
  - Monitoring, alerting, and performance tuning
  - Backup, recovery, and disaster procedures
  - Incident response playbooks

### For Security & Privacy
- **[SECURITY_PRIVACY.md](SECURITY_PRIVACY.md)** — Encryption, data protection, threat model
  - Cryptographic architecture (Ed25519, X25519, XChaCha20-Poly1305)
  - Device identity and authentication (TOFU model)
  - Data protection and retention policies
  - Known limitations and incident response
  - Best practices for users and administrators

### For Developers & Integrators
- **[API_REFERENCE.md](API_REFERENCE.md)** — REST endpoints, WebSocket events, authentication
  - Device registration and queries
  - Message sending and retrieval
  - WebSocket event subscriptions
  - Message formats and error handling
  - Code examples in Dart

- **[FREE_HOSTING.md](FREE_HOSTING.md)** — Deploying the backend on free plans
  - Render web service, Supabase Postgres, Upstash Redis
  - The `render.yaml` blueprint and what each variable does
  - Keeping the service awake and the free-tier ceilings

- **[GOOGLE_SIGNIN.md](GOOGLE_SIGNIN.md)** — Google sign-in, end to end
  - The two OAuth clients that must exist, and the one id that must match
  - Package name and SHA-1 fingerprints to register
  - Failure signatures (`ApiException: 10`, 401 `Wrong recipient`, 503)

### For Support & Problem-Solving
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — Common issues, diagnostics, FAQ
  - Connection issues and diagnostics
  - Messaging problems and solutions
  - Performance optimization
  - Platform-specific issues (Android, Windows)
  - Error codes and frequently asked questions

---

## Documentation Overview

### USER_GUIDE.md (432 lines)

**Audience**: End users, new installers

**Contents**:
- System requirements (Android 12+, Windows 10+)
- Installation and first launch
- Creating username and identity
- Mesh networking setup and peer discovery
- Messaging features (text, attachments, reactions, pins)
- Privacy controls (read receipts, attachment policy, emergency wipe)
- Common tasks and troubleshooting

**Key Sections**:
- Getting Started: Installation, permissions, initial setup
- Mesh Networking: Understanding mesh, enabling visibility, discovering peers
- Core Features: Messaging types, conversations, search, reactions
- Privacy Settings: Encryption, read receipts, attachment policy, data wipe
- Tips & Best Practices: Security recommendations and emergency procedures

### SECURITY_PRIVACY.md (691 lines)

**Audience**: Security-conscious users, admins, security reviewers

**Contents**:
- Encryption architecture and cryptographic primitives
- Device identity, key pairs, and public key management
- Direct message encryption (X25519-ECDH)
- Local message storage encryption (AES-256-GCM)
- Authentication & trust model (Trust on First Use)
- Verification codes and QR codes
- Privacy controls and data retention
- Threat model and known limitations
- Incident response procedures
- Recommended controls for high-security deployments

**Key Sections**:
- Cryptography: Algorithms, key generation, message signing
- Data Protection: Storage, retention, attachments, device identifier
- Authentication & Trust: TOFU model, verification codes, QR codes
- Privacy Controls: Message privacy, chat privacy, profile privacy, search
- Threat Model: Protected threats, unprotected threats, attack scenarios
- Limitations: Known gaps, quantum resistance, platform hardening
- Best Practices: Device hardening, network hardening, operational hardening

### ADMIN_DASHBOARD.md (539 lines)

**Audience**: Administrators, operators, organizational managers

**Contents**:
- Deployment models (standalone, organizational, hybrid)
- Device identity management and registration
- User onboarding and offboarding
- Moderation tools and abuse reporting
- Analytics and monitoring
- System settings and policies
- Incident response
- Best practices

**Key Sections**:
- Admin Access: Deployment models and relay server access
- User Management: Device tracking, organizational registration, onboarding
- Moderation Tools: Blocking, muting, abuse reporting, content moderation
- Analytics: Mesh health, message traffic, device metrics
- Incident Response: Device compromise, user lockout, relay downtime, mass failures
- Troubleshooting: Dashboard issues, metrics problems, user reports

### OPERATOR_RUNBOOK.md (776 lines)

**Audience**: System operators, DevOps, infrastructure teams

**Contents**:
- Relay server deployment and installation
- Configuration (server, TLS, relay, database, logging)
- Monitoring and alerting (Prometheus, Grafana)
- Daily, weekly, monthly maintenance tasks
- Backup and recovery procedures
- Upgrades and rollbacks
- Incident response (server down, high errors, resource issues, queue buildup)
- Disaster recovery and failover
- Best practices (security, performance, reliability)

**Key Sections**:
- Deployment: Binary/Docker installation, PostgreSQL setup, TLS configuration
- Configuration: Environment variables, DNS, firewall, performance tuning
- Monitoring: Key metrics, Prometheus queries, alerting rules, log aggregation
- Maintenance: Daily checklist, backup automation, upgrades
- Incident Response: Alert scenarios, investigation steps, recovery procedures
- Disaster Recovery: Backup strategy, RTO/RPO objectives, failover, data loss

### API_REFERENCE.md (647 lines)

**Audience**: Developers, integrators, API consumers

**Contents**:
- Authentication (device identity tokens, Ed25519 signing)
- REST endpoints (devices, messages)
- WebSocket events (incoming messages, device status, delivery)
- Message formats (direct, public, presence, attachment)
- Error handling (status codes, error responses, rate limiting)
- Code examples in Dart

**Key Sections**:
- Authentication: Token format, generation, expiration
- REST Endpoints: Device registration, queries, message send/retrieve, acknowledgment
- WebSocket Events: Message received, device status, delivery, heartbeat
- Message Formats: Direct (encrypted), public (signed), presence, attachment
- Error Handling: HTTP status codes, error response format, rate limits
- Examples: Send direct message, receive via WebSocket

### TROUBLESHOOTING.md (616 lines)

**Audience**: Support staff, end users, technical troubleshooters

**Contents**:
- Quick diagnostics (app status, Bluetooth, network)
- Connection issues (no peers, device drops, connection instability)
- Messaging issues (queued messages, delivery failures, attachments)
- Performance issues (crashes, freezing, slow loading)
- Privacy & security issues (read receipts, attachments, suspect messages)
- Platform-specific issues (Android, Windows)
- Error code reference (40+ codes with resolutions)
- FAQ (30+ common questions)
- Advanced debugging (log collection, signal analysis)

**Key Sections**:
- Quick Diagnostics: Status checks, Bluetooth verification, network testing
- Connection Issues: Peer discovery, device drops, interference
- Messaging Issues: Queued states, delivery failures, attachment errors
- Performance: Crashes, freezing, high resource usage
- Platform-Specific: Android permissions/background, Windows drivers/tray
- Error Codes: BLE, messaging, cryptography, storage, authentication, network
- FAQ: General, security, features, troubleshooting questions

---

## Documentation Statistics

| Document | Lines | Size | Purpose |
|-----------|-------|------|---------|
| USER_GUIDE.md | 432 | 13 KB | End-user guide and feature walkthrough |
| SECURITY_PRIVACY.md | 691 | 21 KB | Encryption, privacy, threat model, security |
| ADMIN_DASHBOARD.md | 539 | 14 KB | Admin operations, moderation, analytics |
| OPERATOR_RUNBOOK.md | 776 | 18 KB | Deployment, monitoring, incident response |
| API_REFERENCE.md | 647 | 14 KB | REST/WebSocket API, authentication, formats |
| TROUBLESHOOTING.md | 616 | 18 KB | Diagnostics, common issues, error codes, FAQ |
| **Total** | **3,701** | **~98 KB** | Complete documentation suite |

---

## Documentation Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SejiloChat Documentation                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐  ┌──────────────────────────────────┐│
│  │  End Users       │  │  Operators & Admins             ││
│  ├──────────────────┤  ├──────────────────────────────────┤│
│  │ USER_GUIDE.md    │  │ OPERATOR_RUNBOOK.md             ││
│  │ - Setup          │  │ - Deployment                    ││
│  │ - Mesh basics    │  │ - Monitoring                    ││
│  │ - Features       │  │ - Incidents                     ││
│  │ - Privacy        │  │                                 ││
│  │ - Troubleshoot   │  │ ADMIN_DASHBOARD.md              ││
│  │                  │  │ - User management               ││
│  │ TROUBLESHOOT.md  │  │ - Moderation                    ││
│  │ - Diagnostics    │  │ - Analytics                     ││
│  │ - Error codes    │  │                                 ││
│  │ - FAQ            │  │                                 ││
│  └──────────────────┘  └──────────────────────────────────┘│
│                                                             │
│  ┌──────────────────┐  ┌──────────────────────────────────┐│
│  │  Security        │  │  Developers                     ││
│  ├──────────────────┤  ├──────────────────────────────────┤│
│  │ SECURITY_        │  │ API_REFERENCE.md                ││
│  │ PRIVACY.md       │  │ - REST endpoints                ││
│  │ - Encryption     │  │ - WebSocket events              ││
│  │ - Authentication │  │ - Message formats               ││
│  │ - Threat model   │  │ - Error handling                ││
│  │ - Best practices │  │ - Code examples                 ││
│  │                  │  │                                 ││
│  └──────────────────┘  └──────────────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## How to Use This Documentation

### Starting Point: New User?
1. Read: **USER_GUIDE.md** (overview and setup)
2. Reference: **TROUBLESHOOTING.md** (if issues arise)
3. Explore: **SECURITY_PRIVACY.md** (understand security features)

### Starting Point: System Administrator?
1. Read: **ADMIN_DASHBOARD.md** (user management overview)
2. Reference: **OPERATOR_RUNBOOK.md** (deployment and operations)
3. Study: **SECURITY_PRIVACY.md** (security considerations)

### Starting Point: Developer Integrating API?
1. Read: **API_REFERENCE.md** (endpoints and formats)
2. Reference: **SECURITY_PRIVACY.md** (authentication details)
3. Study: Code examples in API_REFERENCE.md

### Starting Point: Security Reviewer?
1. Read: **SECURITY_PRIVACY.md** (threat model and limitations)
2. Reference: **OPERATOR_RUNBOOK.md** (operational security)
3. Study: **API_REFERENCE.md** (authentication and message formats)

### Starting Point: Troubleshooting an Issue?
1. Open: **TROUBLESHOOTING.md**
2. Find: Your specific issue or error code
3. Follow: Diagnostic steps and resolution
4. Escalate: To appropriate guide if needed

---

## Key Concepts Across Guides

### Device Identity
- **USER_GUIDE**: How to create and view your identity
- **SECURITY_PRIVACY**: Cryptographic details (Ed25519 key pairs)
- **API_REFERENCE**: Device ID tokens and authentication
- **ADMIN_DASHBOARD**: Device registration and inventory
- **TROUBLESHOOTING**: Identity not found errors

### Mesh Networking
- **USER_GUIDE**: Setting up mesh, discovering peers
- **SECURITY_PRIVACY**: Trust model and verification
- **OPERATOR_RUNBOOK**: Monitoring mesh health
- **TROUBLESHOOTING**: Peer discovery issues

### Encryption
- **SECURITY_PRIVACY**: Full technical details (algorithms, key exchange)
- **USER_GUIDE**: User-facing privacy settings
- **API_REFERENCE**: Ciphertext formats and encryption parameters
- **TROUBLESHOOTING**: Decryption failure errors

### Privacy Controls
- **USER_GUIDE**: Toggle read receipts, attachment policy, emergency wipe
- **SECURITY_PRIVACY**: Technical implementation and limitations
- **ADMIN_DASHBOARD**: Organizational policies
- **TROUBLESHOOTING**: Privacy settings issues

### Incident Response
- **SECURITY_PRIVACY**: Device compromise, key rotation
- **OPERATOR_RUNBOOK**: Relay server incidents, failover
- **ADMIN_DASHBOARD**: User support escalation
- **TROUBLESHOOTING**: Common problem resolution

---

## Document Maintenance

**Last Updated**: August 24, 2024

**Version**: 1.0

**SejiloChat Version**: 0.5.0+

**Platforms Covered**:
- Android 12 or later
- Windows 10 or later

**Scheduled Reviews**:
- Next update: January 2025 (post-security-audit)
- Quarterly reviews thereafter

**Feedback & Corrections**:
- Report documentation issues: [Support contact]
- Suggest improvements: [Community forum]
- Security feedback: [Security contact]

---

## Quick Reference: When to Use Each Guide

| Scenario | Primary Guide | Secondary Guide |
|----------|---------------|-----------------|
| I just installed SejiloChat | USER_GUIDE | TROUBLESHOOTING |
| My app is crashing | TROUBLESHOOTING | USER_GUIDE |
| I want to verify a contact securely | SECURITY_PRIVACY | USER_GUIDE |
| I need to deploy a relay server | OPERATOR_RUNBOOK | ADMIN_DASHBOARD |
| I'm integrating the API | API_REFERENCE | SECURITY_PRIVACY |
| My device was compromised | SECURITY_PRIVACY | TROUBLESHOOTING |
| I'm managing an organization | ADMIN_DASHBOARD | OPERATOR_RUNBOOK |
| I don't see nearby devices | TROUBLESHOOTING | USER_GUIDE |
| I want to understand encryption | SECURITY_PRIVACY | API_REFERENCE |
| What's the threat model? | SECURITY_PRIVACY | OPERATOR_RUNBOOK |

---

## File Locations

All documentation files are located in:
```
C:\Users\ASUS\Desktop\Sejilo-main\Sejilo-main\docs\
```

Individual files:
- `USER_GUIDE.md` — End-user walkthrough
- `SECURITY_PRIVACY.md` — Encryption and privacy details
- `ADMIN_DASHBOARD.md` — Administration and moderation
- `OPERATOR_RUNBOOK.md` — Deployment and operations
- `API_REFERENCE.md` — REST and WebSocket API
- `TROUBLESHOOTING.md` — Diagnostics and FAQ

---

## Contributing to Documentation

To improve these guides:

1. **Report errors**: [Issue tracker]
2. **Suggest improvements**: [Discussion forum]
3. **Submit corrections**: [Pull request]

Documentation is maintained in Markdown for easy version control and updates.

---

**SejiloChat Documentation Suite — Complete and Ready to Use**
