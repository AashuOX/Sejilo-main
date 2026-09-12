import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Network connectivity status combining internet and mesh reachability.
enum ConnectivityStatus {
  /// Internet is reachable.
  online,

  /// No internet, but at least one BLE/LAN mesh peer is nearby.
  meshConnected,

  /// Completely offline — no internet, no mesh peers.
  offline,
}

/// Observes internet connectivity (via HTTP probe) and BLE peer count to
/// provide a unified [ConnectivityStatus] across the app.
///
/// Usage:
/// ```dart
/// final notifier = ConnectivityNotifier();
/// await notifier.initialize();
/// // Update mesh peers whenever BleMeshService reports changes:
/// notifier.updateMeshPeerCount(meshClient.nearbyPeers.length);
/// ```
class ConnectivityNotifier extends ChangeNotifier {
  ConnectivityNotifier({
    Duration probeInterval = const Duration(seconds: 15),
    Uri? probeUri,
  })  : _probeInterval = probeInterval,
        _probeUri = probeUri ?? Uri.parse('https://connectivitycheck.gstatic.com/generate_204');

  final Duration _probeInterval;
  final Uri _probeUri;

  ConnectivityStatus _status = ConnectivityStatus.offline;
  int _meshPeerCount = 0;
  bool _internetReachable = false;
  Timer? _probeTimer;
  bool _initialized = false;

  ConnectivityStatus get status => _status;
  int get meshPeerCount => _meshPeerCount;
  bool get isOnline => _status == ConnectivityStatus.online;
  bool get hasMeshPeers => _meshPeerCount > 0;

  /// Initialize connectivity monitoring. Call once after construction.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _probe();
    _probeTimer = Timer.periodic(_probeInterval, (_) => _probe());
  }

  /// Update the BLE/LAN peer count from the mesh service.
  void updateMeshPeerCount(int count) {
    if (_meshPeerCount == count) return;
    _meshPeerCount = count;
    _recompute();
  }

  /// Force an immediate connectivity probe (e.g., when app resumes).
  Future<void> refresh() => _probe();

  Future<void> _probe() async {
    bool reachable;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.headUrl(_probeUri);
      request.headers.set('cache-control', 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      reachable = response.statusCode >= 200 && response.statusCode < 400;
      client.close();
    } on Object {
      reachable = false;
    }
    if (_internetReachable == reachable) return;
    _internetReachable = reachable;
    _recompute();
  }

  void _recompute() {
    final next = _internetReachable
        ? ConnectivityStatus.online
        : _meshPeerCount > 0
            ? ConnectivityStatus.meshConnected
            : ConnectivityStatus.offline;
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }
}
