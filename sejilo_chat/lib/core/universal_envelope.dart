import 'dart:convert';
import 'dart:typed_data';

enum UniversalPacketType { message, receipt, groupMessage, gateway }

enum UniversalPayloadType { ciphertext, encryptedAttachmentManifest }

/// Transport-neutral packet. [encryptedPayload] must be produced by the E2EE
/// layer; transports and the relay are never allowed to receive plaintext.
class UniversalEnvelope {
  UniversalEnvelope({
    this.protocolVersion = currentProtocolVersion,
    required this.packetType,
    required this.packetId,
    required this.messageId,
    required this.senderDeviceId,
    this.recipientDeviceId,
    this.groupId,
    required this.createdAt,
    required this.expiresAt,
    required this.ttl,
    required this.hopCount,
    required this.payloadType,
    required Uint8List encryptedPayload,
  }) : encryptedPayload = Uint8List.fromList(encryptedPayload) {
    validate();
  }

  static const currentProtocolVersion = 1;
  static const maximumEncryptedPayloadBytes = 192 * 1024;
  static final _safeId = RegExp(r'^[A-Za-z0-9._~-]{3,128}$');

  final int protocolVersion;
  final UniversalPacketType packetType;
  final String packetId;
  final String messageId;
  final String senderDeviceId;
  final String? recipientDeviceId;
  final String? groupId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int ttl;
  final int hopCount;
  final UniversalPayloadType payloadType;
  final Uint8List encryptedPayload;

  bool get canRelay =>
      hopCount < ttl && DateTime.now().toUtc().isBefore(expiresAt);

  void validate({DateTime? now}) {
    if (protocolVersion != currentProtocolVersion) {
      throw FormatException('Unsupported universal protocol version.');
    }
    for (final entry in {
      'packetId': packetId,
      'messageId': messageId,
      'senderDeviceId': senderDeviceId,
    }.entries) {
      if (!_safeId.hasMatch(entry.value)) {
        throw FormatException('Invalid ${entry.key}.');
      }
    }
    final destinations =
        [recipientDeviceId, groupId].whereType<String>().toList();
    if (destinations.length != 1 || !_safeId.hasMatch(destinations.single)) {
      throw const FormatException('Exactly one valid destination is required.');
    }
    if (ttl < 0 || ttl > 32 || hopCount < 0 || hopCount > ttl) {
      throw const FormatException('Invalid hop limits.');
    }
    if (encryptedPayload.isEmpty ||
        encryptedPayload.length > maximumEncryptedPayloadBytes) {
      throw const FormatException('Encrypted payload has an invalid size.');
    }
    final utcCreated = createdAt.toUtc();
    final utcExpires = expiresAt.toUtc();
    if (!utcExpires.isAfter(utcCreated) ||
        utcExpires.difference(utcCreated) > const Duration(days: 7)) {
      throw const FormatException('Invalid envelope lifetime.');
    }
    if (now != null && !utcExpires.isAfter(now.toUtc())) {
      throw const FormatException('Envelope has expired.');
    }
  }

  Map<String, Object> toJson() => {
        'protocolVersion': protocolVersion,
        'packetType': _packetTypeToWire(packetType),
        'packetId': packetId,
        'messageId': messageId,
        'senderDeviceId': senderDeviceId,
        if (recipientDeviceId != null) 'recipientDeviceId': recipientDeviceId!,
        if (groupId != null) 'groupId': groupId!,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'ttl': ttl,
        'hopCount': hopCount,
        'payloadType': _payloadTypeToWire(payloadType),
        'encryptedPayload':
            base64Url.encode(encryptedPayload).replaceAll('=', ''),
        'contentEncoding': 'identity',
      };

  factory UniversalEnvelope.fromJson(Map<String, Object?> json) {
    const allowed = {
      'protocolVersion',
      'packetType',
      'packetId',
      'messageId',
      'senderDeviceId',
      'recipientDeviceId',
      'groupId',
      'createdAt',
      'expiresAt',
      'ttl',
      'hopCount',
      'payloadType',
      'encryptedPayload',
      'contentEncoding',
    };
    if (json.keys.any((key) => !allowed.contains(key)) ||
        json['contentEncoding'] != 'identity') {
      throw const FormatException('Unknown field or content encoding.');
    }
    try {
      final encodedPayload = json['encryptedPayload'] as String;
      if (encodedPayload.contains('=')) {
        throw const FormatException('Padded base64url.');
      }
      return UniversalEnvelope(
        protocolVersion: json['protocolVersion'] as int,
        packetType: _packetTypeFromWire(json['packetType'] as String),
        packetId: json['packetId'] as String,
        messageId: json['messageId'] as String,
        senderDeviceId: json['senderDeviceId'] as String,
        recipientDeviceId: json['recipientDeviceId'] as String?,
        groupId: json['groupId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        ttl: json['ttl'] as int,
        hopCount: json['hopCount'] as int,
        payloadType: _payloadTypeFromWire(json['payloadType'] as String),
        encryptedPayload: Uint8List.fromList(
          base64Url.decode(base64Url.normalize(encodedPayload)),
        ),
      );
    } on TypeError catch (_) {
      throw const FormatException('Malformed universal envelope.');
    }
  }

  static String _packetTypeToWire(UniversalPacketType value) => switch (value) {
        UniversalPacketType.message => 'message',
        UniversalPacketType.receipt => 'receipt',
        UniversalPacketType.groupMessage => 'group_message',
        UniversalPacketType.gateway => 'gateway',
      };

  static UniversalPacketType _packetTypeFromWire(String value) =>
      switch (value) {
        'message' => UniversalPacketType.message,
        'receipt' => UniversalPacketType.receipt,
        'group_message' => UniversalPacketType.groupMessage,
        'gateway' => UniversalPacketType.gateway,
        _ => throw const FormatException('Unknown packet type.'),
      };

  static String _payloadTypeToWire(UniversalPayloadType value) =>
      switch (value) {
        UniversalPayloadType.ciphertext => 'ciphertext',
        UniversalPayloadType.encryptedAttachmentManifest =>
          'encrypted_attachment_manifest',
      };

  static UniversalPayloadType _payloadTypeFromWire(String value) =>
      switch (value) {
        'ciphertext' => UniversalPayloadType.ciphertext,
        'encrypted_attachment_manifest' =>
          UniversalPayloadType.encryptedAttachmentManifest,
        _ => throw const FormatException('Unknown payload type.'),
      };
}
