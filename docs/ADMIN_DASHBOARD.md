# Admin Dashboard Guide

This guide is for administrators and operators managing SejiloChat deployments, community instances, or institutional networks.

## Table of Contents

1. [Overview](#overview)
2. [Admin Access](#admin-access)
3. [User Management](#user-management)
4. [Moderation Tools](#moderation-tools)
5. [Analytics & Monitoring](#analytics--monitoring)
6. [System Settings](#system-settings)
7. [Incident Response](#incident-response)

---

## Overview

SejiloChat is a **decentralized peer-to-peer system**. There is no central server, cloud backend, or administrative dashboard. Each device operates independently and locally.

However, operators managing deployment or community coordination may need to:

- Monitor mesh network health
- Assist users with technical issues
- Coordinate device identities for organizational use
- Track deployment metrics

This guide covers operational tools and best practices.

---

## Admin Access

### Local Administrative Tools

Since SejiloChat has no central server, administrative functions are performed locally on each device or through server relay infrastructure (if deployed).

### Deployment Models

#### Model 1: Standalone (Default)

- Each user owns their device and data
- No admin backend required
- Users manage their own privacy settings

#### Model 2: Organizational (Optional Relay)

Organizations may deploy an optional **Internet Relay Server** for extended connectivity:

```
Device A ──────┐
               │
Device B ────┬─┴──→ [Relay Server] ──→ Device C (offline)
             │
Device D ────┘
```

- Relay server is optional, not mandatory
- Messages are encrypted end-to-end; relay cannot read content
- Relay operator has no access to message bodies
- Each organization operates its own relay (no central service)

### Accessing Admin Features (Relay Deployment)

If your organization runs a relay server:

1. **SSH into relay server**:
   ```bash
   ssh admin@relay.example.com
   ```

2. **Navigate to logs directory**:
   ```bash
   cd /var/log/sejilo_relay
   ```

3. **View relay status**:
   ```bash
   systemctl status sejilo-relay
   journalctl -u sejilo-relay -f
   ```

---

## User Management

### Device Identity Management

Each SejiloChat installation creates a unique device identity:

- **Public Key**: Ed25519 public key (shared with peers)
- **Verification Code**: Human-readable 6-character code
- **Private Key**: Stored securely in device OS keystore (never exported)

### Organizational Device Registration

For deployments requiring device tracking:

1. **Record device identities**:
   - Device ID: Public key fingerprint
   - Username: User-assigned name
   - Organization: Department or group
   - Install Date: When the app was first deployed
   - Last Seen: Timestamp of last mesh activity

2. **Create device inventory**:
   ```
   Device ID        | Username   | Org      | Install Date | Last Seen
   ─────────────────┼────────────┼──────────┼──────────────┼──────────
   Lx3K2...9jP4    | alice      | Ops      | 2024-08-01   | 2024-08-24
   Mk7J9...2nQ8    | bob        | Comms    | 2024-08-05   | 2024-08-20
   ```

3. **Verify device identities**:
   - Have users share their verification code
   - Compare codes to detect impersonation or device replacement
   - Document verification date and method

### Onboarding New Users

1. **Provide installation media**: APK or Windows executable
2. **Guidance document**: Share the User Guide
3. **Verification protocol**: Establish how users will verify identities
4. **Support contact**: Provide escalation path for technical issues

### Offboarding Users

- No central revocation required (peer-to-peer system)
- Remove device from inventory
- Notify remaining users if needed
- Previously exchanged messages remain in local device storage

---

## Moderation Tools

### Local-Only Moderation

Since SejiloChat is decentralized, moderation is **not enforced centrally**. Instead:

- **Users manage their own contacts**: Block/mute features on each device
- **Peer feedback**: Users report bad behavior to you (organizational admin)
- **Local enforcement**: You advise users on privacy/safety settings

### Block & Mute Features (User-Level)

Users can locally protect themselves:

**Block a Contact**:
1. Open conversation with the peer
2. Tap **More** (⋯) → **Block**
3. Blocked peer cannot send you messages
4. Blocked peer sees you as unavailable

**Mute Notifications**:
1. Open conversation
2. Tap **More** (⋯) → **Mute**
3. Messages still arrive; notifications are suppressed
4. Useful for high-volume chats

### Abuse Reporting (Organizational)

For organizational deployments:

1. **Establish reporting process**:
   - Email address: `abuse@organization.org`
   - Incident form with fields:
     - Reporter name and contact
     - Reported user/device ID
     - Description of incident
     - Evidence (screenshots, timestamps)

2. **Investigate reported incidents**:
   - Interview reporter and reported user
   - Review local logs (if organizational relay is involved)
   - Document findings

3. **Remediation**:
   - Mediate between parties if needed
   - Advise on blocking/privacy settings
   - Remove user if severe violation (e.g., harassment policy)
   - Escalate to law enforcement if necessary

### Content Moderation

Since messages are end-to-end encrypted and stored locally:

- **No keyword filtering**: Central system cannot filter message content
- **No content retention**: Messages are not retained on any server
- **User control**: Each user deletes their own message history

Moderation is limited to:
- Responding to user complaints
- Advising on privacy features
- Removing users from organizational roster if needed

---

## Analytics & Monitoring

### Mesh Network Health

For organizational deployments, monitor mesh connectivity:

#### Relay Server Analytics (If Deployed)

```bash
# Check relay server uptime
uptime

# Monitor relay message throughput
tail -f /var/log/sejilo_relay/relay.log | grep "message_count"

# Count active devices connected to relay
ps aux | grep -E "sejilo.*relay" | wc -l
```

#### Device Connectivity Monitoring

If using an organizational relay with logging enabled:

```
Relay Log Format (anonymized):
─────────────────────────────
[2024-08-24 14:32:01] Device: Lx3K2...9jP4 | Message: type=direct | Size: 2.1KB | TTL: 2 | Status: delivered
[2024-08-24 14:32:15] Device: Mk7J9...2nQ8 | Message: type=public | Size: 156B | TTL: 1 | Status: queued
```

### Key Metrics

- **Mesh Nodes**: Count of active nearby devices
- **Message Throughput**: Messages per minute across relay
- **Delivery Success Rate**: % of messages successfully delivered
- **Average TTL (Time-to-Live)**: Hops required for delivery
- **Network Latency**: Round-trip time between device and relay
- **User Engagement**: Daily/weekly active devices

### Creating Reports

**Weekly Mesh Health Report**:

```markdown
## SejiloChat Mesh Health — Week of 2024-08-18

### Summary
- Active Devices: 42
- New Devices: 3
- Deactivated: 0
- Mesh Uptime: 99.8%

### Message Traffic
- Total Messages: 8,742
- Direct Messages: 7,120 (81%)
- Public Messages: 1,622 (19%)
- Avg Delivery Latency: 1.2s
- Success Rate: 99.5%

### Issues
- 1 relay timeout (resolved at 14:45 UTC)
- 2 user support tickets

### Recommendations
- Monitor relay server disk space (currently 78% full)
```

---

## System Settings

### Relay Server Configuration (If Deployed)

**Configuration File**: `/etc/sejilo/relay.conf`

```yaml
# SejiloChat Relay Server Configuration

server:
  port: 9000
  bind_address: 0.0.0.0
  max_connections: 1000
  connection_timeout: 300

relay:
  max_message_size: 150000  # 150 KB
  message_retention: 86400  # 24 hours (seconds)
  ttl_max: 10
  deduplication_window: 3600

logging:
  level: "info"
  format: "json"
  retention_days: 30
  # Note: Messages are not logged, only metadata
  fields_to_log:
    - timestamp
    - device_id_hash
    - message_type
    - payload_size
    - ttl
    - delivery_status

database:
  connection_string: "postgres://relay:password@localhost/sejilo"
  max_connections: 50
```

### Client-Side Settings (App)

Users can configure via **Privacy Settings**:

```
Privacy Controls
├─ Read Receipts: [Toggle]
├─ Attachment Policy: [Accept All / Ask Me / Reject All]
├─ Clear Chat History
├─ Emergency Data Wipe
└─ Device Identity Reset
```

### Organizational Policies

**Recommended Policies**:

1. **Data Retention**:
   - User discretion; default is indefinite local storage
   - Guidance: "Delete sensitive conversations after 30 days"

2. **Backup & Recovery**:
   - No centralized backup
   - Guidance: "Regularly backup your device data through OS backup"

3. **Device Security**:
   - Require device PIN/biometric lock
   - Guidance: "Enable OS-level encryption"

4. **Identity Verification**:
   - All contacts must verify via verification code in person
   - Document verification dates

---

## Incident Response

### Common Incidents

#### Incident: Device Compromised

**Signs**:
- User reports unauthorized access
- Unexpected messages appearing from user's device
- Delivery state anomalies (messages appearing delivered when not sent)

**Response**:
1. **Isolate device**: Advise user to power off device
2. **Collect evidence**: Ask user for screenshots of suspicious activity
3. **Notify contacts**: If organizational, notify users in contact list
4. **Recovery**: User should perform "Emergency Data Wipe" upon restart
5. **Follow-up**: If repeating issue, advise device OS reinstall

#### Incident: User Locked Out

**Signs**:
- User cannot access app after crash
- "Device identity not found" error on startup

**Response**:
1. **Verify recovery method**: Ask if they have device backup
2. **Recovery steps**:
   - Force close app: `Settings → Apps → SejiloChat → Force Stop`
   - Clear app cache: `Storage → Clear Cache`
   - Restart device
   - Relaunch app
3. **Last resort**: Reinstall app (loses local chat history; device identity can be recovered if they have backup)

#### Incident: Relay Server Offline

**Signs**:
- Devices cannot connect to relay
- Organizational users report extended delivery delays
- Relay status shows down

**Response**:
1. **Verify service status**:
   ```bash
   systemctl status sejilo-relay
   journalctl -u sejilo-relay -n 50
   ```

2. **Restart service**:
   ```bash
   systemctl restart sejilo-relay
   ```

3. **Check resources**:
   ```bash
   df -h  # Disk space
   free -h  # Memory
   top  # CPU usage
   ```

4. **Escalate if needed**: Contact infrastructure team

#### Incident: Mass Device Failures

**Signs**:
- Multiple users report crashes after app update
- "Panic wipe" being triggered unintentionally

**Response**:
1. **Gather data**:
   - How many users affected?
   - What build version are they running?
   - What action triggered the crash?
2. **Communicate**: Post status update if organizational
3. **Investigate**: Check release notes for known issues
4. **Recovery**: Provide rollback instructions or updated APK/executable

### Incident Log Template

```markdown
## Incident Report

**ID**: INC-2024-001
**Date**: 2024-08-24 14:30 UTC
**Severity**: High / Medium / Low
**Status**: Resolved / In Progress

### Description
[Clear description of what happened]

### Impact
- Users affected: 5
- Services affected: Mesh relay
- Duration: 23 minutes

### Root Cause
[Analysis of underlying issue]

### Resolution
[Steps taken to resolve]

### Follow-up
- [ ] Post-mortem scheduled
- [ ] Monitoring improvements planned
- [ ] Documentation updated
```

---

## Best Practices

### Security

1. **Physical Device Security**:
   - Devices should be physically secured if unattended
   - Use OS-level encryption (BitLocker on Windows, default on modern Android)
   - Require strong device PINs

2. **Identity Verification**:
   - Verify codes in person whenever possible
   - Document verification date and who verified
   - Re-verify if a user's device is replaced

3. **Relay Server Security** (if deployed):
   - Use TLS 1.3 for all relay connections
   - Rotate relay server credentials quarterly
   - Monitor relay logs for anomalies
   - Restrict relay access to authorized devices only

### Operational

1. **User Support**:
   - Establish clear escalation path (email, ticket system)
   - Maintain FAQ for common issues
   - Provide onboarding documentation

2. **Monitoring**:
   - Set up alerts for relay server downtime
   - Track mesh network size and growth
   - Monitor device version adoption

3. **Documentation**:
   - Maintain device inventory
   - Document all verification procedures
   - Keep incident logs

4. **Backup & Recovery**:
   - Test device recovery procedures monthly
   - Maintain backups of relay server configuration
   - Plan for disaster recovery (relay data loss)

---

## Troubleshooting for Admins

### Dashboard Issues

**Problem**: Cannot access relay admin interface

**Solutions**:
- Verify SSH key access: `ssh -v admin@relay.example.com`
- Check relay service: `systemctl status sejilo-relay`
- Verify firewall rules: `sudo ufw status`

### Metrics Not Updating

**Problem**: Analytics dashboard shows stale data

**Solutions**:
- Check relay service: `systemctl restart sejilo-relay`
- Verify database connection: `psql -U relay -h localhost -d sejilo`
- Check disk space: `df -h` (if full, metrics stop updating)

### User Reports Not Processing

**Problem**: Bug reports submitted but not reaching support

**Solutions**:
- Verify email configuration on relay
- Check spam folder for reports
- Confirm reporting endpoint is enabled in client config

---

## Resources

- **Relay Server Deployment**: See OPERATOR_RUNBOOK.md
- **Security Review**: See SECURITY_PRIVACY.md
- **Architecture**: See MESH_ARCHITECTURE.md (in sejilo_chat/docs)
- **API Reference**: See API_REFERENCE.md
- **Troubleshooting**: See TROUBLESHOOTING.md

---

## Version Information

- **Guide Version**: 1.0
- **SejiloChat App Version**: 0.5.0+
- **Last Updated**: August 2024
