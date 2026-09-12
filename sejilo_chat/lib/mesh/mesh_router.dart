import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/universal_envelope.dart';
import 'message_deduplication.dart';
import 'peer_discovery.dart';
import 'peer_session_manager.dart';
import 'relay_queue.dart';
import 'transport_manager.dart';
import 'ttl_manager.dart';

class DecryptedLocalMessage {
  const DecryptedLocalMessage({
    required this.envelope,
    required this.cleartext,
  });

  final UniversalEnvelope envelope;
  final Uint8List cleartext;
}

/// Central routing engine for Sejilo Peer-to-Peer Mesh.
/// Orchestrates multi-hop store-and-forward relaying (A -> B -> C -> D),
/// hop limits, loop prevention, deduplication, and zero-leakage intermediate forwarding.
class MeshRouter extends ChangeNotifier {
  MeshRouter({
    required this.localDeviceId,
    required TransportManager transportManager,
    PeerDiscovery? peerDiscovery,
    PeerSessionManager? sessionManager,
    TTLManager? ttlManager,
    MessageDeduplication? deduplication,
    RelayQueue? relayQueue,
  })  : _transportManager = transportManager,
        _peerDiscovery = peerDiscovery ??
            PeerDiscovery(
                transportManager: transportManager,
                localDeviceId: localDeviceId),
        _sessionManager = sessionManager ?? PeerSessionManager(),
        _ttlManager = ttlManager ?? const TTLManager(),
        _deduplication = deduplication ?? MessageDeduplication(),
        _relayQueue = relayQueue ?? RelayQueue() {
    _initSubscriptions();
  }

  final String localDeviceId;
  final TransportManager _transportManager;
  final PeerDiscovery _peerDiscovery;
  final PeerSessionManager _sessionManager;
  final TTLManager _ttlManager;
  final MessageDeduplication _deduplication;
  final RelayQueue _relayQueue;

  bool _isRunning = false;
  Timer? _relayDrainTimer;
  StreamSubscription? _incomingSub;
  StreamSubscription? _peerConnectedSub;

  final StreamController<UniversalEnvelope> _deliveredLocallyController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<UniversalEnvelope> _relayedPacketsController =
      StreamController<UniversalEnvelope>.broadcast();
  final StreamController<String> _receiptAcksController =
      StreamController<String>.broadcast();

  bool get isRunning => _isRunning;
  TransportManager get transportManager => _transportManager;
  PeerDiscovery get peerDiscovery => _peerDiscovery;
  PeerSessionManager get sessionManager => _sessionManager;
  TTLManager get ttlManager => _ttlManager;
  MessageDeduplication get deduplication => _deduplication;
  RelayQueue get relayQueue => _relayQueue;

  Stream<UniversalEnvelope> get onDeliveredLocally =>
      _deliveredLocallyController.stream;
  Stream<UniversalEnvelope> get onRelayed => _relayedPacketsController.stream;
  Stream<String> get onReceiptAcknowledged => _receiptAcksController.stream;

