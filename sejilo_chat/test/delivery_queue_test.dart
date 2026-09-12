import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/delivery_queue.dart';

void main() {
  test('retries with bounded exponential backoff until acknowledged', () {
    final now = DateTime.utc(2026, 8, 4);
    final queue = DeliveryQueue(baseDelay: const Duration(seconds: 1));
    queue.enqueue(QueuedPacket(
        id: 'm1', peerId: 'p1', payload: const [1], createdAt: now));
    expect(queue.ready(now), hasLength(1));
    queue.markAttempt('m1', now);
    expect(queue.ready(now), isEmpty);
    expect(queue.ready(now.add(const Duration(seconds: 1))), hasLength(1));
    expect(queue.acknowledge('m1'), isTrue);
    expect(queue.items.single.state, DeliveryState.delivered);
  });

  test('rejects invalid and duplicate queue entries', () {
    final now = DateTime.utc(2026, 8, 4);
    final queue = DeliveryQueue();
    expect(
        queue.enqueue(QueuedPacket(
            id: '', peerId: 'p', payload: const [1], createdAt: now)),
        isFalse);
    final packet =
        QueuedPacket(id: 'm', peerId: 'p', payload: const [1], createdAt: now);
    expect(queue.enqueue(packet), isTrue);
    expect(queue.enqueue(packet), isFalse);
  });
}
