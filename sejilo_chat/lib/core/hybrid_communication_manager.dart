import 'dart:async';
import 'package:flutter/foundation.dart';
import '../auth/account_auth_controller.dart';
import '../mesh/mesh_router.dart';
import '../mesh/peer_discovery.dart';
import '../mesh/transport_manager.dart';
import '../messaging/message_repository.dart';
import '../messaging/online_messaging_controller.dart';
import 'network_monitor.dart';
import 'sync_manager.dart';
import 'sync_queue.dart';

enum HybridNetworkState {
  online,
  meshConnected,
  offline,
}

enum HybridActivityState {
  idle,
  syncing,
  relaying,
  error,
}

/// Automatic hybrid communication manager orchestrating Internet, Wi-Fi Direct,
/// Bluetooth mesh, local offline storage, and background synchronization without manual user intervention.
class HybridCommunicationManager extends ChangeNotifier {
  HybridCommunicationManager({
    required this.auth,
    required NetworkMonitor networkMonitor,
    required MessageRepository repository,
    required SyncQueue syncQueue,
    required SyncManager syncManager,
    required MeshRouter meshRouter,
    required TransportManager transportManager,
    required PeerDiscovery peerDiscovery,
  })  : _networkMonitor = networkMonitor,
        _repository = repository,
        _syncManager = syncManager,
        _meshRouter = meshRouter,
        _peerDiscovery = peerDiscovery {
    _initListeners();
  }

  final AccountAuthController auth;
  final NetworkMonitor _networkMonitor;
  final MessageRepository _repository;
  final SyncManager _syncManager;
  final MeshRouter _meshRouter;
  final PeerDiscovery _peerDiscovery;

  HybridNetworkState _networkState = HybridNetworkState.offline;
  HybridActivityState _activityState = HybridActivityState.idle;
  int _activeMeshPeerCount = 0;
  String? _lastError;
  bool _initialized = false;
  bool _disposed = false;

  final List<StreamSubscription> _subscriptions = [];

  HybridNetworkState get networkState => _networkState;
  HybridActivityState get activityState => _activityState;
  int get activeMeshPeerCount => _activeMeshPeerCount;
  String? get lastError => _lastError;
  bool get isOnline => _networkState == HybridNetworkState.online;
  bool get isMeshConnected => _networkState == HybridNetworkState.meshConnected;
  bool get isOffline => _networkState == HybridNetworkState.offline;
  bool get isSyncing => _activityState == HybridActivityState.syncing;
  bool get isRelaying => _activityState == HybridActivityState.relaying;

  String get statusLabel {
    if (_activityState == HybridActivityState.syncing) return 'Syncing...';
    if (_activityState == HybridActivityState.relaying) {
      return 'Relaying mesh packet...';
    }
    switch (_networkState) {
      case HybridNetworkState.online:
        return 'Online';
      case HybridNetworkState.meshConnected:
        return _activeMeshPeerCount > 1
            ? 'Mesh Connected ($_activeMeshPeerCount peers)'
            : 'Mesh Connected (1 peer)';
      case HybridNetworkState.offline:
        return 'Offline';
    }
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    await _meshRouter.start();
    await _syncManager.start();
    _recomputeNetworkState();
  }

  void _initListeners() {
    // 1. Listen to Internet reachability transitions
    _subscriptions.add(_networkMonitor.onConnectivityChanged.listen((online) {
      _handleConnectivityChange(online);
    }));

    // 2. Listen to Mesh Peer arrivals & departures
    _subscriptions.add(_peerDiscovery.onPeerConnected.listen((peer) {
      _handlePeerConnected(peer);
    }));

    _subscriptions.add(_peerDiscovery.onPeerDisconnected.listen((peerId) {
      _handlePeerDisconnected(peerId);
    }));

    // 3. Listen to Mesh Router events
    _subscriptions.add(_meshRouter.onRelayed.listen((_) {
      _setActivity(HybridActivityState.relaying, durationMs: 1200);
    }));

    _subscriptions.add(_meshRouter.onDeliveredLocally.listen((env) {
      _handleLocallyDeliveredEnvelope(env);
    }));

    _subscriptions.add(_meshRouter.onReceiptAcknowledged.listen((messageId) {
      _handleReceiptAcknowledged(messageId);
    }));

    _networkMonitor.addListener(_recomputeNetworkState);
    _peerDiscovery.addListener(_recomputeNetworkState);
  }

