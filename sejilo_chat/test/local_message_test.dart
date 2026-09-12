import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/mesh_client.dart';

void main() {
  test('new interaction metadata survives encrypted-store serialization', () {
    final message = LocalMessage(
      id: 'message-1',
      author: 'You',
      body: 'Meet at the fallback point',
      createdAt: DateTime.utc(2026, 8, 4),
      replyToId: 'message-0',
      reactions: const {'thumbs-up': 2},
      isPinned: true,
      deliveryState: 'delivered',
      conversationId: 'peer-full-fingerprint',
    );

    final decoded = LocalMessage.fromJson(message.toJson());
    expect(decoded.id, message.id);
    expect(decoded.replyToId, 'message-0');
    expect(decoded.reactions, {'thumbs-up': 2});
    expect(decoded.isPinned, isTrue);
    expect(decoded.deliveryState, 'delivered');
    expect(decoded.conversationId, 'peer-full-fingerprint');
  });

  test('legacy records receive stable IDs and safe defaults', () {
    final decoded = LocalMessage.fromJson({
      'author': 'Peer',
      'body': 'legacy',
      'createdAt': '2026-08-04T00:00:00.000Z',
      'attachmentPath': null,
      'attachmentType': null,
    });

    expect(decoded.id, isNotEmpty);
    expect(decoded.reactions, isEmpty);
    expect(decoded.deliveryState, 'delivered');
    expect(decoded.conversationId, isNull);
  });
}
