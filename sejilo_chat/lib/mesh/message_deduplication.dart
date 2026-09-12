import 'dart:collection';

/// Deduplicates incoming packets and envelopes to prevent broadcast flooding and loops.
class MessageDeduplication {
  MessageDeduplication({
    this.maxRemembered = 10000,
    this.retentionWindow = const Duration(hours: 24),
  });

  final int maxRemembered;
  final Duration retentionWindow;

  final LinkedHashMap<String, DateTime> _seenPacketIds = LinkedHashMap();
  final LinkedHashMap<String, DateTime> _seenMessageIds = LinkedHashMap();

  int get seenCount => _seenPacketIds.length;

  /// Checks if packet has been seen. If not seen, records it and returns true (is fresh).
  /// If already seen or duplicate, returns false.
  bool markIfFresh(String packetId, {String? messageId, DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    _pruneExpired(timestamp);

    if (_seenPacketIds.containsKey(packetId)) {
      return false;
    }
    if (messageId != null && _seenMessageIds.containsKey(messageId)) {
      return false;
    }

    _seenPacketIds[packetId] = timestamp;
    if (messageId != null) {
      _seenMessageIds[messageId] = timestamp;
    }

    while (_seenPacketIds.length > maxRemembered) {
      _seenPacketIds.remove(_seenPacketIds.keys.first);
    }
    while (_seenMessageIds.length > maxRemembered) {
      _seenMessageIds.remove(_seenMessageIds.keys.first);
    }

    return true;
  }

  bool isSeen(String packetId) => _seenPacketIds.containsKey(packetId);

  void _pruneExpired(DateTime now) {
    _seenPacketIds.removeWhere((_, time) => now.difference(time) > retentionWindow);
    _seenMessageIds.removeWhere((_, time) => now.difference(time) > retentionWindow);
  }

  void clear() {
    _seenPacketIds.clear();
    _seenMessageIds.clear();
  }
}
