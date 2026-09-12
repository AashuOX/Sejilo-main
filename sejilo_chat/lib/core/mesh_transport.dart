import 'dart:collection';

abstract interface class MeshTransport {
  Stream<MeshPeer> get peers;
  Stream<MeshPacket> get receivedPackets;

  Future<void> start();
  Future<void> stop();
  Future<void> send(MeshPacket packet);
}

class MeshPeer {
  const MeshPeer({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

class MeshPacket {
  MeshPacket({
    required this.id,
    required this.senderId,
    required List<int> ciphertext,
    required this.hopLimit,
    DateTime? createdAt,
    this.hopsTravelled = 0,
  })  : ciphertext = List.unmodifiable(ciphertext),
        createdAt = createdAt ?? DateTime.now().toUtc();

  /// Origin outboxes retain offline messages for this encounter window. Relay
  /// admission must use the same age contract or restored messages would be
  /// rejected before delivery.
  static const maxAge = Duration(hours: 24);

  /// Keep transport admission aligned with MeshContentCodec.maxEncodedBytes.
  /// The previous 24 KiB limit silently rejected valid fragmented attachments.
  static const maxCiphertextBytes = 144 * 1024;

  final String id;
  final String senderId;
  final List<int> ciphertext;
  final int hopLimit;
  final int hopsTravelled;
  final DateTime createdAt;

  bool isValidAt(DateTime now) {
    final age = now.toUtc().difference(createdAt.toUtc());
    return id.isNotEmpty &&
        senderId.isNotEmpty &&
        ciphertext.isNotEmpty &&
        ciphertext.length <= maxCiphertextBytes &&
        hopLimit >= 0 &&
        hopsTravelled >= 0 &&
        hopsTravelled <= hopLimit &&
        !age.isNegative &&
        age <= maxAge;
  }

  bool get canRelay => hopsTravelled < hopLimit;

  MeshPacket? forRelay() {
    if (!canRelay) return null;
    return MeshPacket(
      id: id,
      senderId: senderId,
      ciphertext: ciphertext,
      hopLimit: hopLimit,
      hopsTravelled: hopsTravelled + 1,
      createdAt: createdAt,
    );
  }
}

enum MeshPacketDecision { deliverAndRelay, deliverOnly, duplicate, invalid }

class MeshRelay {
  MeshRelay({this.maxRememberedPackets = 4096});

  final int maxRememberedPackets;
  final LinkedHashMap<String, DateTime> _seenPackets = LinkedHashMap();

  int get rememberedPacketCount => _seenPackets.length;

  MeshPacketDecision inspect(MeshPacket packet, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    _discardExpired(timestamp);
    if (!packet.isValidAt(timestamp)) return MeshPacketDecision.invalid;
    if (_seenPackets.containsKey(packet.id)) {
      return MeshPacketDecision.duplicate;
    }

    _seenPackets[packet.id] = packet.createdAt.toUtc();
    while (_seenPackets.length > maxRememberedPackets) {
      _seenPackets.remove(_seenPackets.keys.first);
    }
    return packet.canRelay
        ? MeshPacketDecision.deliverAndRelay
        : MeshPacketDecision.deliverOnly;
  }

  void _discardExpired(DateTime now) {
    final expiredIds = _seenPackets.entries
        .where((entry) => now.difference(entry.value) > MeshPacket.maxAge)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in expiredIds) {
      _seenPackets.remove(id);
    }
  }
}
