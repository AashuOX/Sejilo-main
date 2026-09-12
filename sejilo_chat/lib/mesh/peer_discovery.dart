import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'message_transport.dart';
import 'transport_manager.dart';

class MeshPeerRecord {
  const MeshPeerRecord({
    required this.deviceId,
    required this.displayName,
    required this.temporaryPeerId,
    this.publicKeyFingerprint,
    required this.transportType,
    this.rssi = -60,
    this.hops = 0,
    required this.lastSeen,
    this.isConnected = false,
  });

  final String deviceId;
  final String displayName;
  final String temporaryPeerId;
  final String? publicKeyFingerprint;
  final TransportType transportType;
  final int rssi;
  final int hops;
  final DateTime lastSeen;
  final bool isConnected;

  bool get isDirectNeighbor => hops == 0;

  MeshPeerRecord copyWith({
    String? deviceId,
    String? displayName,
    String? temporaryPeerId,
    String? publicKeyFingerprint,
    TransportType? transportType,
    int? rssi,
    int? hops,
    DateTime? lastSeen,
    bool? isConnected,
  }) {
    return MeshPeerRecord(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      temporaryPeerId: temporaryPeerId ?? this.temporaryPeerId,
      publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,
      transportType: transportType ?? this.transportType,
      rssi: rssi ?? this.rssi,
      hops: hops ?? this.hops,
      lastSeen: lastSeen ?? this.lastSeen,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

/// Discovers, authenticates, and manages nearby peer records across all transports.
class PeerDiscovery extends ChangeNotifier {
  PeerDiscovery({
    required TransportManager transportManager,
    String? localDeviceId,
  })  : _transportManager = transportManager,
        _localDeviceId = localDeviceId ?? 'local-device' {
    _initSubscriptions();
  }

  final TransportManager _transportManager;
  final String _localDeviceId;
  final Map<String, MeshPeerRecord> _peers = {};
  Timer? _pruneTimer;
  StreamSubscription? _discoveredSub;
  StreamSubscription? _lostSub;

  final StreamController<MeshPeerRecord> _peerConnectedController =
      StreamController<MeshPeerRecord>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();

  List<MeshPeerRecord> get activePeers => List.unmodifiable(_peers.values);
  Stream<MeshPeerRecord> get onPeerConnected => _peerConnectedController.stream;
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  void _initSubscriptions() {
    _discoveredSub = _transportManager.peerDiscovered.listen((info) {
      _handlePeerDiscovered(info);
    });

    _lostSub = _transportManager.peerLost.listen((peerId) {
      _handlePeerLost(peerId);
    });

    _pruneTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pruneStalePeers());
  }

  void _handlePeerDiscovered(TransportPeerInfo info) {
    if (info.id == _localDeviceId) return;

    final existing = _peers[info.id];
    final tempId = existing?.temporaryPeerId ?? _generateTemporaryPeerId(info.id);

    final updated = MeshPeerRecord(
      deviceId: info.id,
      displayName: info.displayName,
      temporaryPeerId: tempId,
      publicKeyFingerprint: info.publicKeyFingerprint ?? existing?.publicKeyFingerprint,
      transportType: info.transportType,
      rssi: info.rssi,
      hops: 0, // Direct transport discovery
      lastSeen: info.lastSeen,
      isConnected: true,
    );

    _peers[info.id] = updated;
    if (existing == null || !existing.isConnected) {
      _peerConnectedController.add(updated);
    }
    notifyListeners();
  }

  void _handlePeerLost(String peerId) {
    final existing = _peers[peerId];
    if (existing != null && existing.isConnected) {
      _peers[peerId] = existing.copyWith(isConnected: false);
      _peerDisconnectedController.add(peerId);
      notifyListeners();
    }
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    final disconnectedIds = <String>[];

    _peers.forEach((id, peer) {
      if (now.difference(peer.lastSeen) > const Duration(seconds: 35)) {
        disconnectedIds.add(id);
      }
    });

    for (final id in disconnectedIds) {
      _peers.remove(id);
      _peerDisconnectedController.add(id);
    }

    if (disconnectedIds.isNotEmpty) {
      notifyListeners();
    }
  }

  String _generateTemporaryPeerId(String deviceId) {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'tmp-$hex';
  }

  MeshPeerRecord? getPeer(String deviceId) => _peers[deviceId];

  /// Register or update a multi-hop relayed peer record
  void registerRelayedPeer({
    required String deviceId,
    required String displayName,
    required int hops,
    String? fingerprint,
  }) {
    if (deviceId == _localDeviceId) return;

    final existing = _peers[deviceId];
    if (existing == null || hops < existing.hops) {
      final updated = MeshPeerRecord(
        deviceId: deviceId,
        displayName: displayName,
        temporaryPeerId: existing?.temporaryPeerId ?? _generateTemporaryPeerId(deviceId),
        publicKeyFingerprint: fingerprint ?? existing?.publicKeyFingerprint,
        transportType: TransportType.bluetooth,
        rssi: -80, // Multi-hop estimated attenuation
        hops: hops,
        lastSeen: DateTime.now(),
        isConnected: true,
      );
      _peers[deviceId] = updated;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pruneTimer?.cancel();
    _discoveredSub?.cancel();
    _lostSub?.cancel();
    _peerConnectedController.close();
    _peerDisconnectedController.close();
    super.dispose();
  }
}
