import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/security/secure_outbox_store.dart';

void main() {
  test('outbox items preserve retry state through serialization', () {
    final item = PersistedOutboxItem(
      messageId: 'message-1',
      signedPayload: Uint8List.fromList(const <int>[1, 2, 3]),
      createdAt: DateTime.utc(2026, 8, 10, 9),
      nextAttemptAt: DateTime.utc(2026, 8, 10, 9, 5),
      attempts: 3,
      expectedAcknowledgementFrom: 'recipient-fingerprint',
    );

    final restored = PersistedOutboxItem.fromJson(item.toJson());

    expect(restored.messageId, item.messageId);
    expect(restored.signedPayload, item.signedPayload);
    expect(restored.createdAt, item.createdAt);
    expect(restored.nextAttemptAt, item.nextAttemptAt);
    expect(restored.attempts, item.attempts);
    expect(
      restored.expectedAcknowledgementFrom,
      item.expectedAcknowledgementFrom,
    );
  });

  test('outbox items reject invalid persisted data', () {
    expect(
      () => PersistedOutboxItem.fromJson(<String, dynamic>{
        'id': '',
        'payload': 'AQ',
        'createdAt': '2026-08-10T09:00:00.000Z',
        'nextAttemptAt': '2026-08-10T09:00:00.000Z',
        'attempts': 0,
      }),
      throwsFormatException,
    );
  });
}
