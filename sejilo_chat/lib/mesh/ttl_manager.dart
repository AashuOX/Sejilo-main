import '../core/universal_envelope.dart';

/// Manages Hop Limits and Time-To-Live (TTL) policies for mesh packets.
/// Guarantees that packets are never forwarded indefinitely and drops expired messages.
class TTLManager {
  const TTLManager({
    this.defaultTtl = 4,
    this.maximumAllowedHops = 7,
    this.maxEncounterAge = const Duration(hours: 24),
  });

  final int defaultTtl;
  final int maximumAllowedHops;
  final Duration maxEncounterAge;

  /// Checks if the envelope is fresh and has remaining hops.
  bool isValid(UniversalEnvelope envelope, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final age = timestamp.difference(envelope.createdAt.toUtc());

    if (age.isNegative || age > maxEncounterAge) {
      return false;
    }

    if (timestamp.isAfter(envelope.expiresAt.toUtc())) {
      return false;
    }

    if (envelope.hopCount < 0 ||
        envelope.hopCount >= envelope.ttl ||
        envelope.ttl > maximumAllowedHops) {
      return false;
    }

    return true;
  }

  /// Increments hop count for store-and-forward relaying.
  /// Returns null if hop limit is reached or packet is expired.
  UniversalEnvelope? incrementHop(UniversalEnvelope envelope, {DateTime? now}) {
    if (!isValid(envelope, now: now)) {
      return null;
    }

    final newHopCount = envelope.hopCount + 1;
    if (newHopCount >= envelope.ttl) {
      // Reached maximum allowed hops for this envelope
      return null;
    }

    return UniversalEnvelope(
      protocolVersion: envelope.protocolVersion,
      packetType: envelope.packetType,
      packetId: envelope.packetId,
      messageId: envelope.messageId,
      senderDeviceId: envelope.senderDeviceId,
      recipientDeviceId: envelope.recipientDeviceId,
      groupId: envelope.groupId,
      createdAt: envelope.createdAt,
      expiresAt: envelope.expiresAt,
      ttl: envelope.ttl,
      hopCount: newHopCount,
      payloadType: envelope.payloadType,
      encryptedPayload: envelope.encryptedPayload,
    );
  }
}