  void _initSubscriptions() {
    _incomingSub = _transportManager.incomingEnvelopes.listen((envelope) {
      handleIncomingEnvelope(envelope);
    });

    _peerConnectedSub = _peerDiscovery.onPeerConnected.listen((peer) {
      _onPeerEncountered(peer);
    });
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await _transportManager.startAll();

    _relayDrainTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _drainRelayQueue();
    });

    notifyListeners();
  }

  Future<void> stop() async {
    _isRunning = false;
    _relayDrainTimer?.cancel();
    await _transportManager.stopAll();
    notifyListeners();
  }

  /// Originates a new end-to-end encrypted direct message to [recipientDeviceId].
  Future<UniversalEnvelope> sendDirectMessage({
    required String recipientDeviceId,
    required String messageId,
    required Uint8List encryptedPayload,
    int ttl = 4,
    UniversalPacketType packetType = UniversalPacketType.message,
  }) async {
    final packetId =
        'pkt-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
    final now = DateTime.now().toUtc();

    final envelope = UniversalEnvelope(
      protocolVersion: 1,
      packetType: packetType,
      packetId: packetId,
      messageId: messageId,
      senderDeviceId: localDeviceId,
      recipientDeviceId: recipientDeviceId,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      ttl: ttl,
      hopCount: 0,
      payloadType: UniversalPayloadType.ciphertext,
      encryptedPayload: encryptedPayload,
    );

    // Record as seen locally to prevent processing echo
    _deduplication.markIfFresh(envelope.packetId,
        messageId: envelope.messageId);

    // 1. Try immediate send via best transport
    final delivered =
        await _transportManager.send(envelope, targetPeerId: recipientDeviceId);

    // 2. If not immediately acknowledged or multi-hop required, enqueue into RelayQueue
    if (!delivered) {
      _relayQueue.enqueue(envelope, targetNextHopPeerId: recipientDeviceId);
    }

    notifyListeners();
    return envelope;
  }

  /// Core routing logic for handling incoming packets across all transports.
  void handleIncomingEnvelope(UniversalEnvelope envelope, {String? ingressPeerId}) {
    // 0. Loop prevention: drop packets originated from self (BitChat pattern)
    if (envelope.senderDeviceId == localDeviceId) return;

    // 1. Deduplication Check: drop if previously processed
    if (!_deduplication.markIfFresh(envelope.packetId,
        messageId: envelope.messageId)) {
      return;
    }

    // 2. TTL & Hop Limit Check: drop if expired or over hop limit
    if (!_ttlManager.isValid(envelope)) {
      return;
    }

    final isForMe = envelope.recipientDeviceId == localDeviceId;

    if (isForMe) {
      // ── Final Destination: Local Delivery ─────────────────────────
      if (envelope.packetType == UniversalPacketType.receipt) {
        _receiptAcksController.add(envelope.messageId);
        _relayQueue.remove(envelope.packetId);
      } else {
        _deliveredLocallyController.add(envelope);

        // Send cryptographic delivery acknowledgement back to sender
        _sendDeliveryReceipt(
          originalSenderDeviceId: envelope.senderDeviceId,
          originalMessageId: envelope.messageId,
          originalPacketId: envelope.packetId,
        );
      }
      notifyListeners();
    } else {
      // ── Intermediate Node: Store-and-Forward Multi-Hop Relay ───────
      // Intermediate relays DO NOT decrypt private payload; they only verify routing headers
      _relayMultiHop(envelope, ingressPeerId: ingressPeerId);
    }
  }

  void _relayMultiHop(UniversalEnvelope envelope, {String? ingressPeerId}) {
    // Loop prevention: do not relay messages originated by this node
    if (envelope.senderDeviceId == localDeviceId) return;

    final forwarded = _ttlManager.incrementHop(envelope);
    if (forwarded == null) return; // Drop if hop limit reached

    _relayedPacketsController.add(forwarded);

    // 1. Check if recipient is a direct neighbor
    final directNeighbor =
        _peerDiscovery.getPeer(envelope.recipientDeviceId ?? '');
    if (directNeighbor != null &&
        directNeighbor.isConnected &&
        directNeighbor.deviceId != ingressPeerId) {
      _transportManager.send(forwarded, targetPeerId: directNeighbor.deviceId);
    } else {
      // 2. Broadcast across local peer-to-peer mesh transports or enqueue for store-and-forward
      _transportManager.broadcastLocal(forwarded);
      _relayQueue.enqueue(forwarded);
    }
    notifyListeners();
  }

  Future<void> _sendDeliveryReceipt({
    required String originalSenderDeviceId,
    required String originalMessageId,
    required String originalPacketId,
  }) async {
    final receiptPacketId =
        'rcpt-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
    final now = DateTime.now().toUtc();

    final receiptJson = jsonEncode({
      'receiptForPacketId': originalPacketId,
      'receiptForMessageId': originalMessageId,
      'deliveredAt': now.toIso8601String(),
    });
    final receiptPayload = Uint8List.fromList(utf8.encode(receiptJson));

    final receiptEnvelope = UniversalEnvelope(
      protocolVersion: 1,
      packetType: UniversalPacketType.receipt,
      packetId: receiptPacketId,
      messageId: originalMessageId,
      senderDeviceId: localDeviceId,
      recipientDeviceId: originalSenderDeviceId,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      ttl: 4,
      hopCount: 0,
      payloadType: UniversalPayloadType.ciphertext,
      encryptedPayload: receiptPayload,
    );

    _deduplication.markIfFresh(receiptEnvelope.packetId);
    await _transportManager.send(receiptEnvelope,
        targetPeerId: originalSenderDeviceId);
  }

  void _onPeerEncountered(MeshPeerRecord peer) {
    // When encountering a peer, drain queued packets addressed to them or awaiting relay
    final readyEntries = _relayQueue.getReadyEntries();
    for (final entry in readyEntries) {
      if (entry.envelope.recipientDeviceId == peer.deviceId ||
          entry.targetNextHopPeerId == peer.deviceId) {
        _transportManager
            .send(entry.envelope, targetPeerId: peer.deviceId)
            .then((success) {
          if (success) {
            _relayQueue.remove(entry.envelope.packetId);
          } else {
            _relayQueue.recordFailure(entry.envelope.packetId);
          }
        });
      }
    }
  }

  void _drainRelayQueue() {
    if (!_isRunning) return;

    final readyEntries = _relayQueue.getReadyEntries();
    for (final entry in readyEntries) {
      _transportManager
          .send(entry.envelope, targetPeerId: entry.targetNextHopPeerId)
          .then((success) {
        if (success) {
          _relayQueue.remove(entry.envelope.packetId);
        } else {
          _relayQueue.recordFailure(entry.envelope.packetId);
        }
      });
    }
  }

  @override
  void dispose() {
    _relayDrainTimer?.cancel();
    _incomingSub?.cancel();
    _peerConnectedSub?.cancel();
    _deliveredLocallyController.close();
    _relayedPacketsController.close();
    _receiptAcksController.close();
    super.dispose();
  }
}
