import 'dart:async';
import '../../core/internet_relay_transport.dart';
import '../../core/universal_envelope.dart';
import '../message_transport.dart';

/// Internet store-and-forward relay transport implementation of [MessageTransport].
class InternetTransport extends MessageTransport {
  InternetTransport({
    required InternetRelayTransport relay,
  }) : _relay = relay {
    _relaySub = _relay.receivedEnvelopes.listen((env) {
      _incomingController.add(env);
    });
    _stateSub = _relay.stateChanges.listen((s) {
      notifyListeners();
    });
  }

  final InternetRelayTransport _relay;
  StreamSubscription<UniversalEnvelope>? _relaySub;
  StreamSubscription<dynamic>? _stateSub;

  final StreamController<UniversalEnvelope> _incomingController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<TransportPeerInfo> _peerDiscoveredController =
      StreamController<TransportPeerInfo>.broadcast();
  final StreamController<String> _peerLostController =
      StreamController<String>.broadcast();

  @override
  String get name => 'Internet Relay Transport';

  @override
  TransportType get type => TransportType.internet;

  @override
  TransportState get state {
    switch (_relay.state.name) {
      case 'active':
        return TransportState.active;
      case 'connecting':
        return TransportState.starting;
      case 'disconnected':
      case 'offline':
        return TransportState.disconnected;
      case 'stopped':
      default:
        return TransportState.stopped;
    }
  }

  @override
  bool get isAvailable => _relay.state.name == 'active';

  @override
  int get routeScore => 9000;

  @override
  Stream<UniversalEnvelope> get incomingEnvelopes => _incomingController.stream;

  @override
  Stream<TransportPeerInfo> get peerDiscovered => _peerDiscoveredController.stream;

  @override
  Stream<String> get peerLost => _peerLostController.stream;

  @override
  Future<void> start() async {
    await _relay.start();
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    await _relay.stop();
    notifyListeners();
  }

  @override
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId}) async {
    try {
      await _relay.send(envelope);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _relaySub?.cancel();
    _stateSub?.cancel();
    _incomingController.close();
    _peerDiscoveredController.close();
    _peerLostController.close();
    super.dispose();
  }
}
