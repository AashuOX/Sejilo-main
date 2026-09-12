import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/delivery_transport.dart';
import 'package:sejilo_chat/core/universal_envelope.dart';

void main() {
  UniversalEnvelope envelope({int ttl = 4, int hopCount = 0}) {
    return UniversalEnvelope(
      packetType: UniversalPacketType.message,
      packetId: 'packet_1234567890',
      messageId: 'message_123456789',
      senderDeviceId: 'sender_1234567890',
      recipientDeviceId: 'recipient_1234567',
      createdAt: DateTime.utc(2026, 8, 11, 12),
      expiresAt: DateTime.utc(2026, 8, 12, 12),
      ttl: ttl,
      hopCount: hopCount,
      payloadType: UniversalPayloadType.ciphertext,
      encryptedPayload: Uint8List.fromList([1, 2, 3, 4]),
    );
  }

  test('universal envelope round trips without changing ciphertext', () {
    final original = envelope();
    final restored = UniversalEnvelope.fromJson(original.toJson());

    expect(restored.packetId, original.packetId);
    expect(restored.recipientDeviceId, original.recipientDeviceId);
    expect(restored.encryptedPayload, original.encryptedPayload);
    expect(restored.toJson(), original.toJson());
  });

  test('universal envelope rejects ambiguous destinations and excess hops', () {
    expect(
      () => UniversalEnvelope(
        packetType: UniversalPacketType.message,
        packetId: 'packet_1234567890',
        messageId: 'message_123456789',
        senderDeviceId: 'sender_1234567890',
        recipientDeviceId: 'recipient_1234567',
        groupId: 'group_12345678901',
        createdAt: DateTime.utc(2026, 8, 11),
        expiresAt: DateTime.utc(2026, 8, 12),
        ttl: 2,
        hopCount: 0,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList([1]),
      ),
      throwsFormatException,
    );
    expect(() => envelope(ttl: 2, hopCount: 3), throwsFormatException);
  });

  test('route selection ignores unavailable paths and prefers healthy LAN', () {
    const router = DeliveryRouter();
    final selected = router.best(const [
      DeliveryRoute(
        kind: DeliveryTransportKind.ble,
        state: DeliveryTransportState.unavailable,
        latency: Duration.zero,
        cost: 0,
        isMetered: false,
      ),
      DeliveryRoute(
        kind: DeliveryTransportKind.internet,
        state: DeliveryTransportState.ready,
        latency: Duration(milliseconds: 40),
        cost: 1,
        isMetered: false,
      ),
      DeliveryRoute(
        kind: DeliveryTransportKind.lan,
        state: DeliveryTransportState.ready,
        latency: Duration(milliseconds: 10),
        cost: 0,
        isMetered: false,
      ),
    ]);

    expect(selected?.kind, DeliveryTransportKind.lan);
  });
}
