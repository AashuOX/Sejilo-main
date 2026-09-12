import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/core/mesh_wire_protocol.dart';
import 'package:sejilo_chat/core/universal_envelope.dart';
import 'package:sejilo_chat/mesh/transports/bluetooth_transport.dart';
import 'package:sejilo_chat/mesh/mesh_router.dart';
import 'package:sejilo_chat/mesh/transport_manager.dart';
import 'package:sejilo_chat/security/device_identity.dart';

Future<DeviceIdentity> _createIdentity() async {
  final keyPair = await Ed25519().newKeyPair();
  final extracted = await keyPair.extract();
  return DeviceIdentity.ed25519Only(
    publicKey: await extracted.extractPublicKey(),
    keyPair: extracted,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BitChat Mesh Parity — Gossip Protocol & Topology Discovery', () {
    test('Announcement signed with direct neighbors verifies and binds signature',
        () async {
      final identity = await _createIdentity();
      final codec = MeshContentCodec();
      final now = DateTime.now().toUtc();
      final neighbors = ['peer-1111', 'peer-2222', 'peer-3333'];

      final signedBytes = await codec.sign(
        type: MeshContentType.announce,
        id: 'announce-test-001',
        author: 'Alice',
        createdAt: now,
        maxHops: 7,
        identity: identity,
        neighbors: neighbors,
      );

      final verified = await codec.decodeAndVerify(signedBytes);
      expect(verified, isNotNull);
      expect(verified!.type, MeshContentType.announce);
      expect(verified.author, 'Alice');
      expect(verified.neighbors, neighbors);
      expect(verified.senderId, identity.shortId);
    });

    test('Tampering with neighbor gossip list invalidates Ed25519 signature',
        () async {
      final identity = await _createIdentity();
      final codec = MeshContentCodec();
      final now = DateTime.now().toUtc();

      final signedBytes = await codec.sign(
        type: MeshContentType.announce,
        id: 'announce-test-002',
        author: 'Bob',
        createdAt: now,
        maxHops: 7,
        identity: identity,
        neighbors: ['peer-alice'],
      );

      // Mutate the JSON payload to simulate forged neighbors
      final decodedMap =
          jsonDecode(utf8.decode(signedBytes)) as Map<String, dynamic>;
      decodedMap['nbr'] = ['peer-alice', 'peer-mallory-forged'];
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(decodedMap)));

      final verified = await codec.decodeAndVerify(tamperedBytes);
      expect(verified, isNull,
          reason: 'Tampered neighbor list must be rejected by Ed25519 signature');
    });

    test('Neighbor gossip is rejected if exceeding 10 peers', () async {
      final identity = await _createIdentity();
      final codec = MeshContentCodec();
      final now = DateTime.now().toUtc();
      final tooManyNeighbors = List.generate(12, (i) => 'peer-$i');

      expect(
        () => codec.sign(
          type: MeshContentType.announce,
          id: 'announce-test-003',
          author: 'Eve',
          createdAt: now,
          maxHops: 7,
          identity: identity,
          neighbors: tooManyNeighbors,
        ),
        throwsArgumentError,
      );
    });

    test('Non-announcement packets reject neighbor gossip field', () async {
      final identity = await _createIdentity();
      final codec = MeshContentCodec();
      final now = DateTime.now().toUtc();

      expect(
        () => codec.sign(
          type: MeshContentType.publicMessage,
          id: 'msg-test-001',
          author: 'Alice',
          createdAt: now,
          maxHops: 7,
          identity: identity,
          body: 'Hello mesh',
          neighbors: ['peer-x'],
        ),
        throwsArgumentError,
      );
    });
  });

  group('BitChat Mesh Parity — Routing, Loop Prevention & Ingress Exclusion', () {
    test('MeshRouter loop prevention: drops packet originated by self', () {
      final tm = TransportManager();
      final router = MeshRouter(
        localDeviceId: 'my-device-id',
        transportManager: tm,
      );

      final envelopeFromSelf = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.message,
        packetId: 'pkt-self-001',
        messageId: 'msg-self-001',
        senderDeviceId: 'my-device-id',
        recipientDeviceId: 'peer-device-id',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ttl: 4,
        hopCount: 0,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList([1, 2, 3]),
      );

      var relayed = false;
      var delivered = false;
      router.onRelayed.listen((_) => relayed = true);
      router.onDeliveredLocally.listen((_) => delivered = true);

      router.handleIncomingEnvelope(envelopeFromSelf);

      expect(relayed, isFalse);
      expect(delivered, isFalse);
    });

    test('BluetoothTransport.send serializes fragments and returns true', () async {
      final transport = BluetoothTransport();
      await transport.start();

      final envelope = UniversalEnvelope(
        protocolVersion: 1,
        packetType: UniversalPacketType.message,
        packetId: 'pkt-bt-001',
        messageId: 'msg-bt-001',
        senderDeviceId: 'sender-01',
        recipientDeviceId: 'recipient-01',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ttl: 4,
        hopCount: 0,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList(utf8.encode('Hello Bluetooth Mesh')),
      );

      final sent = await transport.send(envelope);
      expect(sent, isTrue);
    });
  });
}
