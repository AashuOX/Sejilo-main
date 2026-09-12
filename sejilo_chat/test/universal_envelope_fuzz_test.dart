import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/universal_envelope.dart';

void main() {
  test('malformed universal envelopes fail without unexpected exceptions', () {
    final random = Random(0x5E71);
    for (var iteration = 0; iteration < 500; iteration++) {
      final candidate = <String, Object?>{
        if (random.nextBool()) 'protocolVersion': random.nextInt(300),
        if (random.nextBool())
          'packetType': ['message', 'unknown', 4][random.nextInt(3)],
        if (random.nextBool()) 'packetId': 'x' * random.nextInt(150),
        if (random.nextBool())
          'messageId': random.nextBool() ? 42 : 'message_0123456789',
        if (random.nextBool()) 'senderDeviceId': 'sender_0123456789',
        if (random.nextBool()) 'recipientDeviceId': 'recipient_012345',
        if (random.nextBool()) 'groupId': 'group_0123456789',
        if (random.nextBool()) 'createdAt': 'not-a-date',
        if (random.nextBool()) 'expiresAt': '2026-08-12T00:00:00.000Z',
        if (random.nextBool()) 'ttl': random.nextInt(100) - 20,
        if (random.nextBool()) 'hopCount': random.nextInt(100) - 20,
        if (random.nextBool()) 'payloadType': 'ciphertext',
        if (random.nextBool())
          'encryptedPayload': random.nextBool() ? 'AQID' : '%%%bad',
        if (random.nextBool()) 'contentEncoding': 'identity',
        if (random.nextInt(8) == 0) 'unexpected': 'field',
      };
      try {
        UniversalEnvelope.fromJson(candidate);
      } on FormatException {
        // Expected fail-closed parser outcome.
      } catch (error) {
        fail('Unexpected parser exception at iteration $iteration: $error');
      }
    }
  });
}
