import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../core/ble_mesh_service.dart';
import '../../core/mesh_frames.dart';
import '../../core/universal_envelope.dart';
import '../message_transport.dart';

/// Bluetooth Low Energy (BLE) peer-to-peer mesh transport implementation.
class BluetoothTransport extends MessageTransport {
  BluetoothTransport({
    BleMeshService? bleService,
  }) : _bleService = bleService {
    _initListeners();
  }

  final BleMeshService? _bleService;
  TransportState _state = TransportState.stopped;

  final StreamController<UniversalEnvelope> _incomingController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<TransportPeerInfo> _peerDiscoveredController =
      StreamController<TransportPeerInfo>.broadcast();
  final StreamController<String> _peerLostController =
      StreamController<String>.broadcast();

  final MeshReassembler _reassembler = MeshReassembler();
  final MeshFragmenter _fragmenter = const MeshFragmenter();
  final Map<String, TransportPeerInfo> _peers = {};

  void _initListeners() {
    if (_bleService == null) return;

    _bleService.addListener(() {
      _syncBlePeers();
      notifyListeners();
    });

    _bleService.incoming.listen((incoming) {
      try {
        final rawJson =
            utf8.decode(incoming.attachmentBytes ?? utf8.encode(incoming.body));
        if (rawJson.startsWith('{') && rawJson.contains('protocolVersion')) {
          final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
          final env = UniversalEnvelope.fromJson(decoded);
          _incomingController.add(env);
        }
      } catch (_) {}
    });
  }

  void _syncBlePeers() {
    if (_bleService == null) return;
    final blePeers = _bleService.peers;

    final currentIds = <String>{};
    for (final p in blePeers) {
      currentIds.add(p.deviceId);
      final info = TransportPeerInfo(
        id: p.deviceId,
        displayName: p.username,
        transportType: TransportType.bluetooth,
        rssi: p.rssi,
        publicKeyFingerprint: p.verificationCode,
        lastSeen: p.lastSeen,
      );
      _peers[p.deviceId] = info;
      _peerDiscoveredController.add(info);
    }

    _peers.removeWhere((id, _) {
      if (!currentIds.contains(id)) {
        _peerLostController.add(id);
        return true;
      }
      return false;
    });
  }

  @override
  String get name => 'Bluetooth Low Energy Mesh';

  @override
  TransportType get type => TransportType.bluetooth;

  @override
  TransportState get state => _state;

  @override
  bool get isAvailable =>
      _bleService?.isStarted ?? (_state == TransportState.active);

  @override
  int get routeScore => 9500;

  @override
  Stream<UniversalEnvelope> get incomingEnvelopes => _incomingController.stream;

  @override
  Stream<TransportPeerInfo> get peerDiscovered =>
      _peerDiscoveredController.stream;

  @override
  Stream<String> get peerLost => _peerLostController.stream;

  @override
  Future<void> start() async {
    _state = TransportState.starting;
    notifyListeners();

    if (_bleService != null) {
      await _bleService.start();
    }
    _state = TransportState.active;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _state = TransportState.stopped;
    if (_bleService != null) {
      await _bleService.stop();
    }
    _peers.clear();
    notifyListeners();
  }

  @override
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId}) async {
    if (!isAvailable) return false;

    try {
      final jsonPayload = jsonEncode(envelope.toJson());
      final payloadBytes = Uint8List.fromList(utf8.encode(jsonPayload));

      // BLE frames are bounded and fragmented for reliable transmission
      final fragments = _fragmenter.fragment(
        messageId: envelope.packetId,
        ciphertext: payloadBytes,
      );

      // If active BleMeshService is available, transmit via physical BLE radio
      if (_bleService != null && _bleService.isStarted) {
        final recipient = targetPeerId ?? envelope.recipientDeviceId;
        if (recipient != null &&
            recipient.isNotEmpty &&
            _bleService.peers.any((p) =>
                p.shortId == recipient || p.verificationCode == recipient)) {
          final directSent = await _bleService.sendDirectMessage(
            envelope.packetId,
            jsonPayload,
            recipientId: recipient,
          );
          if (directSent) return true;
        }

        return await _bleService.broadcastMessage(
          envelope.packetId,
          jsonPayload,
        );
      }

      // Successfully processed fragments in offline/mock mode
      return fragments.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Inject received BLE frame bytes (e.g. from GATT characteristics or unit tests)
  void handleIncomingBleFrame(MeshFrame frame) {
    try {
      final completedPayload = _reassembler.add(frame);
      if (completedPayload != null) {
        final decoded =
            jsonDecode(utf8.decode(completedPayload)) as Map<String, dynamic>;
        final env = UniversalEnvelope.fromJson(decoded);
        _incomingController.add(env);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _incomingController.close();
    _peerDiscoveredController.close();
    _peerLostController.close();
    super.dispose();
  }
}
