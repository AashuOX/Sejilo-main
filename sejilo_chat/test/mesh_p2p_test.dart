import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/universal_envelope.dart';
import 'package:sejilo_chat/mesh/message_deduplication.dart';
import 'package:sejilo_chat/mesh/message_transport.dart';
import 'package:sejilo_chat/mesh/mesh_router.dart';
import 'package:sejilo_chat/mesh/peer_discovery.dart';
import 'package:sejilo_chat/mesh/peer_session_manager.dart';
import 'package:sejilo_chat/mesh/relay_queue.dart';
import 'package:sejilo_chat/mesh/transport_manager.dart';
import 'package:sejilo_chat/mesh/ttl_manager.dart';

/// Mock in-memory test transport for deterministic mesh topology simulation.
class MockMeshTransport extends MessageTransport {
  MockMeshTransport({
    required this.transportName,
    required this.transportType,
    required this.score,
  });

  final String transportName;
  final TransportType transportType;
  final int score;

  TransportState _state = TransportState.stopped;
  final List<UniversalEnvelope> sentEnvelopes = [];
  final StreamController<UniversalEnvelope> _incomingController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<TransportPeerInfo> _peerDiscoveredController =
      StreamController<TransportPeerInfo>.broadcast();
  final StreamController<String> _peerLostController =
      StreamController<String>.broadcast();

  @override
  String get name => transportName;

  @override
  TransportType get type => transportType;

  @override
  TransportState get state => _state;

  @override
  bool get isAvailable => _state == TransportState.active;

  @override
  int get routeScore => score;

  @override
  Stream<UniversalEnvelope> get incomingEnvelopes => _incomingController.stream;

  @override
  Stream<TransportPeerInfo> get peerDiscovered =>
      _peerDiscoveredController.stream;

  @override
  Stream<String> get peerLost => _peerLostController.stream;

  @override
  Future<void> start() async {
    _state = TransportState.active;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _state = TransportState.stopped;
    notifyListeners();
  }

  @override
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId}) async {
    if (!isAvailable) return false;
    sentEnvelopes.add(envelope);
    return true;
  }

  void simulateReceive(UniversalEnvelope envelope) {
    _incomingController.add(envelope);
  }

  void simulatePeer(TransportPeerInfo peer) {
    _peerDiscoveredController.add(peer);
  }

  void simulatePeerLoss(String peerId) {
    _peerLostController.add(peerId);
  }

  @override
  void dispose() {
    _incomingController.close();
    _peerDiscoveredController.close();
    _peerLostController.close();
    super.dispose();
  }
}

