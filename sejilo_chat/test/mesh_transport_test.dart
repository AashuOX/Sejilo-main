import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/mesh_transport.dart';
import 'package:sejilo_chat/core/mesh_wire_protocol.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 12);

  MeshPacket packet(
      {int hopLimit = 3, int hopsTravelled = 0, DateTime? createdAt}) {
    return MeshPacket(
      id: 'packet-1',
      senderId: 'device-a',
      ciphertext: const [1, 2, 3],
      hopLimit: hopLimit,
      hopsTravelled: hopsTravelled,
      createdAt: createdAt ?? now,
    );
  }

  test('accepts a fresh packet once and relays within its hop limit', () {
    final relay = MeshRelay();
    final original = packet();

    expect(
        relay.inspect(original, now: now), MeshPacketDecision.deliverAndRelay);
    expect(relay.inspect(original, now: now), MeshPacketDecision.duplicate);
    expect(original.forRelay()?.hopsTravelled, 1);
  });

  test('delivers but does not relay a packet at its hop limit', () {
    final relay = MeshRelay();
    final finalHop = packet(hopLimit: 2, hopsTravelled: 2);

    expect(relay.inspect(finalHop, now: now), MeshPacketDecision.deliverOnly);
    expect(finalHop.forRelay(), isNull);
  });

  test('rejects expired, future, and oversized packets', () {
    final relay = MeshRelay();
    expect(
        relay.inspect(
            packet(
                createdAt: now
                    .subtract(MeshPacket.maxAge + const Duration(seconds: 1))),
            now: now),
        MeshPacketDecision.invalid);
    expect(
        relay.inspect(packet(createdAt: now.add(const Duration(seconds: 1))),
            now: now),
        MeshPacketDecision.invalid);
    expect(
        relay.inspect(
            MeshPacket(
                id: 'large',
                senderId: 'device-a',
                ciphertext: List.filled(MeshPacket.maxCiphertextBytes + 1, 0),
                hopLimit: 1,
                createdAt: now),
            now: now),
        MeshPacketDecision.invalid);
  });

  test('keeps offline packets valid for a 24-hour encounter window', () {
    final relay = MeshRelay();

    expect(
      relay.inspect(
        packet(createdAt: now.subtract(const Duration(hours: 23))),
        now: now,
      ),
      MeshPacketDecision.deliverAndRelay,
    );
    expect(
      relay.inspect(
        MeshPacket(
          id: 'expired-after-window',
          senderId: 'device-a',
          ciphertext: const [1],
          hopLimit: 3,
          createdAt: now.subtract(
            MeshPacket.maxAge + const Duration(seconds: 1),
          ),
        ),
        now: now,
      ),
      MeshPacketDecision.invalid,
    );
  });

  test('relay admission accepts the full signed attachment envelope', () {
    expect(
      MeshPacket.maxCiphertextBytes,
      MeshContentCodec.maxEncodedBytes,
    );
    expect(
      MeshRelay().inspect(
        MeshPacket(
          id: 'large-attachment',
          senderId: 'device-a',
          ciphertext: List<int>.filled(100 * 1024, 7),
          hopLimit: 3,
          createdAt: now,
        ),
        now: now,
      ),
      MeshPacketDecision.deliverAndRelay,
    );
  });
}
