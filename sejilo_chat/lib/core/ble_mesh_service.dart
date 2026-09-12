import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_plugin/flutter_bluetooth_plugin.dart';

import '../security/device_identity.dart';
import '../security/peer_session.dart';
import '../security/secure_outbox_store.dart';
import '../mesh/peer_session_manager.dart';
import 'mesh_frames.dart';
import 'mesh_transport.dart';
import 'mesh_wire_protocol.dart';

class NearbyMeshPeer {
  const NearbyMeshPeer({
    required this.deviceId,
    required this.shortId,
    required this.username,
    required this.rssi,
    required this.lastSeen,
    required this.isVerified,
    required this.hops,
    this.verificationCode,
  });

  final String deviceId;
  final String shortId;
  final String username;
  final int rssi;
  final DateTime lastSeen;
  final bool isVerified;

  /// Full Ed25519 public-key fingerprint. This is present only after a signed
  /// packet from the peer has been verified.
  final String? verificationCode;

  String? get displayVerificationCode => verificationCode == null
      ? null
      : DeviceIdentity.verificationCodeForFingerprint(verificationCode!);

  /// Zero is a direct radio neighbor; larger values are verified relay depth.
  final int hops;
}

class IncomingMeshMessage {
  const IncomingMeshMessage({
    required this.id,
    required this.senderId,
    required this.senderFingerprint,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.hops,
    required this.isVerified,
    this.conversationId,
    this.attachmentType,
    this.attachmentBytes,
  });

  final String id;
  final String senderId;
  final String senderFingerprint;
  final String author;
  final String body;
  final DateTime createdAt;
  final int hops;
  final bool isVerified;
  final String? conversationId;
  final String? attachmentType;
  final Uint8List? attachmentBytes;
}

enum MeshDeliveryStatus { queued, sent, delivered, failed }

class MeshDeliveryUpdate {
  const MeshDeliveryUpdate({required this.messageId, required this.status});

  final String messageId;
  final MeshDeliveryStatus status;
}

/// Live Android/Windows BLE transport for the authenticated Sejilo v2 wire
/// protocol. Every logical payload is signed before fragmentation. Receivers
/// verify the full identity, apply expiry/duplicate/hop checks, and only then
/// deliver or relay it.
class BleMeshService extends ChangeNotifier {
  BleMeshService({
    required this.identity,
    required this.username,
    required this.outboxStore,
  });

  static const serviceUuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
  static const dataUuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d47a';
  static const cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';
  static const _defaultMaxHops = 7;
  static const _peerTtl = Duration(seconds: 60);
  static const _pendingTtl = MeshPacket.maxAge;
  static const _maxPendingMessages = 100;
  static const _maxTrackedPeers = 256;
  static const _maxPinnedPeerKeys = 512;
  static const _maxPendingAssemblies = 128;
  static const _interFragmentDelay = Duration(milliseconds: 20);
  static const _maxMessageAge = Duration(minutes: 30);
  static const _maxConnectedPeripherals = 4;
  static const _maxConnectedCentrals = 4;

  final DeviceIdentity identity;
  final String username;
  final SecureOutboxStore outboxStore;
  final FlutterBluetoothPlugin _bluetooth = FlutterBluetoothPlugin();
  final MeshContentCodec _contentCodec = MeshContentCodec();
  final MeshWireFrameCodec _wireFrameCodec = const MeshWireFrameCodec();
  final MeshFragmenter _fragmenter = const MeshFragmenter(
    maxPayloadBytes: MeshWireFrameCodec.maxFragmentPayloadBytes,
  );
  final MeshReassembler _reassembler = MeshReassembler();
  final MeshRelay _relay = MeshRelay(maxRememberedPackets: 1000);
  final HashAlgorithm _hash = Sha256();
  final Random _random = Random.secure();
  final Map<String, NearbyMeshPeer> _peers = {};
  final Map<String, String> _deviceToPeerId = {};
  final Map<String, String> _pinnedPeerKeys = {};
  final Map<String, int> _assemblyHops = {};
  final Map<String, _PendingDelivery> _pending = {};

  /// X25519 key-exchange public keys learned from peer announcements, keyed by
  /// the peer's verified fingerprint (senderId). Used to derive E2EE session
  /// keys for encrypted direct messages.
  final Map<String, List<int>> _peerX25519Keys = {};
  final PeerSessionManager _sessions = PeerSessionManager();
  final Set<String> _connecting = {};
  final Set<String> _configuringPeripherals = {};
  final Set<String> _configuredPeripherals = {};
  final Set<String> _connectedCentrals = {};
  final Set<String> _connectedPeripherals = {};
  final Map<String, Future<void>> _linkTails = {};
  final StreamController<IncomingMeshMessage> _incoming =
      StreamController.broadcast();
  final StreamController<MeshDeliveryUpdate> _deliveryUpdates =
      StreamController.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _announceTimer;
  Timer? _retryTimer;
  Timer? _cleanupTimer;
  bool _retryRunning = false;
  Future<void> _sendTail = Future<void>.value();
  bool _started = false;
  String? _error;
  int _radioScanHits = 0;
  int _scanHits = 0;
  int _receivedFrames = 0;
  int _verifiedPackets = 0;
  int _invalidFrames = 0;
  int _sentFrames = 0;
  DateTime? _lastActivity;
  String? _localGroupId;

