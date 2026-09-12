# API Reference

Reference guide for SejiloChat's REST API, WebSocket events, authentication, and message protocols.

## Table of Contents

1. [Overview](#overview)
2. [Authentication](#authentication)
3. [REST Endpoints](#rest-endpoints)
4. [WebSocket Events](#websocket-events)
5. [Message Formats](#message-formats)
6. [Error Handling](#error-handling)

---

## Overview

**Important**: SejiloChat is a **peer-to-peer system with optional relay server**. The REST API and WebSocket support are only available if you deploy an optional Internet Relay Server. The core app communicates over Bluetooth mesh locally.

### API Purpose

The relay server API enables:
- **Extended connectivity**: Store-and-forward for offline devices
- **Bridging**: Connect Bluetooth mesh to internet-based communication
- **Administration**: Monitor network health and synchronization
- **Relay operations**: Queue and deliver messages across internet

### Architecture

```
Device A (Bluetooth) ──────→ [Relay Server API] ──────→ Device B (Internet)
         │                          ↓
         └──────────────────────────┴─ Device C (Offline)
```

### Base URL

```
Relay Server: https://relay.example.com:9000/api/v1
WebSocket: wss://relay.example.com:9000/ws
```

---

## Authentication

### Device Identity Authentication

All API requests must include a device identity token:

**Header**: `Authorization: Bearer <DEVICE_ID_TOKEN>`

**Token Format**:
```
<DEVICE_ID>.<TIMESTAMP>.<SIGNATURE>

Where:
  DEVICE_ID: Base64-URL encoded Ed25519 public key
  TIMESTAMP: Unix timestamp (seconds since epoch)
  SIGNATURE: Ed25519 signature of "DEVICE_ID.TIMESTAMP"
```

### Token Generation (Dart Example)

```dart
import 'package:cryptography/cryptography.dart';

Future<String> generateAuthToken(SimpleKeyPairData privateKey) async {
  final algorithm = Ed25519();
  final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).toStringAsFixed(0);
  final publicKeyBytes = privateKey.publicKey.bytes;
  final deviceId = base64Url.encode(publicKeyBytes).replaceAll('=', '');
  
  final messageToSign = '$deviceId.$timestamp';
  final signature = await algorithm.sign(
    utf8.encode(messageToSign),
    keyPair: privateKey,
  );
  
  final signatureB64 = base64Url.encode(signature.bytes).replaceAll('=', '');
  return '$deviceId.$timestamp.$signatureB64';
}
```

### Token Expiration

Tokens are valid for **1 hour** from timestamp. Relay server rejects expired tokens:

```
Current time: 2024-08-24 15:30:00 UTC
Token timestamp: 2024-08-24 14:00:00 UTC (90 minutes old)
Status: REJECTED (Expired)
```

---

## REST Endpoints

### Devices

#### Register Device

**POST** `/api/v1/devices`

Register a new device identity with the relay.

**Request**:
```bash
curl -X POST https://relay.example.com:9000/api/v1/devices \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
    "username": "alice",
    "platform": "android",
    "version": "0.5.0"
  }'
```

**Response** (201 Created):
```json
{
  "id": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
  "registered_at": "2024-08-24T14:30:00Z",
  "last_seen": "2024-08-24T14:30:00Z",
  "status": "online"
}
```

#### Get Device Info

**GET** `/api/v1/devices/:device_id`

Retrieve information about a device (your own or a known peer).

**Request**:
```bash
curl -X GET https://relay.example.com:9000/api/v1/devices/Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK \
  -H "Authorization: Bearer <TOKEN>"
```

**Response** (200 OK):
```json
{
  "id": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
  "username": "alice",
  "platform": "android",
  "version": "0.5.0",
  "registered_at": "2024-08-24T14:00:00Z",
  "last_seen": "2024-08-24T14:30:00Z",
  "status": "online",
  "pending_messages": 2
}
```

#### List Online Devices

**GET** `/api/v1/devices?status=online`

List all devices currently connected to the relay.

**Response**:
```json
{
  "devices": [
    {
      "id": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
      "username": "alice",
      "status": "online",
      "last_seen": "2024-08-24T14:30:00Z"
    },
    {
      "id": "Mk7J9sK2L4mN3pQ5rS7tU9vW1xY2zA3",
      "username": "bob",
      "status": "online",
      "last_seen": "2024-08-24T14:25:00Z"
    }
  ],
  "count": 2
}
```

### Messages

#### Send Message to Device

**POST** `/api/v1/messages`

Queue a message for a device on the relay.

**Request**:
```bash
curl -X POST https://relay.example.com:9000/api/v1/messages \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
    "to": "Mk7J9sK2L4mN3pQ5rS7tU9vW1xY2zA3",
    "type": "direct",
    "body": "Hello Bob!",
    "encrypted": true,
    "ciphertext": "...",
    "ttl": 24,
    "timestamp": "2024-08-24T14:30:00Z"
  }'
```

**Response** (201 Created):
```json
{
  "id": "msg-abc123",
  "from": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
  "to": "Mk7J9sK2L4mN3pQ5rS7tU9vW1xY2zA3",
  "status": "queued",
  "queued_at": "2024-08-24T14:30:00Z"
}
```

#### Retrieve Pending Messages

**GET** `/api/v1/messages`

Retrieve all messages queued for your device.

**Request**:
```bash
curl -X GET https://relay.example.com:9000/api/v1/messages \
  -H "Authorization: Bearer <TOKEN>"
```

**Response** (200 OK):
```json
{
  "messages": [
    {
      "id": "msg-abc123",
      "from": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
      "type": "direct",
      "ciphertext": "...",
      "timestamp": "2024-08-24T14:30:00Z"
    }
  ],
  "count": 1
}
```

#### Acknowledge Message

**POST** `/api/v1/messages/:message_id/ack`

Confirm receipt of a message; relay deletes it.

**Request**:
```bash
curl -X POST https://relay.example.com:9000/api/v1/messages/msg-abc123/ack \
  -H "Authorization: Bearer <TOKEN>"
```

**Response** (200 OK):
```json
{
  "id": "msg-abc123",
  "status": "delivered"
}
```

---

## WebSocket Events

### Connection

**URL**: `wss://relay.example.com:9000/ws`

**Connect with authentication**:

```dart
import 'package:web_socket_channel/web_socket_channel.dart';

final channel = IOWebSocketChannel.connect(
  Uri.parse('wss://relay.example.com:9000/ws'),
  headers: {
    'Authorization': 'Bearer <TOKEN>'
  },
);
```

### Message Events

#### Incoming Message

**Event**: `message.received`

Fired when a message arrives for your device.

```json
{
  "type": "message.received",
  "event": {
    "id": "msg-abc123",
    "from": "Lx3K2dJqM9FbP7VnX4cY8aZ1wE5hG3jK",
    "from_username": "alice",
    "ciphertext": "...",
    "timestamp": "2024-08-24T14:30:00Z"
  }
}
```

**Handler**:
```dart
channel.stream.listen((message) {
  final event = jsonDecode(message);
  if (event['type'] == 'message.received') {
    print('Message from ${event['event']['from_username']}');
  }
});
```

#### Device Online/Offline

**Event**: `device.status_change`

Fired when a peer comes online or goes offline.

```json
{
  "type": "device.status_change",
  "event": {
    "device_id": "Mk7J9sK2L4mN3pQ5rS7tU9vW1xY2zA3",
    "username": "bob",
    "status": "online",
    "timestamp": "2024-08-24T14:31:00Z"
  }
}
```

#### Message Delivered

**Event**: `message.delivered`

Fired when a message you sent is delivered to the recipient.

```json
{
  "type": "message.delivered",
  "event": {
    "id": "msg-abc123",
    "to": "Mk7J9sK2L4mN3pQ5rS7tU9vW1xY2zA3",
    "status": "delivered",
    "timestamp": "2024-08-24T14:30:05Z"
  }
}
```

### Heartbeat

**Event**: `ping`

Relay sends a ping every 30 seconds. Respond with `pong`.

```json
{
  "type": "ping",
  "timestamp": "2024-08-24T14:30:00Z"
}
```

**Response**:
```json
{
  "type": "pong",
  "timestamp": "2024-08-24T14:30:00Z"
}
```

---

## Message Formats

### Direct Message (Encrypted)

End-to-end encrypted message between two devices.

**Fields**:
```json
{
  "type": "direct",
  "from": "<sender_device_id>",
  "to": "<recipient_device_id>",
  "body": "Optional plaintext body (usually empty)",
  "ciphertext": "<base64_encrypted_payload>",
  "encrypted": true,
  "timestamp": "2024-08-24T14:30:00Z",
  "ttl": 2,
  "signature": "<ed25519_signature_base64>"
}
```

**Ciphertext Payload** (after decryption):
```json
{
  "body": "Hello Bob!",
  "attachments": [
    {
      "id": "att-123",
      "type": "image/jpeg",
      "size": 204800,
      "checksum": "sha256:..."
    }
  ],
  "reactions": {
    "👍": 1,
    "❤": 2
  },
  "reply_to": "msg-previous-123"
}
```

### Public Message (Signed)

Message broadcast to all nearby peers; signed but not encrypted.

**Fields**:
```json
{
  "type": "public",
  "from": "<sender_device_id>",
  "from_username": "alice",
  "body": "Is anyone available for help?",
  "encrypted": false,
  "timestamp": "2024-08-24T14:30:00Z",
  "ttl": 3,
  "signature": "<ed25519_signature_base64>"
}
```

### Presence Message

Announces device presence and availability.

**Fields**:
```json
{
  "type": "presence",
  "device_id": "<device_id>",
  "username": "alice",
  "status": "online",
  "public_key": "<base64_ed25519_public_key>",
  "x25519_public_key": "<base64_x25519_public_key>",
  "timestamp": "2024-08-24T14:30:00Z",
  "signature": "<ed25519_signature_base64>"
}
```

### Attachment Message

Message containing media (photo, voice note).

**Fields**:
```json
{
  "type": "attachment",
  "from": "<sender_device_id>",
  "to": "<recipient_device_id>",
  "attachment_id": "att-abc123",
  "attachment_type": "image/jpeg",
  "attachment_size": 204800,
  "attachment_data": "<base64_encrypted_payload>",
  "encrypted": true,
  "timestamp": "2024-08-24T14:30:00Z",
  "ttl": 2,
  "signature": "<ed25519_signature_base64>"
}
```

---

## Error Handling

### HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| **200** | OK | Request succeeded |
| **201** | Created | Resource created successfully |
| **400** | Bad Request | Invalid request format; check JSON syntax |
| **401** | Unauthorized | Auth token missing, expired, or invalid |
| **403** | Forbidden | Authenticated but not authorized for this resource |
| **404** | Not Found | Resource does not exist |
| **409** | Conflict | Device ID already registered; use GET to retrieve |
| **413** | Payload Too Large | Message/attachment exceeds size limit |
| **429** | Too Many Requests | Rate limit exceeded; wait before retrying |
| **500** | Internal Server Error | Relay server error; retry after delay |
| **503** | Service Unavailable | Relay server overloaded or offline |

### Error Response Format

**Response** (400 Bad Request):
```json
{
  "error": "invalid_message_format",
  "message": "Field 'body' is required",
  "details": {
    "field": "body",
    "type": "string"
  }
}
```

### Common Errors

**Invalid Authorization Token**:
```
401 Unauthorized
{
  "error": "invalid_token",
  "message": "Token signature verification failed"
}
```

**Device Not Found**:
```
404 Not Found
{
  "error": "device_not_found",
  "message": "Device Mk7J9sK2L4mN3pQ5rS7tU9vW1xY2zA3 is not registered"
}
```

**Message Too Large**:
```
413 Payload Too Large
{
  "error": "message_too_large",
  "message": "Message size 15MB exceeds limit of 10MB",
  "limit_bytes": 10485760,
  "actual_bytes": 15728640
}
```

**Rate Limited**:
```
429 Too Many Requests
{
  "error": "rate_limited",
  "message": "Too many requests; retry after 60 seconds",
  "retry_after_seconds": 60
}
```

---

## Rate Limits

API requests are rate-limited per device:

- **Messages**: 100 per minute
- **Device queries**: 1000 per minute
- **Connections**: 10 per minute

**Response Header**:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1724165460
```

---

## Examples

### Send Direct Message via Relay

```dart
Future<void> sendDirectMessageViaRelay(
  String recipientDeviceId,
  String messageBody,
) async {
  final token = await generateAuthToken(myPrivateKey);
  
  const relayUrl = 'https://relay.example.com:9000/api/v1';
  final response = await http.post(
    Uri.parse('$relayUrl/messages'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'from': myDeviceId,
      'to': recipientDeviceId,
      'type': 'direct',
      'body': messageBody,
      'encrypted': true,
      'ciphertext': await encryptMessage(messageBody),
      'ttl': 24,
      'timestamp': DateTime.now().toIso8601String(),
    }),
  );
  
  if (response.statusCode == 201) {
    print('Message queued on relay');
  } else {
    print('Error: ${response.body}');
  }
}
```

### Receive Messages via WebSocket

```dart
Future<void> listenForMessages() async {
  final token = await generateAuthToken(myPrivateKey);
  
  final channel = IOWebSocketChannel.connect(
    Uri.parse('wss://relay.example.com:9000/ws'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  channel.stream.listen((message) {
    final event = jsonDecode(message);
    
    if (event['type'] == 'message.received') {
      final msg = event['event'];
      print('Message from ${msg['from_username']}');
      
      // Acknowledge receipt
      sendAck(msg['id']);
    }
  });
}
```

---

## Version Information

- **API Version**: 1.0
- **SejiloChat Version**: 0.5.0+
- **Last Updated**: August 2024

---

## References

- [REST best practices](https://restfulapi.net/)
- [WebSocket protocol](https://tools.ietf.org/html/rfc6455)
- [Ed25519 signatures](https://tools.ietf.org/html/rfc8032)
- [ECDH key exchange](https://tools.ietf.org/html/rfc7748)
