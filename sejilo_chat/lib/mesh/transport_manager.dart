import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/universal_envelope.dart';
import 'message_transport.dart';

/// Orchestrator for all mesh transports (Wi-Fi, Bluetooth, Internet Relay).
/// Implements dynamic route scoring, prioritized multipath forwarding, and failover.
class TransportManager extends ChangeNotifier {
  TransportManager({
    List<MessageTransport>? transports,
  }) {
    if (transports != null) {
      for (final t in transports) {
        registerTransport(t);
      }
    }
  }

  final List<MessageTransport> _transports = [];
  final Map<MessageTransport, List<StreamSubscription>> _subscriptions = {};

  final StreamController<UniversalEnvelope> _incomingEnvelopesController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<TransportPeerInfo> _peerDiscoveredController =
      StreamController<TransportPeerInfo>.broadcast();
  final StreamController<String> _peerLostController =
      StreamController<String>.broadcast();

  List<MessageTransport> get transports => List.unmodifiable(_transports);

  Stream<UniversalEnvelope> get incomingEnvelopes => _incomingEnvelopesController.stream;
  Stream<TransportPeerInfo> get peerDiscovered => _peerDiscoveredController.stream;
  Stream<String> get peerLost => _peerLostController.stream;

  void registerTransport(MessageTransport transport) {
    if (_transports.contains(transport)) return;

    _transports.add(transport);
    _transports.sort((a, b) => b.routeScore.compareTo(a.routeScore)); // Higher score preferred

    final subs = <StreamSubscription>[];
    subs.add(transport.incomingEnvelopes.listen((envelope) {
      _incomingEnvelopesController.add(envelope);
    }));

    subs.add(transport.peerDiscovered.listen((peer) {
      _peerDiscoveredController.add(peer);
    }));

    subs.add(transport.peerLost.listen((peerId) {
      _peerLostController.add(peerId);
    }));

    transport.addListener(notifyListeners);
    _subscriptions[transport] = subs;
    notifyListeners();
  }

  void unregisterTransport(MessageTransport transport) {
    if (!_transports.contains(transport)) return;

    final subs = _subscriptions.remove(transport);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }

    transport.removeListener(notifyListeners);
    _transports.remove(transport);
    notifyListeners();
  }

  Future<void> startAll() async {
    for (final t in _transports) {
      try {
        await t.start();
      } catch (e) {
        debugPrint('[TransportManager] Error starting ${t.name}: $e');
      }
    }
    notifyListeners();
  }

  Future<void> stopAll() async {
    for (final t in _transports) {
      try {
        await t.stop();
      } catch (e) {
        debugPrint('[TransportManager] Error stopping ${t.name}: $e');
      }
    }
    notifyListeners();
  }

  /// Transmit envelope through the best available transport with fallback.
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId}) async {
    final activeTransports = _transports.where((t) => t.isAvailable).toList();
    if (activeTransports.isEmpty) return false;

    // Prioritize transports by route score (Wi-Fi > BLE > Internet)
    activeTransports.sort((a, b) => b.routeScore.compareTo(a.routeScore));

    for (final transport in activeTransports) {
      try {
        final success = await transport.send(envelope, targetPeerId: targetPeerId);
        if (success) return true;
      } catch (_) {}
    }

    return false;
  }

  /// Broadcast envelope across all available local peer-to-peer transports (Wi-Fi & BLE).
  Future<int> broadcastLocal(UniversalEnvelope envelope) async {
    int sendCount = 0;
    final p2pTransports = _transports
        .where((t) => t.isAvailable && t.type != TransportType.internet)
        .toList();

    for (final t in p2pTransports) {
      try {
        final success = await t.send(envelope);
        if (success) sendCount++;
      } catch (_) {}
    }
    return sendCount;
  }

  MessageTransport? getTransport(TransportType type) {
    try {
      return _transports.firstWhere((t) => t.type == type);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> get overallMetrics => {
        'totalTransports': _transports.length,
        'activeTransports': _transports.where((t) => t.isAvailable).length,
        'transports': _transports.map((t) => t.metrics).toList(),
      };

  @override
  void dispose() {
    for (final subs in _subscriptions.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _subscriptions.clear();
    _incomingEnvelopesController.close();
    _peerDiscoveredController.close();
    _peerLostController.close();
    super.dispose();
  }
}
