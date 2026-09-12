import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../core/universal_envelope.dart';
import '../message_transport.dart';

/// Wi-Fi Direct / Local Area Network peer-to-peer transport.
/// Uses UDP multicast beacons for zero-config peer discovery and direct
/// framed TCP socket connections for encrypted multi-hop payload delivery.
class WifiTransport extends MessageTransport {
  WifiTransport({
    int tcpPort = 0,
    int discoveryPort = 39871,
    String? localDeviceId,
    String? localDisplayName,
  })  : _configuredTcpPort = tcpPort,
        _discoveryPort = discoveryPort,
        _localDeviceId = localDeviceId ?? 'device-local',
        _localDisplayName = localDisplayName ?? 'Sejilo User';

  final int _configuredTcpPort;
  final int _discoveryPort;
  final String _localDeviceId;
  final String _localDisplayName;

  TransportState _state = TransportState.stopped;
  ServerSocket? _tcpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  Timer? _pruneTimer;

  int _actualTcpPort = 0;
  final Map<String, TransportPeerInfo> _peers = {};

  final StreamController<UniversalEnvelope> _incomingController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<TransportPeerInfo> _peerDiscoveredController =
      StreamController<TransportPeerInfo>.broadcast();
  final StreamController<String> _peerLostController =
      StreamController<String>.broadcast();

  @override
  String get name => 'Wi-Fi Direct & LAN Mesh';

  @override
  TransportType get type => TransportType.wifi;

  @override
  TransportState get state => _state;

  @override
  bool get isAvailable => _state == TransportState.active;

  @override
  int get routeScore => 10000; // Wi-Fi has highest throughput and lowest local latency

  int get port => _actualTcpPort;
  List<TransportPeerInfo> get nearbyPeers => List.unmodifiable(_peers.values);

  @override
  Stream<UniversalEnvelope> get incomingEnvelopes => _incomingController.stream;

  @override
  Stream<TransportPeerInfo> get peerDiscovered => _peerDiscoveredController.stream;

  @override
  Stream<String> get peerLost => _peerLostController.stream;

  @override
  Future<void> start() async {
    if (_state == TransportState.active) return;
    _state = TransportState.starting;
    notifyListeners();

    try {
      // 1. Start TCP Server for incoming envelope transfers
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _configuredTcpPort,
      );
      _actualTcpPort = _tcpServer!.port;
      _tcpServer!.listen(_handleIncomingTcpClient);

      // 2. Start UDP Discovery Socket
      try {
        _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _discoveryPort,
          reuseAddress: true,
          reusePort: !Platform.isWindows,
        );
        _udpSocket!.broadcastEnabled = true;
        _udpSocket!.listen(_handleIncomingUdpDatagram);

        // Periodic UDP beacon
        _beaconTimer = Timer.periodic(const Duration(seconds: 4), (_) => _broadcastDiscoveryBeacon());
      } catch (e) {
        debugPrint('[WifiTransport] UDP discovery disabled: $e');
      }

      // Periodic stale peer pruner (remove peers silent for > 20 seconds)
      _pruneTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pruneStalePeers());

      _state = TransportState.active;
      notifyListeners();
    } catch (e) {
      _state = TransportState.error;
      notifyListeners();
    }
  }

  void _handleIncomingTcpClient(Socket client) {
    final buffer = BytesBuilder();
    client.listen(
      (data) {
        buffer.add(data);
      },
      onDone: () {
        try {
          final raw = utf8.decode(buffer.toBytes());
          if (raw.trim().isNotEmpty) {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            final envelope = UniversalEnvelope.fromJson(json);
            _incomingController.add(envelope);
          }
        } catch (_) {}
        client.destroy();
      },
      onError: (_) {
        client.destroy();
      },
      cancelOnError: true,
    );
  }

  void _handleIncomingUdpDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _udpSocket?.receive();
    if (dg == null) return;

    try {
      final msg = utf8.decode(dg.data);
      if (!msg.startsWith('SEJILO_WIFI_BEACON_V1:')) return;

      final payload = jsonDecode(msg.substring('SEJILO_WIFI_BEACON_V1:'.length)) as Map<String, dynamic>;
      final peerId = payload['deviceId'] as String? ?? '';
      final peerPort = payload['tcpPort'] as int? ?? 0;
      final displayName = payload['displayName'] as String? ?? 'Peer';
      final fingerprint = payload['fingerprint'] as String?;

      if (peerId.isEmpty || peerId == _localDeviceId || peerPort <= 0) return;

      final peerAddress = '${dg.address.address}:$peerPort';
      final peerInfo = TransportPeerInfo(
        id: peerId,
        displayName: displayName,
        transportType: TransportType.wifi,
        rssi: -40, // Local Wi-Fi RSSI estimate
        address: peerAddress,
        publicKeyFingerprint: fingerprint,
        lastSeen: DateTime.now(),
      );

      _peers[peerId] = peerInfo;
      _peerDiscoveredController.add(peerInfo);
      notifyListeners();
    } catch (_) {}
  }

  void _broadcastDiscoveryBeacon() {
    if (_udpSocket == null || _actualTcpPort <= 0) return;

    try {
      final beaconData = jsonEncode({
        'deviceId': _localDeviceId,
        'displayName': _localDisplayName,
        'tcpPort': _actualTcpPort,
        'timestamp': DateTime.now().toIso8601String(),
      });
      final bytes = utf8.encode('SEJILO_WIFI_BEACON_V1:$beaconData');
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (_) {}
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    final expiredIds = <String>[];

    _peers.forEach((id, p) {
      if (now.difference(p.lastSeen) > const Duration(seconds: 20)) {
        expiredIds.add(id);
      }
    });

    for (final id in expiredIds) {
      _peers.remove(id);
      _peerLostController.add(id);
    }

    if (expiredIds.isNotEmpty) {
      notifyListeners();
    }
  }

  @override
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId}) async {
    if (_state != TransportState.active) return false;

    final targetPeers = targetPeerId != null
        ? [_peers[targetPeerId]].whereType<TransportPeerInfo>().toList()
        : _peers.values.toList();

    if (targetPeers.isEmpty) return false;

    bool sentAtLeastOnce = false;
    final jsonBytes = utf8.encode(jsonEncode(envelope.toJson()));

    for (final p in targetPeers) {
      if (p.address == null) continue;
      try {
        final parts = p.address!.split(':');
        final host = parts[0];
        final port = int.parse(parts[1]);

        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
        socket.add(jsonBytes);
        await socket.flush();
        await socket.close();
        sentAtLeastOnce = true;
      } catch (_) {}
    }

    return sentAtLeastOnce;
  }

  /// Manually inject an envelope (for direct tests and simulation)
  void injectEnvelope(UniversalEnvelope envelope) {
    _incomingController.add(envelope);
  }

  /// Manually register a peer (for direct tests and simulation)
  void registerPeer(TransportPeerInfo peer) {
    _peers[peer.id] = peer;
    _peerDiscoveredController.add(peer);
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _beaconTimer?.cancel();
    _pruneTimer?.cancel();
    _udpSocket?.close();
    await _tcpServer?.close();
    _peers.clear();
    _state = TransportState.stopped;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _incomingController.close();
    _peerDiscoveredController.close();
    _peerLostController.close();
    super.dispose();
  }
}