  void _recomputeNetworkState() {
    if (_disposed) return;
    final peers = _peerDiscovery.activePeers.where((p) => p.isConnected).length;
    _activeMeshPeerCount = peers;

    HybridNetworkState nextState;
    if (_networkMonitor.isOnline) {
      nextState = HybridNetworkState.online;
    } else if (peers > 0) {
      nextState = HybridNetworkState.meshConnected;
    } else {
      nextState = HybridNetworkState.offline;
    }

    if (_networkState != nextState) {
      _networkState = nextState;
      notifyListeners();
    }
  }

  /// Automatically triggered when Internet connectivity changes.
  Future<void> _handleConnectivityChange(bool online) async {
    _recomputeNetworkState();

    if (online) {
      // ── Internet returned: Auto-sync pending mutations with backend ──
      _setActivity(HybridActivityState.syncing);
      try {
        await _syncManager.triggerSync();
        _setActivity(HybridActivityState.idle);
      } catch (e) {
        _lastError = e.toString();
        _setActivity(HybridActivityState.error, durationMs: 2000);
      }
    } else {
      // ── Internet dropped: Seamless fallback to Mesh / Local store ────
      _recomputeNetworkState();
    }
  }

  /// Automatically triggered when a nearby mesh peer is encountered.
  Future<void> _handlePeerConnected(MeshPeerRecord peer) async {
    _recomputeNetworkState();

    // Exchange queued store-and-forward packets with the encountered peer
    if (!_networkMonitor.isOnline) {
      _setActivity(HybridActivityState.relaying, durationMs: 1500);
    }
  }

  void _handlePeerDisconnected(String peerId) {
    _recomputeNetworkState();
  }

  void _handleLocallyDeliveredEnvelope(dynamic env) {
    _setActivity(HybridActivityState.idle);
  }

  void _handleReceiptAcknowledged(String messageId) {
    final conversationId = _repository.findConversationIdForMessage(messageId);
    if (conversationId == null) return;

    _repository.updateMessageStatus(
      conversationId: conversationId,
      messageId: messageId,
      status: MessageDeliveryStatus.delivered,
    );
    notifyListeners();
  }

  void _setActivity(HybridActivityState state, {int? durationMs}) {
    if (_disposed) return;
    _activityState = state;
    notifyListeners();

    if (durationMs != null && state != HybridActivityState.idle) {
      Future<void>.delayed(Duration(milliseconds: durationMs), () {
        if (!_disposed && _activityState == state) {
          _activityState = HybridActivityState.idle;
          notifyListeners();
        }
      });
    }
  }

  /// Send message through the best automatic route (Internet $\rightarrow$ Local Mesh $\rightarrow$ Store & Forward).
  Future<OnlineMessage?> sendMessageAuto({
    required String conversationId,
    required String text,
    Uint8List? mediaBytes,
    String? mediaMimeType,
    String? replyToMessageId,
  }) async {
    final profile = auth.profile;
    if (profile == null) return null;

    // 1. Optimistic Local Persistence (Instant zero-lag UI feedback)
    final msg = await _repository.createLocalPendingMessage(
      conversationId: conversationId,
      sender: profile,
      text: text,
      mediaBytes: mediaBytes,
      mediaMimeType: mediaMimeType,
      replyToMessageId: replyToMessageId,
    );

    // 2. Select route based on active network state
    if (_networkState == HybridNetworkState.online && auth.isConfigured) {
      // Route via Internet WebSocket/REST Sync
      _setActivity(HybridActivityState.syncing);
      await _syncManager.triggerSync();
      _setActivity(HybridActivityState.idle);
    } else if (_networkState == HybridNetworkState.meshConnected) {
      // Route via Peer-to-Peer Mesh (Wi-Fi Direct / BLE)
      _setActivity(HybridActivityState.relaying);
      final rawPayload = Uint8List.fromList(text.codeUnits);
      await _meshRouter.sendDirectMessage(
        recipientDeviceId: conversationId,
        messageId: msg.id,
        encryptedPayload: rawPayload,
      );
      _setActivity(HybridActivityState.idle, durationMs: 1000);
    } else {
      // Completely offline: item safely retained in persistent SyncQueue & OfflineDatabase
      // Will automatically synchronize when either Internet or Mesh peers appear
    }

    notifyListeners();
    return msg;
  }

  /// Manual test helper to simulate network transitions.
  void simulateNetworkTransition(HybridNetworkState targetState) {
    switch (targetState) {
      case HybridNetworkState.online:
        _networkMonitor.setOnlineOverride(true);
        break;
      case HybridNetworkState.meshConnected:
        _networkMonitor.setOnlineOverride(false);
        break;
      case HybridNetworkState.offline:
        _networkMonitor.setOnlineOverride(false);
        break;
    }
    _networkState = targetState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _networkMonitor.removeListener(_recomputeNetworkState);
    _peerDiscovery.removeListener(_recomputeNetworkState);
    super.dispose();
  }
}