  String get shortId => identity.shortId;

  List<NearbyMeshPeer> get peers {
    final threshold = DateTime.now().subtract(_peerTtl);
    final result = _peers.values
        .where((peer) => peer.lastSeen.isAfter(threshold))
        .toList(growable: false);
    result.sort((left, right) {
      final verified = right.isVerified ? 1 : 0;
      final leftVerified = left.isVerified ? 1 : 0;
      if (verified != leftVerified) return verified.compareTo(leftVerified);
      if (left.hops != right.hops) return left.hops.compareTo(right.hops);
      return right.rssi.compareTo(left.rssi);
    });
    return result;
  }

  bool get isStarted => _started;
  String? get error => _error;
  int get centralLinks => _connectedCentrals.length;
  int get peripheralLinks => _connectedPeripherals.length;
  int get radioScanHits => _radioScanHits;
  int get scanHits => _scanHits;
  int get receivedFrames => _receivedFrames;
  int get verifiedPackets => _verifiedPackets;
  int get invalidFrames => _invalidFrames;
  int get sentFrames => _sentFrames;
  DateTime? get lastActivity => _lastActivity;
  Stream<IncomingMeshMessage> get incoming => _incoming.stream;
  Stream<MeshDeliveryUpdate> get deliveryUpdates => _deliveryUpdates.stream;

  Future<void> restorePendingDeliveries() async {
    if (_pending.isNotEmpty) return;
    final items = await outboxStore.load();
    for (final item in items) {
      if (DateTime.now().toUtc().difference(item.createdAt) <= _pendingTtl) {
        _pending[item.messageId] = _PendingDelivery(
          messageId: item.messageId,
          signedPayload: item.signedPayload,
          createdAt: item.createdAt,
          expectedAcknowledgementFrom: item.expectedAcknowledgementFrom,
          attempts: item.attempts,
          nextAttemptAt: item.nextAttemptAt,
        );
      }
    }
    await _persistPendingDeliveries();
  }

  void setLocalGroupId(String? groupId) {
    _localGroupId = groupId;
  }

