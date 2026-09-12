import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/universal_envelope.dart';
import 'ttl_manager.dart';

class RelayQueueEntry {
  RelayQueueEntry({
    required this.envelope,
    DateTime? enqueuedAt,
    this.targetNextHopPeerId,
    this.attempts = 0,
    DateTime? nextAttemptAt,
  })  : enqueuedAt = (enqueuedAt ?? DateTime.now()).toUtc(),
        nextAttemptAt = (nextAttemptAt ?? enqueuedAt ?? DateTime.now()).toUtc();

  final UniversalEnvelope envelope;
  final DateTime enqueuedAt;
  final String? targetNextHopPeerId;
  int attempts;
  DateTime nextAttemptAt;

  bool isReady(DateTime now) {
    if (attempts == 0) return true; // Initial attempt is always immediately ready
    return !now.toUtc().isBefore(nextAttemptAt);
  }

  void scheduleNextAttempt(DateTime now) {
    attempts++;
    final backoffSeconds = min(300, pow(2, min(6, attempts)).toInt() + Random().nextInt(3));
    nextAttemptAt = now.toUtc().add(Duration(seconds: backoffSeconds));
  }
}

/// Bounded store-and-forward queue for mesh packet relaying.
class RelayQueue extends ChangeNotifier {
  RelayQueue({
    this.maxCapacity = 500,
    this.maxAttempts = 10,
    TTLManager? ttlManager,
  }) : _ttlManager = ttlManager ?? const TTLManager();

  final int maxCapacity;
  final int maxAttempts;
  final TTLManager _ttlManager;

  final List<RelayQueueEntry> _queue = [];

  int get length => _queue.length;
  List<RelayQueueEntry> get entries => List.unmodifiable(_queue);

  /// Enqueue an envelope for store-and-forward relaying.
  bool enqueue(UniversalEnvelope envelope, {String? targetNextHopPeerId, DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    if (!_ttlManager.isValid(envelope, now: timestamp)) {
      return false;
    }

    // Check if already in queue
    final existingIdx = _queue.indexWhere((e) => e.envelope.packetId == envelope.packetId);
    if (existingIdx >= 0) {
      return false;
    }

    // Enforce capacity limit: drop oldest non-receipt entry if full
    if (_queue.length >= maxCapacity) {
      final dropIdx = _queue.indexWhere((e) => e.envelope.packetType != UniversalPacketType.receipt);
      if (dropIdx >= 0) {
        _queue.removeAt(dropIdx);
      } else {
        _queue.removeAt(0);
      }
    }

    _queue.add(RelayQueueEntry(
      envelope: envelope,
      enqueuedAt: timestamp,
      targetNextHopPeerId: targetNextHopPeerId,
      nextAttemptAt: timestamp,
    ));

    notifyListeners();
    return true;
  }

  /// Get next batch of envelopes ready for transmission.
  List<RelayQueueEntry> getReadyEntries({DateTime? now, int limit = 20}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    _pruneExpired(timestamp);

    final ready = _queue.where((e) => e.isReady(timestamp)).take(limit).toList();
    // Prioritize receipts over general messages
    ready.sort((a, b) {
      if (a.envelope.packetType == UniversalPacketType.receipt &&
          b.envelope.packetType != UniversalPacketType.receipt) {
        return -1;
      }
      if (b.envelope.packetType == UniversalPacketType.receipt &&
          a.envelope.packetType != UniversalPacketType.receipt) {
        return 1;
      }
      return a.nextAttemptAt.compareTo(b.nextAttemptAt);
    });

    return ready;
  }

  /// Mark packet acknowledged or successfully relayed, removing it from queue.
  void remove(String packetId) {
    _queue.removeWhere((e) => e.envelope.packetId == packetId);
    notifyListeners();
  }

  /// Record a failed attempt and reschedule backoff.
  void recordFailure(String packetId, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    try {
      final entry = _queue.firstWhere((e) => e.envelope.packetId == packetId);
      entry.scheduleNextAttempt(timestamp);
      if (entry.attempts >= maxAttempts) {
        _queue.remove(entry);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _pruneExpired(DateTime now) {
    _queue.removeWhere((e) => !_ttlManager.isValid(e.envelope, now: now));
  }

  void clear() {
    _queue.clear();
    notifyListeners();
  }
}
