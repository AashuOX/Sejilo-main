import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Monitors internet connectivity via low-latency probes and exposes real-time state.
class NetworkMonitor extends ChangeNotifier {
  NetworkMonitor({
    Duration probeInterval = const Duration(seconds: 10),
    Uri? probeUri,
  })  : _probeInterval = probeInterval,
        _probeUri = probeUri ?? Uri.parse('https://connectivitycheck.gstatic.com/generate_204');

  final Duration _probeInterval;
  final Uri _probeUri;
  bool _isOnline = true;
  Timer? _timer;
  bool _initialized = false;
  bool _disposed = false;

  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await checkConnectivity();
    if (!_disposed) {
      _timer = Timer.periodic(_probeInterval, (_) => checkConnectivity());
    }
  }

  /// Manually force a check or update network state (useful for tests and app resume).
  Future<bool> checkConnectivity() async {
    if (_disposed) return _isOnline;
    bool reachable = false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.headUrl(_probeUri);
      request.headers.set('cache-control', 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      reachable = response.statusCode >= 200 && response.statusCode < 400;
      client.close();
    } catch (_) {
      reachable = false;
    }

    if (!_disposed && !_connectivityController.isClosed && _isOnline != reachable) {
      _isOnline = reachable;
      _connectivityController.add(_isOnline);
      notifyListeners();
    }
    return _isOnline;
  }

  /// Override network status directly (e.g. for testing offline/online transitions).
  void setOnlineOverride(bool online) {
    if (!_disposed && !_connectivityController.isClosed && _isOnline != online) {
      _isOnline = online;
      _connectivityController.add(_isOnline);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connectivityController.close();
    super.dispose();
  }
}