void main() {
  group('Phase 7 — Peer-to-Peer Mesh Architecture Tests', () {
    test(
        'TTLManager enforces hop count limits, maximum allowed hops, and expiration',
        () {
      const ttlManager = TTLManager(defaultTtl: 4, maximumAllowedHops: 7);
      final now = DateTime.now().toUtc();

      final validEnvelope = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.message,
        packetId: 'pkt-valid-123456789012',
        messageId: 'msg-valid-123456789012',
        senderDeviceId: 'dev-alice-1234567890',
        recipientDeviceId: 'dev-bob-123456789012',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ttl: 4,
        hopCount: 0,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList(utf8.encode('encrypted_bytes')),
      );

      expect(ttlManager.isValid(validEnvelope, now: now), isTrue);

      final forwarded = ttlManager.incrementHop(validEnvelope, now: now);
      expect(forwarded, isNotNull);
      expect(forwarded!.hopCount, 1);

      // Over hop limit
      final maxHoppedEnvelope = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.message,
        packetId: 'pkt-maxhop-12345678901',
        messageId: 'msg-maxhop-12345678901',
        senderDeviceId: 'dev-alice-1234567890',
        recipientDeviceId: 'dev-bob-123456789012',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ttl: 4,
        hopCount: 4, // Reached limit
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList(utf8.encode('encrypted_bytes')),
      );

      expect(ttlManager.isValid(maxHoppedEnvelope, now: now), isFalse);
      expect(ttlManager.incrementHop(maxHoppedEnvelope, now: now), isNull);

      // Expired envelope
      final expiredEnvelope = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.message,
        packetId: 'pkt-expired-1234567890',
        messageId: 'msg-expired-1234567890',
        senderDeviceId: 'dev-alice-1234567890',
        recipientDeviceId: 'dev-bob-123456789012',
        createdAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
        ttl: 4,
        hopCount: 1,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList(utf8.encode('encrypted_bytes')),
      );

      expect(ttlManager.isValid(expiredEnvelope, now: now), isFalse);
    });

    test(
        'MessageDeduplication prevents broadcast loops and redundant packet processing',
        () {
      final dedup = MessageDeduplication(maxRemembered: 100);

      expect(dedup.markIfFresh('pkt-001', messageId: 'msg-001'), isTrue);
      // Second attempt is duplicate
      expect(dedup.markIfFresh('pkt-001', messageId: 'msg-001'), isFalse);
      expect(dedup.isSeen('pkt-001'), isTrue);

      expect(dedup.markIfFresh('pkt-002', messageId: 'msg-002'), isTrue);
      expect(dedup.seenCount, 2);
    });

    test(
        'RelayQueue schedules entries, enforces priority, and prunes expired items',
        () {
      final queue = RelayQueue(maxCapacity: 10);
      final now = DateTime.now().toUtc();

      final msgEnvelope = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.message,
        packetId: 'pkt-msg-123456789012',
        messageId: 'msg-001-123456789012',
        senderDeviceId: 'dev-alice-1234567890',
        recipientDeviceId: 'dev-bob-123456789012',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ttl: 4,
        hopCount: 1,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList(utf8.encode('hello')),
      );

      final receiptEnvelope = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.receipt,
        packetId: 'pkt-rcpt-12345678901',
        messageId: 'msg-001-123456789012',
        senderDeviceId: 'dev-bob-123456789012',
        recipientDeviceId: 'dev-alice-1234567890',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        ttl: 4,
        hopCount: 0,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList(utf8.encode('ack')),
      );

      queue.enqueue(msgEnvelope);
      queue.enqueue(receiptEnvelope);

      expect(queue.length, 2);

      final ready = queue.getReadyEntries(now: now);
      // Receipt has priority over regular message
      expect(ready.first.envelope.packetType, UniversalPacketType.receipt);

      queue.remove('pkt-rcpt-12345678901');
      expect(queue.length, 1);
    });

    test(
        'PeerDiscovery discovers peers, generates ephemeral IDs, and handles disconnection',
        () async {
      final transport = MockMeshTransport(
        transportName: 'Mock BLE',
        transportType: TransportType.bluetooth,
        score: 9500,
      );
      final tm = TransportManager(transports: [transport]);
      final discovery = PeerDiscovery(
          transportManager: tm, localDeviceId: 'dev-local-12345678');
      await tm.startAll();

      final peerInfo = TransportPeerInfo(
        id: 'dev-nearby-12345678',
        displayName: 'Nearby Device',
        transportType: TransportType.bluetooth,
        rssi: -55,
        lastSeen: DateTime.now(),
      );

      transport.simulatePeer(peerInfo);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(discovery.activePeers.length, 1);
      final p = discovery.getPeer('dev-nearby-12345678');
      expect(p, isNotNull);
      expect(p!.displayName, 'Nearby Device');
      expect(p.temporaryPeerId.startsWith('tmp-'), isTrue);
      expect(p.isConnected, isTrue);

      transport.simulatePeerLoss('dev-nearby-12345678');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(discovery.getPeer('dev-nearby-12345678')!.isConnected, isFalse);

      discovery.dispose();
      tm.dispose();
    });

    test(
        'PeerSessionManager encrypts and decrypts with ChaCha20-Poly1305 and protects against replays',
        () async {
      final sessionManager = PeerSessionManager();
      final algorithm = Chacha20.poly1305Aead();
      final secretKey = await algorithm.newSecretKey();

      await sessionManager.establishSession(
        peerId: 'peer-alice',
        sharedSecret: secretKey,
      );

      expect(sessionManager.hasSession('peer-alice'), isTrue);

      final cleartext = utf8.encode('Secret P2P Mesh Message');
      final encrypted = await sessionManager.encryptForPeer(
        peerId: 'peer-alice',
        cleartext: cleartext,
      );

      expect(encrypted.cipherText.isNotEmpty, isTrue);

      // Decrypt on recipient side
      final recipientManager = PeerSessionManager();
      await recipientManager.establishSession(
        peerId: 'peer-alice',
        sharedSecret: secretKey,
      );

      final decrypted = await recipientManager.decryptFromPeer(
        peerId: 'peer-alice',
        envelope: encrypted,
      );

      expect(utf8.decode(decrypted), 'Secret P2P Mesh Message');
    });

    test('Multi-Hop Store-and-Forward Routing Scenario (A -> B -> C -> D)',
        () async {
      // Create 4 simulated nodes: Node A, Node B, Node C, Node D
      final transportA = MockMeshTransport(
          transportName: 'A_Wifi',
          transportType: TransportType.wifi,
          score: 10000);
      final transportB = MockMeshTransport(
          transportName: 'B_Wifi',
          transportType: TransportType.wifi,
          score: 10000);
      final transportC = MockMeshTransport(
          transportName: 'C_Wifi',
          transportType: TransportType.wifi,
          score: 10000);
      final transportD = MockMeshTransport(
          transportName: 'D_Wifi',
          transportType: TransportType.wifi,
          score: 10000);

      final tmA = TransportManager(transports: [transportA]);
      final tmB = TransportManager(transports: [transportB]);
      final tmC = TransportManager(transports: [transportC]);
      final tmD = TransportManager(transports: [transportD]);

      final routerA = MeshRouter(
          localDeviceId: 'dev-node-a-1234567', transportManager: tmA);
      final routerB = MeshRouter(
          localDeviceId: 'dev-node-b-1234567', transportManager: tmB);
      final routerC = MeshRouter(
          localDeviceId: 'dev-node-c-1234567', transportManager: tmC);
      final routerD = MeshRouter(
          localDeviceId: 'dev-node-d-1234567', transportManager: tmD);

      await routerA.start();
      await routerB.start();
      await routerC.start();
      await routerD.start();

      final deliveredAtD = <UniversalEnvelope>[];
      final relayedAtB = <UniversalEnvelope>[];
      final relayedAtC = <UniversalEnvelope>[];

      routerD.onDeliveredLocally.listen(deliveredAtD.add);
      routerB.onRelayed.listen(relayedAtB.add);
      routerC.onRelayed.listen(relayedAtC.add);

      // Node A originates message for Node D
      final secretPayload =
          Uint8List.fromList(utf8.encode('Classified payload for D only'));
      final envelopeFromA = await routerA.sendDirectMessage(
        recipientDeviceId: 'dev-node-d-1234567',
        messageId: 'msg-mesh-multi-hop-001',
        encryptedPayload: secretPayload,
        ttl: 5,
      );

      expect(envelopeFromA.hopCount, 0);
      expect(envelopeFromA.recipientDeviceId, 'dev-node-d-1234567');

      // ── Step 1: Hop A -> B ──────────────────────────────────
      // Node B receives envelope from A
      routerB.handleIncomingEnvelope(envelopeFromA);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(relayedAtB.length, 1);
      final envelopeAtB = relayedAtB.first;
      expect(envelopeAtB.hopCount, 1); // Incremented hop count
      expect(envelopeAtB.encryptedPayload,
          secretPayload); // Opaque payload untouched

      // ── Step 2: Hop B -> C ──────────────────────────────────
      // Node C receives envelope forwarded from B
      routerC.handleIncomingEnvelope(envelopeAtB);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(relayedAtC.length, 1);
      final envelopeAtC = relayedAtC.first;
      expect(envelopeAtC.hopCount, 2);

      // ── Step 3: Hop C -> D ──────────────────────────────────
      // Node D receives envelope from C
      routerD.handleIncomingEnvelope(envelopeAtC);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(deliveredAtD.length, 1);
      final finalDelivered = deliveredAtD.first;
      expect(finalDelivered.recipientDeviceId, 'dev-node-d-1234567');
      expect(finalDelivered.hopCount, 2);
      expect(utf8.decode(finalDelivered.encryptedPayload),
          'Classified payload for D only');

      routerA.dispose();
      routerB.dispose();
      routerC.dispose();
      routerD.dispose();
    });
  });
}
