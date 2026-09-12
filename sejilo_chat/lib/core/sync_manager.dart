import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../auth/account_auth_controller.dart';
import '../messaging/message_repository.dart';
import '../messaging/online_messaging_controller.dart';
import 'connectivity_notifier.dart';
import 'delivery_transport.dart';
import 'internet_relay_transport.dart';
import 'network_monitor.dart';
import 'sync_queue.dart';
import 'universal_envelope.dart';

/// Production sync manager for offline-first messaging and mesh envelope syncing.
///
/// Features:
/// 1. Auto-upload pending messages and chat mutations when connectivity is restored.
/// 2. Handles server acknowledgements, assigning canonical message IDs and updating UI states.
/// 3. Resilient retry with exponential backoff on transient network and server errors.
/// 4. Bridges mesh store-and-forward relay transport.
class SyncManager extends ChangeNotifier {
  SyncManager({
    required ConnectivityNotifier connectivity,
    InternetRelayTransport? internetTransport,
    NetworkMonitor? networkMonitor,
    SyncQueue? syncQueue,
    MessageRepository? repository,
    AccountAuthController? auth,
    http.Client? httpClient,
  })  : _connectivity = connectivity,
        _internet = internetTransport,
        _networkMonitor = networkMonitor,
        _syncQueue = syncQueue,
        _repository = repository,
        _auth = auth,
        _client = httpClient ?? http.Client();

  final ConnectivityNotifier _connectivity;
  final InternetRelayTransport? _internet;
  final NetworkMonitor? _networkMonitor;
  final SyncQueue? _syncQueue;
  final MessageRepository? _repository;
  final AccountAuthController? _auth;
  final http.Client _client;

  final Map<String, _OutboundEnvelopeEntry> _envelopeQueue = {};
  StreamSubscription<UniversalEnvelope>? _internetSub;
  StreamSubscription<bool>? _networkSub;
  Timer? _periodicSyncTimer;
  bool _running = false;
  bool _isSyncing = false;

  /// Cursor of the last successfully pulled sync event (ISO-8601 UTC).
  /// Persistent across app launches; used for incremental sync pulls.
  String? _syncCursor;

  bool get isSyncing => _isSyncing;

  String? get syncCursor => _syncCursor;

  /// Restore the sync cursor persisted by the app shell.
  void restoreSyncCursor(String? cursor) {
    if (cursor != null && cursor.isNotEmpty) _syncCursor = cursor;
  }

  ValueChanged<UniversalEnvelope>? onEnvelopeReceived;
  void Function(String packetId, String state)? onStateChanged;

