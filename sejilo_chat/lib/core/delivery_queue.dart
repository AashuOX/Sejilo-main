import 'dart:collection';

enum DeliveryState { queued, inFlight, delivered, failed }

class QueuedPacket {
  QueuedPacket({
    required this.id,
    required this.peerId,
    required this.payload,
    required this.createdAt,
    this.state = DeliveryState.queued,
    this.attempts = 0,
    DateTime? nextAttemptAt,
  }) : nextAttemptAt = nextAttemptAt ?? createdAt;

  final String id;
  final String peerId;
  final List<int> payload;
  final DateTime createdAt;
  DeliveryState state;
  int attempts;
  DateTime nextAttemptAt;
}

/// Store-and-forward queue with explicit acknowledgements and bounded backoff.
/// Persistence is supplied by the caller so state can be committed atomically.
class DeliveryQueue {
  DeliveryQueue({
    this.maxAttempts = 8,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final LinkedHashMap<String, QueuedPacket> _items = LinkedHashMap();

  List<QueuedPacket> get items => List.unmodifiable(_items.values);

  bool enqueue(QueuedPacket packet) {
    if (packet.id.isEmpty || packet.peerId.isEmpty || packet.payload.isEmpty) {
      return false;
    }
    if (_items.containsKey(packet.id)) return false;
    _items[packet.id] = packet;
    return true;
  }

  List<QueuedPacket> ready(DateTime now) => _items.values
      .where((item) =>
          item.state != DeliveryState.delivered &&
          item.state != DeliveryState.failed &&
          !item.nextAttemptAt.isAfter(now))
      .toList(growable: false);

  void markAttempt(String id, DateTime now) {
    final item = _items[id];
    if (item == null || item.state == DeliveryState.delivered) return;
    item.attempts++;
    if (item.attempts >= maxAttempts) {
      item.state = DeliveryState.failed;
      return;
    }
    item.state = DeliveryState.inFlight;
    final exponent = (item.attempts - 1).clamp(0, 20);
    final delayMs = (baseDelay.inMilliseconds * (1 << exponent))
        .clamp(baseDelay.inMilliseconds, maxDelay.inMilliseconds);
    item.nextAttemptAt = now.add(Duration(milliseconds: delayMs));
  }

  bool acknowledge(String id) {
    final item = _items[id];
    if (item == null || item.state == DeliveryState.failed) return false;
    item.state = DeliveryState.delivered;
    return true;
  }

  void removeDelivered() {
    _items.removeWhere((_, item) => item.state == DeliveryState.delivered);
  }
}