  Future<void> start() async {
    if (_started) return;
    _error = null;
    if (_subscriptions.isEmpty) {
      _subscriptions
        ..add(_bluetooth.scanResults.listen(_onScanResult))
        ..add(_bluetooth.connectionState.listen(_onConnectionState))
        ..add(_bluetooth.characteristicValues.listen(
          (event) => unawaited(
            _handleWireFrame(event.value, deviceId: event.deviceId),
          ),
        ))
        ..add(_bluetooth.gattServerRequests.listen(_onServerRequest));
    }

    String? advertisingWarning;
    try {
      final peripheralSupported = await _bluetooth.isPeripheralSupported();
      if (peripheralSupported) {
        await _bluetooth.setGattServerServices([
          BluetoothGattService(
            uuid: serviceUuid,
            characteristics: [
              BluetoothGattCharacteristic(
                uuid: dataUuid,
                serviceUuid: serviceUuid,
                properties: const [
                  'read',
                  'write',
                  'writeWithoutResponse',
                  'notify',
                ],
                permissions: const ['read', 'write'],
                descriptors: [
                  BluetoothGattDescriptor(
                    uuid: cccdUuid,
                    characteristicUuid: dataUuid,
                    value: Uint8List.fromList([0, 0]),
                  ),
                ],
              ),
            ],
          ),
        ]);
        await _bluetooth.startAdvertising(
          advertisementData: BluetoothAdvertisementData(
            localName: _advertisedName,
            serviceUuids: const [serviceUuid],
          ),
        );
      } else {
        advertisingWarning =
            'This Bluetooth adapter cannot advertise, so it will connect to nearby Sejilo advertisers instead.';
      }
    } catch (error) {
      // A Windows adapter can refuse to host a GATT service while remaining a
      // fully capable BLE scanner/client. Do not make discovery depend on
      // advertising succeeding.
      advertisingWarning =
          'Bluetooth advertising is unavailable: $error. Scanning continues.';
    }

    try {
      // Mark the receiver ready before invoking the platform scan. Windows can
      // synchronously emit already-known GATT endpoints during startScan.
      _started = true;
      // Native platforms may use this service request to supplement raw
      // advertisement callbacks with known GATT endpoints. Dart still verifies
      // every result before connecting.
      await _bluetooth.startScan(
        serviceUuids: const [serviceUuid],
        allowDuplicates: true,
      );
      _announceTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(_sendAnnouncement()),
      );
      _retryTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_retryPending()),
      );
      _cleanupTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(_cleanupStalePending()),
      );
      await _sendAnnouncement();
    } catch (error) {
      _started = false;
      _error = 'Bluetooth scanning failed to start: $error';
    }
    if (_started && advertisingWarning != null) _error = advertisingWarning;
    notifyListeners();
  }

  /// Restarts the BLE radio without changing the user's visibility choice.
  /// This is useful after Bluetooth has been toggled, permissions were just
  /// granted, or a laptop resumes from sleep.
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> stop() async {
    _started = false;
    _announceTimer?.cancel();
    _retryTimer?.cancel();
    _cleanupTimer?.cancel();
    _announceTimer = null;
    _retryTimer = null;
    _cleanupTimer = null;
    try {
      await _bluetooth.stopScan();
    } catch (_) {}
    try {
      await _bluetooth.stopAdvertising();
    } catch (_) {}
    try {
      await _bluetooth.clearGattServerServices();
    } catch (_) {}
    _connecting.clear();
    _configuringPeripherals.clear();
    _configuredPeripherals.clear();
    _connectedCentrals.clear();
    _connectedPeripherals.clear();
    _peers.clear();
    _deviceToPeerId.clear();
    notifyListeners();
  }

  String get _advertisedName {
    final safeName = username.replaceAll('|', '').trim();
    final limitedName =
        safeName.length > 10 ? safeName.substring(0, 10) : safeName;
    return 'SJ|$shortId|$limitedName';
  }

  Future<bool> broadcastMessage(
    String id,
    String body, {
    String? attachmentType,
    Uint8List? attachmentBytes,
  }) async {
    return _sendMessage(
      id: id,
      body: body,
      type: MeshContentType.publicMessage,
      attachmentType: attachmentType,
      attachmentBytes: attachmentBytes,
    );
  }

  Future<bool> sendDirectMessage(
    String id,
    String body, {
    required String recipientId,
    String? attachmentType,
    Uint8List? attachmentBytes,
  }) async {
    if (!DeviceIdentity.isValidFingerprint(recipientId)) return false;
    final trimmed = body.trim();
    if (!_started || (trimmed.isEmpty && attachmentBytes == null)) return false;

    // E2EE: encrypt the body for the recipient using a shared secret derived
    // from our X25519 key and the peer's X25519 key (learned from their
    // verified announcement). Attachments remain fail-closed: we never send
    // unencrypted attachment payloads over the mesh.
    if (attachmentBytes != null) return false;
    final peerKx = _peerX25519Keys[recipientId];
    if (peerKx == null) return false;

    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: identity.x25519KeyPair,
      remotePublicKey: SimplePublicKey(
        Uint8List.fromList(peerKx),
        type: KeyPairType.x25519,
      ),
    );
    final session = await _sessions.establishSession(
      peerId: recipientId,
      sharedSecret: sharedSecret,
    );
    final envelope = await session.encrypt(utf8.encode(trimmed));
    final encryptedBody = _encodeSessionEnvelope(envelope);

    return _sendMessage(
      id: id,
      body: encryptedBody,
      type: MeshContentType.directMessage,
      recipientId: recipientId.trim(),
      encryptedBody: true,
    );
  }

  Future<bool> sendGroupMessage(
    String id,
    String body, {
    required String groupId,
    String? attachmentType,
    Uint8List? attachmentBytes,
  }) =>
      _sendMessage(
        id: id,
        body: body,
        type: MeshContentType.groupMessage,
        groupId: groupId,
        attachmentType: attachmentType,
        attachmentBytes: attachmentBytes,
      );

  Future<bool> _sendMessage({
    required String id,
    required String body,
    required MeshContentType type,
    String? recipientId,
    String? groupId,
    String? attachmentType,
    Uint8List? attachmentBytes,
    bool encryptedBody = false,
  }) async {
    final trimmed = body.trim();
    if (!_started || (trimmed.isEmpty && attachmentBytes == null)) return false;
    try {
      final bool wantsKx = type == MeshContentType.announce ||
        type == MeshContentType.directMessage;
      final signedPayload = await _contentCodec.sign(
        type: type,
        id: id,
        author: username,
        createdAt: DateTime.now().toUtc(),
        maxHops: _defaultMaxHops,
        identity: identity,
        body: trimmed,
        recipientId: recipientId,
        groupId: groupId,
        attachmentType: attachmentType,
        attachmentBytes: attachmentBytes,
        kxPublicKey: wantsKx
            ? Uint8List.fromList(identity.x25519PublicKey.bytes)
            : null,
        encryptedBody: encryptedBody,
      );
      if (_pending.length >= _maxPendingMessages) {
        final oldest = _pending.values.reduce(
          (left, right) =>
              left.createdAt.isBefore(right.createdAt) ? left : right,
        );
        _pending.remove(oldest.messageId);
        _emitDelivery(oldest.messageId, MeshDeliveryStatus.failed);
      }
      final pending = _PendingDelivery(
        messageId: id,
        signedPayload: signedPayload,
        createdAt: DateTime.now().toUtc(),
        expectedAcknowledgementFrom: recipientId,
      );
      _pending[id] = pending;
      await _persistPendingDeliveries();
      _rememberOrigin(id, signedPayload, pending.createdAt);
      final sent = await _trySendPending(pending, DateTime.now().toUtc());
      if (!sent) _emitDelivery(id, MeshDeliveryStatus.queued);
      return sent;
    } on ArgumentError catch (error) {
      _error = error.message?.toString() ?? 'The message cannot be sent.';
      notifyListeners();
      return false;
    }
  }

  void _onScanResult(BluetoothScanResult result) {
    if (!_started) return;
    _prunePeers();
    _radioScanHits++;
    final parts = (result.localName ?? result.device.name ?? '').split('|');
    final advertisesSejilo = result.serviceUuids.any(
      (uuid) => _normaliseUuid(uuid) == serviceUuid,
    );
    if (!advertisesSejilo && (parts.length < 3 || parts.first != 'SJ')) return;
    _scanHits++;
    _lastActivity = DateTime.now();
    final hasSejiloName = parts.length >= 3 && parts.first == 'SJ';
    final advertisedId = hasSejiloName ? parts[1] : result.device.id;
    if (advertisedId == shortId) return;
    final previous = _peers[advertisedId];
    _peers[advertisedId] = NearbyMeshPeer(
      deviceId: result.device.id,
      shortId: advertisedId,
      username: hasSejiloName
          ? parts.sublist(2).join('|')
          : (result.localName ?? result.device.name ?? 'Sejilo peer'),
      rssi: result.rssi,
      lastSeen: DateTime.now(),
      isVerified: previous?.isVerified ?? false,
      hops: 0,
      verificationCode: previous?.verificationCode,
    );
    _deviceToPeerId[result.device.id] = advertisedId;
    notifyListeners();
    unawaited(_connect(result.device.id));
  }

  String _normaliseUuid(String value) =>
      value.toLowerCase().replaceAll('{', '').replaceAll('}', '').trim();

  Future<void> _connect(String deviceId) async {
    if (_connecting.contains(deviceId) ||
        _connectedPeripherals.contains(deviceId) ||
        _connectedPeripherals.length >= _maxConnectedPeripherals) {
      return;
    }
    _connecting.add(deviceId);
    try {
      await _bluetooth.connect(deviceId, timeout: const Duration(seconds: 12));
      await _preparePeripheralConnection(deviceId);
    } catch (error) {
      _error = 'Could not connect to a nearby device: $error';
      notifyListeners();
    } finally {
      _connecting.remove(deviceId);
    }
  }

  Future<void> _onConnectionState(BluetoothConnectionStateEvent event) async {
    if (event.state == BluetoothConnectionState.connected) {
      _connecting.remove(event.deviceId);
      await _preparePeripheralConnection(event.deviceId);
    } else if (event.state == BluetoothConnectionState.disconnected) {
      _connecting.remove(event.deviceId);
      _connectedPeripherals.remove(event.deviceId);
      _configuredPeripherals.remove(event.deviceId);
    }
    notifyListeners();
  }

  Future<void> _preparePeripheralConnection(String deviceId) async {
    if (_configuredPeripherals.contains(deviceId) ||
        !_configuringPeripherals.add(deviceId)) {
      return;
    }
    _connectedPeripherals.add(deviceId);
    try {
      try {
        await _bluetooth.requestMtu(deviceId, 247);
      } catch (_) {}
      final services = await _bluetooth.discoverServices(deviceId);
      if (!services.any(
        (service) => service.uuid.toLowerCase() == serviceUuid,
      )) {
        _connectedPeripherals.remove(deviceId);
        return;
      }
      try {
        await _bluetooth.setCharacteristicNotification(
          deviceId: deviceId,
          serviceUuid: serviceUuid,
          characteristicUuid: dataUuid,
          enable: true,
        );
      } catch (_) {}
      _configuredPeripherals.add(deviceId);
      await _sendAnnouncement(onlyDeviceId: deviceId);
      _error = null;
      await _retryPending();
    } catch (error) {
      _connectedPeripherals.remove(deviceId);
      _error = 'Connected, but GATT setup failed: $error';
    } finally {
      _configuringPeripherals.remove(deviceId);
      notifyListeners();
    }
  }

  void _onServerRequest(BluetoothGattServerRequest request) {
    if (request.event == 'characteristicWrite' &&
        request.characteristicUuid?.toLowerCase() == dataUuid) {
      _connectedCentrals.add(request.deviceId);
      unawaited(_handleWireFrame(request.value, deviceId: request.deviceId));
    } else if (request.event == 'subscribed') {
      _connectedCentrals.add(request.deviceId);
      unawaited(_sendAnnouncement());
      unawaited(_retryPending());
    } else if (request.event == 'unsubscribed' ||
        (request.event == 'connectionState' &&
            request.raw['state'] == 'disconnected')) {
      _connectedCentrals.remove(request.deviceId);
    } else if (request.event == 'connectionState' &&
        request.raw['state'] == 'connected') {
      if (_connectedCentrals.length < _maxConnectedCentrals) {
        _connectedCentrals.add(request.deviceId);
      }
    }
    notifyListeners();
  }

  Future<void> _handleWireFrame(
    Uint8List bytes, {
    required String deviceId,
  }) async {
    _receivedFrames++;
    _lastActivity = DateTime.now();
    final decoded = _wireFrameCodec.decode(bytes);
    if (decoded == null) {
      _invalidFrames++;
      notifyListeners();
      return;
    }
    _assemblyHops.update(
      decoded.frame.messageId,
      (current) => min(current, decoded.hopsTravelled),
      ifAbsent: () => decoded.hopsTravelled,
    );
    while (_assemblyHops.length > _maxPendingAssemblies) {
      _assemblyHops.remove(_assemblyHops.keys.first);
    }
    final assembled = _reassembler.add(decoded.frame);
    if (assembled == null) return;
    final hops =
        _assemblyHops.remove(decoded.frame.messageId) ?? decoded.hopsTravelled;
    final content = await _contentCodec.decodeAndVerify(assembled);
    if (content == null ||
        content.senderId == shortId ||
        hops > content.maxHops) {
      _invalidFrames++;
      notifyListeners();
      return;
    }

    final encodedPublicKey =
        base64Url.encode(content.publicKey.bytes).replaceAll('=', '');
    if (!_pinnedPeerKeys.containsKey(content.senderId) &&
        _pinnedPeerKeys.length >= _maxPinnedPeerKeys) {
      return;
    }
    final pinned = _pinnedPeerKeys.putIfAbsent(
      content.senderId,
      () => encodedPublicKey,
    );
    if (pinned != encodedPublicKey) return;
    _verifiedPackets++;

    // Remember the peer's X25519 key so future direct messages can be
    // encrypted to them. Learn it from both announcements and (encrypted)
    // direct messages, which also carry the sender's key-exchange key.
    if (content.kxPublicKey != null) {
      _peerX25519Keys[content.senderId] = content.kxPublicKey!;
    }

    final packet = MeshPacket(
      id: content.id,
      senderId: content.senderId,
      ciphertext: assembled,
      hopLimit: content.maxHops,
      hopsTravelled: hops,
      createdAt: content.createdAt,
    );
    final decision = _relay.inspect(packet);
    if (decision == MeshPacketDecision.invalid) return;

    _rememberVerifiedPeer(content, deviceId: deviceId, hops: hops);

    if (decision == MeshPacketDecision.duplicate) {
      if (content.type == MeshContentType.publicMessage ||
          (content.type == MeshContentType.groupMessage &&
              content.groupId == _localGroupId)) {
        await _sendAcknowledgement(content.id);
      }
      return;
    }

    if (DateTime.now().toUtc().difference(content.createdAt) > _maxMessageAge) {
      _invalidFrames++;
      notifyListeners();
      return;
    }

    // Encrypted direct messages are decrypted with a session derived from the
    // sender's X25519 key and our own key-exchange key. Legacy readable direct
    // payloads (no encryption) fail closed rather than presenting transport
    // signatures as E2EE.
    if (content.type == MeshContentType.directMessage &&
        !content.encryptedBody) {
      return;
    }

    switch (content.type) {
      case MeshContentType.announce:
        break;
      case MeshContentType.publicMessage:
        _incoming.add(IncomingMeshMessage(
          id: content.id,
          senderId: content.senderId,
          senderFingerprint: encodedPublicKey,
          author: content.author,
          body: content.body ?? '',
          createdAt: content.createdAt,
          hops: hops,
          isVerified: true,
          conversationId: null,
          attachmentType: content.attachmentType,
          attachmentBytes: content.attachmentBytes,
        ));
        await _sendAcknowledgement(content.id);
        break;
      case MeshContentType.directMessage:
        if (content.recipientId == null ||
            content.recipientId != shortId ||
            content.body == null ||
            content.kxPublicKey == null) {
          break;
        }
        try {
          final plaintext =
              await _decryptDirectMessage(content, senderFingerprint: encodedPublicKey);
          if (plaintext == null) break;
          _incoming.add(IncomingMeshMessage(
            id: content.id,
            senderId: content.senderId,
            senderFingerprint: encodedPublicKey,
            author: content.author,
            body: plaintext,
            createdAt: content.createdAt,
            hops: hops,
            isVerified: true,
            conversationId: null,
          ));
          await _sendAcknowledgement(content.id);
        } catch (_) {
          // Decryption or authentication failure: fail closed.
          break;
        }
        break;
      case MeshContentType.groupMessage:
        if (content.groupId == _localGroupId) {
          _incoming.add(IncomingMeshMessage(
            id: content.id,
            senderId: content.senderId,
            senderFingerprint: encodedPublicKey,
            author: content.author,
            body: content.body ?? '',
            createdAt: content.createdAt,
            hops: hops,
            isVerified: true,
            conversationId: 'group:${content.groupId}',
            attachmentType: content.attachmentType,
            attachmentBytes: content.attachmentBytes,
          ));
          await _sendAcknowledgement(content.id);
        }
        break;
      case MeshContentType.acknowledgement:
        final acknowledged = content.acknowledges!;
        final pending = _pending[acknowledged];
        if (pending != null &&
            (pending.expectedAcknowledgementFrom == null ||
                pending.expectedAcknowledgementFrom == encodedPublicKey)) {
          _pending.remove(acknowledged);
          await _persistPendingDeliveries();
          _emitDelivery(acknowledged, MeshDeliveryStatus.delivered);
        }
        break;
    }

    if (content.type == MeshContentType.announce && content.neighbors != null) {
      _processGossipNeighbors(content.neighbors!, announcerHops: hops);
    }

    if (decision == MeshPacketDecision.deliverAndRelay) {
      // Adaptive relay probability based on mesh density (BitChat pattern)
      final networkSize = _peers.length;
      final relayProb = switch (networkSize) {
        <= 3 => 1.0,
        <= 15 => 0.95,
        <= 30 => 0.85,
        _ => 0.65,
      };
      if (_random.nextDouble() <= relayProb) {
        // Randomized anti-collision jitter to avoid simultaneous transmissions (BitChat pattern)
        await Future<void>.delayed(
            Duration(milliseconds: 15 + _random.nextInt(65)));

        // Ingress link and author exclusion
        final authorDeviceId = _peers[content.senderId]?.hops == 0
            ? _peers[content.senderId]?.deviceId
            : null;

        await _sendSignedPayload(
          assembled,
          hopsTravelled: hops + 1,
          excludeDeviceId: deviceId,
          excludeAuthorDeviceId: authorDeviceId,
        );
      }
    }
  }

  void _rememberVerifiedPeer(
    VerifiedMeshContent content, {
    required String deviceId,
    required int hops,
  }) {
    final encodedPublicKey =
        base64Url.encode(content.publicKey.bytes).replaceAll('=', '');
    final advertisedId = _deviceToPeerId[deviceId];
    if (advertisedId != null && advertisedId != content.senderId && hops == 0) {
      final stale = _peers[advertisedId];
      if (stale?.isVerified != true) _peers.remove(advertisedId);
    }
    final previous = _peers[content.senderId];
    _peers[content.senderId] = NearbyMeshPeer(
      deviceId: hops == 0 ? deviceId : (previous?.deviceId ?? content.senderId),
      shortId: content.senderId,
      username: content.author,
      rssi: hops == 0 ? (previous?.rssi ?? 0) : (previous?.rssi ?? -127),
      lastSeen: DateTime.now(),
      isVerified: true,
      hops: hops,
      verificationCode: encodedPublicKey,
    );
    if (hops == 0) _deviceToPeerId[deviceId] = content.senderId;
    notifyListeners();

    // Immediate outbox drain when peer announces or becomes verified (BitChat StoreForward pattern)
    _drainPendingForPeer(content.senderId, encodedPublicKey);
  }

  void _drainPendingForPeer(String peerShortId, String? encodedPublicKey) {
    for (final pending in _pending.values.toList()) {
      if (pending.expectedAcknowledgementFrom == null ||
          pending.expectedAcknowledgementFrom == peerShortId ||
          (encodedPublicKey != null &&
              pending.expectedAcknowledgementFrom == encodedPublicKey)) {
        unawaited(_trySendPending(pending, DateTime.now().toUtc()));
      }
    }
  }

  void _processGossipNeighbors(List<String> neighbors, {required int announcerHops}) {
    var updated = false;
    for (final neighborId in neighbors) {
      if (neighborId == shortId) continue;
      final existing = _peers[neighborId];
      if (existing != null && existing.hops == 0) continue; // Keep direct radio link
      final computedHops = announcerHops + 1;
      if (existing == null || existing.hops > computedHops) {
        _peers[neighborId] = NearbyMeshPeer(
          deviceId: existing?.deviceId ?? neighborId,
          shortId: neighborId,
          username: existing?.username ??
              'Node ${neighborId.length > 6 ? neighborId.substring(0, 6) : neighborId}',
          rssi: -127,
          lastSeen: DateTime.now(),
          isVerified: existing?.isVerified ?? false,
          hops: computedHops,
          verificationCode: existing?.verificationCode,
        );
        updated = true;
      }
    }
    if (updated) notifyListeners();
  }

  void _prunePeers() {
    final threshold = DateTime.now().subtract(_peerTtl);
    _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(threshold));
    while (_peers.length > _maxTrackedPeers) {
      final oldest = _peers.values.reduce(
        (left, right) => left.lastSeen.isBefore(right.lastSeen) ? left : right,
      );
      _peers.remove(oldest.shortId);
    }
  }

  Future<void> _sendAnnouncement({String? onlyDeviceId}) async {
    if (!_started && onlyDeviceId == null) return;
    try {
      final now = DateTime.now().toUtc();
      final id = 'announce-$shortId-${now.microsecondsSinceEpoch}';
      final directNeighbors = _peers.values
          .where((p) => p.hops == 0 && p.shortId != shortId)
          .map((p) => p.shortId)
          .toSet()
          .take(10)
          .toList(growable: false);
      final payload = await _contentCodec.sign(
        type: MeshContentType.announce,
        id: id,
        author: username,
        createdAt: now,
        maxHops: _defaultMaxHops,
        identity: identity,
        kxPublicKey: Uint8List.fromList(identity.x25519PublicKey.bytes),
        neighbors: directNeighbors.isNotEmpty ? directNeighbors : null,
      );
      _rememberOrigin(id, payload, now);
      await _sendSignedPayload(payload,
          hopsTravelled: 0, onlyDeviceId: onlyDeviceId);
    } catch (_) {
      // Presence is retried by the periodic timer and connection events.
    }
  }

  Future<void> _sendAcknowledgement(String messageId) async {
    if (!_started) return;
    try {
      final now = DateTime.now().toUtc();
      final id = 'ack-$shortId-${now.microsecondsSinceEpoch}';
      final payload = await _contentCodec.sign(
        type: MeshContentType.acknowledgement,
        id: id,
        author: username,
        createdAt: now,
        maxHops: _defaultMaxHops,
        identity: identity,
        acknowledges: messageId,
      );
      _rememberOrigin(id, payload, now);
      await _sendSignedPayload(payload, hopsTravelled: 0);
    } catch (_) {
      // The sender's bounded retry will cause another acknowledgement chance.
    }
  }

  String _encodeSessionEnvelope(SessionEnvelope envelope) {
    final map = <String, dynamic>{
      'k': envelope.keyEpoch,
      'c': envelope.counter,
      'ct': base64Url.encode(envelope.cipherText).replaceAll('=', ''),
      'm': base64Url.encode(envelope.mac).replaceAll('=', ''),
    };
    return base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '');
  }

  SessionEnvelope? _decodeSessionEnvelope(String encoded) {
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      ) as Map<String, dynamic>;
      return SessionEnvelope(
        keyEpoch: decoded['k'] as int,
        counter: decoded['c'] as int,
        cipherText:
            base64Url.decode(base64Url.normalize(decoded['ct'] as String)),
        mac: base64Url.decode(base64Url.normalize(decoded['m'] as String)),
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _decryptDirectMessage(
    VerifiedMeshContent content, {
    required String senderFingerprint,
  }) async {
    if (content.body == null || content.kxPublicKey == null) return null;
    final envelope = _decodeSessionEnvelope(content.body!);
    if (envelope == null) return null;

    try {
      final sharedSecret = await X25519().sharedSecretKey(
        keyPair: identity.x25519KeyPair,
        remotePublicKey: SimplePublicKey(
          Uint8List.fromList(content.kxPublicKey!),
          type: KeyPairType.x25519,
        ),
      );
      final session = await _sessions.establishSession(
        peerId: content.senderId,
        sharedSecret: sharedSecret,
      );
      final plaintext = await session.decrypt(envelope);
      return utf8.decode(plaintext, allowMalformed: false);
    } on Object {
      return null;
    }
  }

  void _rememberOrigin(String id, Uint8List payload, DateTime createdAt) {
    _relay.inspect(MeshPacket(
      id: id,
      senderId: shortId,
      ciphertext: payload,
      hopLimit: _defaultMaxHops,
      createdAt: createdAt,
    ));
  }

  Future<bool> _sendSignedPayload(
    Uint8List signedPayload, {
    required int hopsTravelled,
    String? excludeDeviceId,
    String? excludeAuthorDeviceId,
    String? onlyDeviceId,
  }) {
    // If targeted to a single device, serialize solely on that device's queue
    if (onlyDeviceId != null) {
      final prev = _linkTails[onlyDeviceId] ?? Future<void>.value();
      final completer = Completer<bool>();
      final next = prev.then((_) async {
        try {
          final res = await _sendSignedPayloadNow(
            signedPayload,
            hopsTravelled: hopsTravelled,
            excludeDeviceId: excludeDeviceId,
            excludeAuthorDeviceId: excludeAuthorDeviceId,
            onlyDeviceId: onlyDeviceId,
          );
          completer.complete(res);
        } catch (e, st) {
          completer.completeError(e, st);
        }
      });
      _linkTails[onlyDeviceId] = next.catchError((_) {});
      return completer.future;
    }

    // Keep all fragments of one logical packet contiguous. Android permits
    // only one outstanding GATT operation per link, and interleaving an
    // announcement or retry with an attachment increases loss dramatically.
    final operation = _sendTail.then(
      (_) => _sendSignedPayloadNow(
        signedPayload,
        hopsTravelled: hopsTravelled,
        excludeDeviceId: excludeDeviceId,
        excludeAuthorDeviceId: excludeAuthorDeviceId,
        onlyDeviceId: onlyDeviceId,
      ),
    );
    _sendTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<bool> _sendSignedPayloadNow(
    Uint8List signedPayload, {
    required int hopsTravelled,
    String? excludeDeviceId,
    String? excludeAuthorDeviceId,
    String? onlyDeviceId,
  }) async {
    final digest = await _hash.hash(signedPayload);
    final transferId = _wireFrameCodec.transferIdForDigest(digest.bytes);
    final fragments = _fragmenter.fragment(
      messageId: transferId,
      ciphertext: signedPayload,
    );
    var sentAll = true;
    for (var index = 0; index < fragments.length; index++) {
      final fragment = fragments[index];
      final frame = _wireFrameCodec.encode(
        fragment,
        hopsTravelled: hopsTravelled,
      );
      final sent = await _transmitFrame(
        frame,
        excludeDeviceId: excludeDeviceId,
        excludeAuthorDeviceId: excludeAuthorDeviceId,
        onlyDeviceId: onlyDeviceId,
      );
      if (!sent) {
        sentAll = false;
        break;
      }
      if (index + 1 < fragments.length) {
        await Future<void>.delayed(_interFragmentDelay);
      }
    }
    return sentAll;
  }

  Future<bool> _transmitFrame(
    Uint8List frame, {
    String? excludeDeviceId,
    String? excludeAuthorDeviceId,
    String? onlyDeviceId,
  }) async {
    var sent = false;
    final peripherals = onlyDeviceId == null
        ? List<String>.from(_connectedPeripherals)
        : <String>[onlyDeviceId];
    for (final deviceId in peripherals) {
      if (deviceId == excludeDeviceId ||
          deviceId == excludeAuthorDeviceId ||
          !_connectedPeripherals.contains(deviceId)) {
        continue;
      }
      try {
        await _bluetooth.writeCharacteristic(
          deviceId: deviceId,
          serviceUuid: serviceUuid,
          characteristicUuid: dataUuid,
          value: frame,
        );
        sent = true;
        _sentFrames++;
        _lastActivity = DateTime.now();
      } catch (_) {
        _connectedPeripherals.remove(deviceId);
      }
    }
    final centrals = onlyDeviceId == null
        ? List<String>.from(_connectedCentrals)
        : <String>[onlyDeviceId];
    for (final deviceId in centrals) {
      if (deviceId == excludeDeviceId ||
          deviceId == excludeAuthorDeviceId ||
          !_connectedCentrals.contains(deviceId)) {
        continue;
      }
      try {
        final notified = await _bluetooth.notifyGattServerCharacteristic(
          deviceId: deviceId,
          serviceUuid: serviceUuid,
          characteristicUuid: dataUuid,
          value: frame,
          confirm: false,
        );
        if (notified) {
          _sentFrames++;
          _lastActivity = DateTime.now();
        }
        sent = notified || sent;
      } catch (_) {
        // Other links can still carry the packet.
      }
    }
    return sent;
  }

  Future<bool> _trySendPending(
    _PendingDelivery pending,
    DateTime now,
  ) async {
    if (now.difference(pending.createdAt) > _pendingTtl) {
      _pending.remove(pending.messageId);
      await _persistPendingDeliveries();
      _emitDelivery(pending.messageId, MeshDeliveryStatus.failed);
      return false;
    }
    if (now.difference(pending.createdAt) > _maxMessageAge) {
      _pending.remove(pending.messageId);
      await _persistPendingDeliveries();
      _emitDelivery(pending.messageId, MeshDeliveryStatus.failed);
      return false;
    }
    if (_connectedPeripherals.isEmpty && _connectedCentrals.isEmpty) {
      pending.nextAttemptAt = now.add(const Duration(seconds: 2));
      await _persistPendingDeliveries();
      return false;
    }
    final directDeviceId = pending.expectedAcknowledgementFrom == null
        ? null
        : _directDeviceIdForFingerprint(
            pending.expectedAcknowledgementFrom!,
          );
    var sent = await _sendSignedPayload(
      pending.signedPayload,
      hopsTravelled: 0,
      onlyDeviceId: directDeviceId,
    );
    if (!sent && directDeviceId != null) {
      // A stale direct route must not prevent delivery through another relay.
      sent = await _sendSignedPayload(
        pending.signedPayload,
        hopsTravelled: 0,
      );
    }
    pending.attempts++;
    final seconds = min(300, 2 * (1 << min(pending.attempts - 1, 8)));
    pending.nextAttemptAt = now.add(Duration(seconds: seconds));
    await _persistPendingDeliveries();
    _emitDelivery(
      pending.messageId,
      sent ? MeshDeliveryStatus.sent : MeshDeliveryStatus.queued,
    );
    return sent;
  }

  String? _directDeviceIdForFingerprint(String fingerprintOrShortId) {
    for (final peer in _peers.values) {
      final matches = peer.verificationCode == fingerprintOrShortId ||
          peer.shortId == fingerprintOrShortId;
      if (peer.hops == 0 &&
          matches &&
          (_connectedPeripherals.contains(peer.deviceId) ||
              _connectedCentrals.contains(peer.deviceId))) {
        return peer.deviceId;
      }
    }
    return null;
  }

  Future<void> _cleanupStalePending() async {
    final now = DateTime.now().toUtc();
    final stale = _pending.entries
        .where((entry) => now.difference(entry.value.createdAt) > _maxMessageAge)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final messageId in stale) {
      _pending.remove(messageId);
      _emitDelivery(messageId, MeshDeliveryStatus.failed);
    }
    if (stale.isNotEmpty) {
      await _persistPendingDeliveries();
    }
  }

  Future<void> _retryPending() async {
    if (!_started || _retryRunning) return;
    _retryRunning = true;
    try {
      final now = DateTime.now().toUtc();
      final ready = _pending.values
          .where((item) => !item.nextAttemptAt.isAfter(now))
          .toList(growable: false);
      for (final pending in ready) {
        if (_pending.containsKey(pending.messageId)) {
          await _trySendPending(pending, now);
        }
      }
    } finally {
      _retryRunning = false;
    }
  }

  void _emitDelivery(String messageId, MeshDeliveryStatus status) {
    _deliveryUpdates.add(
      MeshDeliveryUpdate(messageId: messageId, status: status),
    );
  }

  Future<void> _persistPendingDeliveries() => outboxStore.save(
        _pending.values
            .map(
              (pending) => PersistedOutboxItem(
                messageId: pending.messageId,
                signedPayload: pending.signedPayload,
                createdAt: pending.createdAt,
                nextAttemptAt: pending.nextAttemptAt,
                attempts: pending.attempts,
                expectedAcknowledgementFrom:
                    pending.expectedAcknowledgementFrom,
              ),
            )
            .toList(growable: false),
      );

  @override
  void dispose() {
    _announceTimer?.cancel();
    _retryTimer?.cancel();
    _cleanupTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _incoming.close();
    _deliveryUpdates.close();
    unawaited(_bluetooth.stopScan());
    unawaited(_bluetooth.stopAdvertising());
    unawaited(_bluetooth.clearGattServerServices());
    super.dispose();
  }
}

class _PendingDelivery {
  _PendingDelivery({
    required this.messageId,
    required this.signedPayload,
    required this.createdAt,
    this.expectedAcknowledgementFrom,
    this.attempts = 0,
    DateTime? nextAttemptAt,
  }) : nextAttemptAt = nextAttemptAt ?? createdAt;

  final String messageId;
  final Uint8List signedPayload;
  final DateTime createdAt;
  final String? expectedAcknowledgementFrom;
  int attempts;
  DateTime nextAttemptAt;
}