  /// Start sync manager. Idempotent.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    if (_internet != null) {
      _internetSub = _internet.receivedEnvelopes.listen(
        _onInboundEnvelope,
        onError: (Object e) => debugPrint('[SyncManager] internet rx error: $e'),
      );
      if (_internet.state == DeliveryTransportState.stopped) {
        unawaited(_internet.start());
      }
    }

    _connectivity.addListener(_onConnectivityChanged);

    if (_networkMonitor != null) {
      _networkSub = _networkMonitor.onConnectivityChanged.listen((isOnline) {
        if (isOnline) {
          triggerSync();
        }
      });
    }

    // Periodic sync attempt every 30 seconds
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isOnline || (_networkMonitor?.isOnline ?? false)) {
        triggerSync();
      }
    });

    if (_connectivity.isOnline || (_networkMonitor?.isOnline ?? false)) {
      await triggerSync();
      await _flushEnvelopeQueue();
    }
  }

  /// Pull new events from the server since the last sync cursor
  /// (cursor-based incremental sync).
  ///
  /// Returns the number of events applied, or -1 when no auth/sync
  /// capability is configured.
  Future<int> pullIncremental() async {
    if (_auth == null || !_auth.isConfigured || !_auth.isAuthenticated) return -1;

    final cursor = await _loadSyncCursor();
    final cursorParam = cursor != null ? '?cursor=${Uri.encodeQueryComponent(cursor)}' : '';
    Map<String, dynamic> res;
    try {
      res = await _request('GET', '/v1/sync$cursorParam');
    } catch (err) {
      debugPrint('[SyncManager] Incremental sync pull failed: $err');
      return -1;
    }

    final events = (res['events'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (events.isEmpty) return 0;

    final applied = await _applySyncEvents(events);

    final nextCursor = res['nextCursor'] as String?;
    if (nextCursor != null && nextCursor.isNotEmpty) {
      _syncCursor = nextCursor;
      await _persistSyncCursor(_syncCursor!);
    }

    return applied;
  }

  /// Apply a batch of server sync events (new messages, conversation
  /// mutations, reactions) to the local repository.
  Future<int> _applySyncEvents(List<Map<String, dynamic>> events) async {
    if (_repository == null || _auth == null) return 0;
    final currentUserId = _auth.currentUserId ?? '';
    var applied = 0;

    for (final event in events) {
      final type = event['type'] as String? ?? '';
      final payload = event['payload'] as Map<String, dynamic>? ?? {};

      try {
        switch (type) {
          case 'message:new':
            await _repository.saveIncomingMessage(
              OnlineMessage.fromJson(
                payload['message'] as Map<String, dynamic>? ?? {},
                currentUserId,
              ),
              currentUserId: currentUserId,
            );
            applied++;
            break;
          case 'message:read':
            await _repository.updateMessageStatus(
              conversationId: payload['conversationId'] as String? ?? '',
              messageId: payload['messageId'] as String? ?? '',
              status: MessageDeliveryStatus.read,
            );
            applied++;
            break;
          default:
            debugPrint('[SyncManager] Unhandled sync event type: $type');
        }
      } catch (err) {
        debugPrint('[SyncManager] Failed to apply event $type: $err');
      }
    }

    return applied;
  }

  Future<String?> _loadSyncCursor() async {
    if (_syncCursor != null) return _syncCursor;
    try {
      final repository = _repository;
      if (repository == null) return null;
      final persisted = await repository.loadSyncCursor();
      if (persisted != null && persisted.isNotEmpty) _syncCursor = persisted;
      return _syncCursor;
    } catch (err) {
      debugPrint('[SyncManager] Failed to load sync cursor: $err');
      return _syncCursor;
    }
  }

  Future<void> _persistSyncCursor(String cursor) async {
    try {
      await _repository?.saveSyncCursor(cursor);
    } catch (err) {
      debugPrint('[SyncManager] Failed to persist sync cursor: $err');
    }
  }

  /// Stop sync manager and release resources.
  Future<void> stop() async {
    _running = false;
    _periodicSyncTimer?.cancel();
    _connectivity.removeListener(_onConnectivityChanged);
    await _internetSub?.cancel();
    await _networkSub?.cancel();
    _internetSub = null;
    _networkSub = null;
    await _internet?.stop();
  }

  void _onConnectivityChanged() {
    if (_connectivity.isOnline) {
      triggerSync();
      _flushEnvelopeQueue();
    }
  }

  // ── Offline Chat Sync Engine ──────────────────────────────────

  /// Flush all queued offline messages and actions to the backend.
  Future<void> triggerSync() async {
    if (_isSyncing || _syncQueue == null || _auth == null || !_auth.isAuthenticated) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final pendingItems = await _syncQueue.getPendingItems();
      for (final item in pendingItems) {
        // Stop sync immediately if internet drops mid-sync
        final isOnline = _connectivity.isOnline || (_networkMonitor?.isOnline ?? true);
        if (!isOnline) break;

        await _syncQueue.markInProgress(item.id);

        try {
          switch (item.type) {
            case SyncOperationType.sendMessage:
              await _syncSendMessage(item);
              break;
            case SyncOperationType.sendReaction:
              await _syncSendReaction(item);
              break;
            case SyncOperationType.markAsRead:
              await _syncMarkAsRead(item);
              break;
            case SyncOperationType.deleteMessage:
              await _syncDeleteMessage(item);
              break;
          }
          await _syncQueue.markCompleted(item.id);
        } catch (err) {
          debugPrint('[SyncManager] Failed to sync item ${item.id}: $err');
          await _syncQueue.markFailed(item.id, err.toString());
          if (_repository != null && item.type == SyncOperationType.sendMessage) {
            await _repository.updateMessageStatus(
              conversationId: item.conversationId,
              messageId: item.id,
              status: MessageDeliveryStatus.failed,
            );
          }
        }
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncSendMessage(SyncQueueItem item) async {
    if (_auth == null || !_auth.isConfigured) return;
    final convId = item.conversationId;
    final payload = item.payload;

    final requestBody = <String, dynamic>{
      'conversationId': convId,
      if (payload['text'] != null) 'text': payload['text'],
      if (payload['media'] != null) 'media': payload['media'],
      if (payload['replyToMessageId'] != null) 'replyToMessageId': payload['replyToMessageId'],
    };

    final res = await _request('POST', '/v1/chat/conversations/$convId/messages', requestBody);
    final serverId = res['id'] as String? ?? 'msg-${DateTime.now().millisecondsSinceEpoch}';

    if (_repository != null) {
      await _repository.markMessageSent(
        conversationId: convId,
        localTempId: item.id,
        serverId: serverId,
        status: MessageDeliveryStatus.sent,
      );
    }
  }

  Future<void> _syncSendReaction(SyncQueueItem item) async {
    if (_auth == null || !_auth.isConfigured) return;
    final msgId = item.payload['messageId'] as String? ?? item.id;
    final emoji = item.payload['emoji'] as String? ?? '❤️';
    await _request('POST', '/v1/chat/messages/$msgId/reactions', {'emoji': emoji});
  }

  Future<void> _syncMarkAsRead(SyncQueueItem item) async {
    if (_auth == null || !_auth.isConfigured) return;
    final msgId = item.payload['messageId'] as String? ?? item.id;
    await _request('POST', '/v1/chat/messages/$msgId/status', {'status': 'read'});
  }

  Future<void> _syncDeleteMessage(SyncQueueItem item) async {
    if (_auth == null || !_auth.isConfigured) return;
    final msgId = item.payload['messageId'] as String? ?? item.id;
    await _request('DELETE', '/v1/chat/messages/$msgId');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (_auth == null) throw Exception('Auth controller required');
    final token = _auth.token;
    var base = _auth.baseUrl;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final uri = Uri.parse('$base$path');

    final headers = <String, String>{
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };

    http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _client.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        response = await _client.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PATCH':
        response = await _client.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'DELETE':
        response = await _client.delete(uri, headers: headers);
        break;
      default:
        throw UnimplementedError(method);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Sync request failed with status ${response.statusCode}: ${response.body}');
  }

  // ── Mesh Envelope Relay Compatibility ─────────────────────────

  Future<void> send(UniversalEnvelope envelope) async {
    final entry = _OutboundEnvelopeEntry(envelope: envelope);
    _envelopeQueue[envelope.packetId] = entry;
    onStateChanged?.call(envelope.packetId, 'queued');
    notifyListeners();
    if (_connectivity.isOnline &&
        _internet != null &&
        _internet.state == DeliveryTransportState.ready) {
      await _trySendEnvelope(entry);
    }
  }

  void receiveFromMesh(UniversalEnvelope envelope) => _onInboundEnvelope(envelope);

  int cleanExpired() {
    final now = DateTime.now().toUtc();
    final expired = _envelopeQueue.entries
        .where((e) => e.value.envelope.expiresAt.isBefore(now))
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _envelopeQueue.remove(id);
      onStateChanged?.call(id, 'expired');
    }
    if (expired.isNotEmpty) notifyListeners();
    return expired.length;
  }

  Future<void> _flushEnvelopeQueue() async {
    if (_internet == null || _internet.state != DeliveryTransportState.ready) return;
    final entries = List<_OutboundEnvelopeEntry>.from(_envelopeQueue.values);
    for (final entry in entries) {
      if (entry.state != 'delivered' && entry.state != 'expired') {
        await _trySendEnvelope(entry);
      }
    }
  }

  Future<void> _trySendEnvelope(_OutboundEnvelopeEntry entry) async {
    if (_internet == null) return;
    entry.state = 'sending';
    entry.attempts++;
    onStateChanged?.call(entry.envelope.packetId, 'sending');
    notifyListeners();

    try {
      await _internet.send(entry.envelope);
      entry.state = 'delivered';
      _envelopeQueue.remove(entry.envelope.packetId);
      onStateChanged?.call(entry.envelope.packetId, 'delivered');
      notifyListeners();
    } catch (e) {
      entry.state = 'failed';
      entry.lastError = e.toString();
      onStateChanged?.call(entry.envelope.packetId, 'failed');
      notifyListeners();
    }
  }

  void _onInboundEnvelope(UniversalEnvelope envelope) {
    onEnvelopeReceived?.call(envelope);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

class _OutboundEnvelopeEntry {
  _OutboundEnvelopeEntry({required this.envelope});
  final UniversalEnvelope envelope;
  String state = 'queued';
  int attempts = 0;
  String? lastError;
}
