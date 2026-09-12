import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../auth/account_auth_controller.dart';
import '../core/connectivity_notifier.dart';
import '../core/hybrid_communication_manager.dart';
import '../core/network_monitor.dart';
import '../core/sync_manager.dart';
import '../core/sync_queue.dart';
import '../mesh/mesh_router.dart';
import '../mesh/peer_discovery.dart';
import '../mesh/transport_manager.dart';
import '../storage/offline_database.dart';
import 'message_repository.dart';

enum MessageDeliveryStatus {
  sending,
  sent,
  relaying,
  delivered,
  read,
  failed,
  expired
}

class MessageReaction {
  const MessageReaction({required this.userId, required this.emoji});
  final String userId;
  final String emoji;

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        userId: json['userId'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'userId': userId, 'emoji': emoji};
}

class OnlineMessage {
  const OnlineMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.senderDisplayName,
    this.senderAvatar,
    required this.text,
    this.mediaBytes,
    this.mediaMimeType,
    this.replyToMessageId,
    this.reactions = const [],
    this.isVoiceNote = false,
    this.voiceDurationSeconds = 0,
    required this.createdAt,
    required this.isMe,
    this.status = MessageDeliveryStatus.sent,
    this.expiresAt,
    this.expiresIn,
    this.remainingMs,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderUsername;
  final String senderDisplayName;
  final Uint8List? senderAvatar;
  final String text;
  final Uint8List? mediaBytes;
  final String? mediaMimeType;
  final String? replyToMessageId;
  final List<MessageReaction> reactions;
  final bool isVoiceNote;
  final int voiceDurationSeconds;
  final DateTime createdAt;
  final bool isMe;
  final MessageDeliveryStatus status;
  final DateTime? expiresAt; // When the message expires
  final String? expiresIn; // Human readable: '1m', '5m', '1h', '24h', '7d'
  final int? remainingMs; // Remaining milliseconds until expiration

  OnlineMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderUsername,
    String? senderDisplayName,
    Uint8List? senderAvatar,
    String? text,
    Uint8List? mediaBytes,
    String? mediaMimeType,
    String? replyToMessageId,
    List<MessageReaction>? reactions,
    bool? isVoiceNote,
    int? voiceDurationSeconds,
    DateTime? createdAt,
    bool? isMe,
    MessageDeliveryStatus? status,
    DateTime? expiresAt,
    String? expiresIn,
    int? remainingMs,
  }) {
    return OnlineMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      text: text ?? this.text,
      mediaBytes: mediaBytes ?? this.mediaBytes,
      mediaMimeType: mediaMimeType ?? this.mediaMimeType,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      reactions: reactions ?? this.reactions,
      isVoiceNote: isVoiceNote ?? this.isVoiceNote,
      voiceDurationSeconds: voiceDurationSeconds ?? this.voiceDurationSeconds,
      createdAt: createdAt ?? this.createdAt,
      isMe: isMe ?? this.isMe,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      expiresIn: expiresIn ?? this.expiresIn,
      remainingMs: remainingMs ?? this.remainingMs,
    );
  }

  factory OnlineMessage.fromJson(
      Map<String, dynamic> json, String currentUserId) {
    final media = json['media'] as Map<String, dynamic>?;
    final avatar =
        (json['avatar'] ?? json['senderAvatar']) as Map<String, dynamic>?;
    final senderId = json['senderId'] as String? ?? '';
    final reactionsList = (json['reactions'] as List<dynamic>? ?? [])
        .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
        .toList();

    MessageDeliveryStatus parseStatus(String? s) {
      switch (s) {
        case 'sending':
          return MessageDeliveryStatus.sending;
        case 'sent':
          return MessageDeliveryStatus.sent;
        case 'delivered':
          return MessageDeliveryStatus.delivered;
        case 'read':
          return MessageDeliveryStatus.read;
        case 'failed':
          return MessageDeliveryStatus.failed;
        default:
          return MessageDeliveryStatus.delivered;
      }
    }

    return OnlineMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      senderId: senderId,
      senderUsername: json['senderUsername'] as String? ?? '',
      senderDisplayName: json['senderDisplayName'] as String? ??
          json['senderUsername'] as String? ??
          '',
      senderAvatar: avatar == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(avatar['data'] as String))),
      text: json['text'] as String? ?? '',
      mediaBytes: media == null
          ? null
          : Uint8List.fromList(
              base64Url.decode(base64Url.normalize(media['data'] as String))),
      mediaMimeType: media?['mimeType'] as String?,
      replyToMessageId: json['replyToMessageId'] as String?,
      reactions: reactionsList,
      isVoiceNote: json['isVoiceNote'] as bool? ?? false,
      voiceDurationSeconds: json['voiceDurationSeconds'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isMe: senderId == currentUserId,
      status: parseStatus(json['status'] as String?),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      expiresIn: json['expiresIn'] as String?,
      remainingMs: json['remainingMs'] as int?,
    );
  }
}

class OnlineConversation {
  const OnlineConversation({
    required this.id,
    this.kind = 'direct',
    this.title,
    required this.participant,
    this.participants = const [],
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
    this.isOnline = false,
    this.typingUsers = const {},
  });

  final String id;
  final String kind;
  final String? title;
  final PublicProfile participant;
  final List<PublicProfile> participants;
  final OnlineMessage? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  final bool isOnline;
  final Set<String> typingUsers;

  String get displayName =>
      kind == 'group' && title != null && title!.isNotEmpty
          ? title!
          : participant.displayName;

  OnlineConversation copyWith({
    String? id,
    String? kind,
    String? title,
    PublicProfile? participant,
    List<PublicProfile>? participants,
    OnlineMessage? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
    bool? isOnline,
    Set<String>? typingUsers,
  }) {
    return OnlineConversation(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      participant: participant ?? this.participant,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
      typingUsers: typingUsers ?? this.typingUsers,
    );
  }
}

/// Controller managing production-quality online messaging, offline-first SQLite/document
/// persistence, synchronization queues, and real-time WebSockets.
class OnlineMessagingController extends ChangeNotifier {
  OnlineMessagingController({
    required this.auth,
    http.Client? client,
    OfflineDatabase? db,
    SyncQueue? syncQueue,
    MessageRepository? repository,
    NetworkMonitor? networkMonitor,
    TransportManager? transportManager,
    PeerDiscovery? peerDiscovery,
    MeshRouter? meshRouter,
    HybridCommunicationManager? hybridManager,
  })  : _client = client ?? http.Client(),
        _db = db ?? OfflineDatabase(),
        _networkMonitor = networkMonitor ?? NetworkMonitor() {
    _syncQueue = syncQueue ?? SyncQueue(db: _db);
    _repository =
        repository ?? MessageRepository(db: _db, syncQueue: _syncQueue);

    _syncManager = SyncManager(
      connectivity: ConnectivityNotifier(),
      networkMonitor: _networkMonitor,
      syncQueue: _syncQueue,
      repository: _repository,
      auth: auth,
      httpClient: _client,
    );

    _transportManager = transportManager ?? TransportManager();
    _peerDiscovery = peerDiscovery ??
        PeerDiscovery(
          transportManager: _transportManager,
          localDeviceId: auth.currentUserId ?? 'device-me',
        );
    _meshRouter = meshRouter ??
        MeshRouter(
          localDeviceId: auth.currentUserId ?? 'device-me',
          transportManager: _transportManager,
          peerDiscovery: _peerDiscovery,
        );

    _hybridManager = hybridManager ??
        HybridCommunicationManager(
          auth: auth,
          networkMonitor: _networkMonitor,
          repository: _repository,
          syncQueue: _syncQueue,
          syncManager: _syncManager,
          meshRouter: _meshRouter,
          transportManager: _transportManager,
          peerDiscovery: _peerDiscovery,
        );

    _repository.addListener(notifyListeners);
    _hybridManager.addListener(notifyListeners);
    auth.addListener(_onAuthChanged);

    _initLifecycle();
  }

  final AccountAuthController auth;
  final http.Client _client;
  final OfflineDatabase _db;
  late final SyncQueue _syncQueue;
  late final MessageRepository _repository;
  late final NetworkMonitor _networkMonitor;
  late final SyncManager _syncManager;
  late final TransportManager _transportManager;
  late final PeerDiscovery _peerDiscovery;
  late final MeshRouter _meshRouter;
  late final HybridCommunicationManager _hybridManager;

  final List<OnlineConversation> _conversations = [];
  final Map<String, List<OnlineMessage>> _messagesByConversation = {};
  final Map<String, Timer> _typingTimers = {};
  bool _isLoading = false;
  String? _error;
  bool _disposed = false;

  WebSocket? _socket;
  StreamSubscription? _wsSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isWsConnected = false;

  MessageRepository get repository => _repository;
  NetworkMonitor get networkMonitor => _networkMonitor;
  SyncManager get syncManager => _syncManager;
  TransportManager get transportManager => _transportManager;
  PeerDiscovery get peerDiscovery => _peerDiscovery;
  MeshRouter get meshRouter => _meshRouter;
  HybridCommunicationManager get hybridManager => _hybridManager;

  List<OnlineConversation> get conversations => _conversations.isNotEmpty
      ? List.unmodifiable(_conversations)
      : _repository.cachedConversations;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isWsConnected => _isWsConnected;
  int get totalUnreadCount =>
      conversations.fold(0, (sum, c) => sum + c.unreadCount);

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> _initLifecycle() async {
    await _repository.initialize();
    if (_disposed) return;
    await _networkMonitor.initialize();
    if (_disposed) return;
    await _syncManager.start();

    if (!_disposed && auth.isAuthenticated) {
      _initOnline();
    }
  }

  void _onAuthChanged() {
    if (auth.isAuthenticated) {
      _initOnline();
    } else {
      _disconnectWs();
      _conversations.clear();
      _messagesByConversation.clear();
      notifyListeners();
    }
  }

  void _initOnline() {
    loadConversations();
    _connectWs();
  }

  Future<void> _connectWs() async {
    _disconnectWs();
    final token = auth.token;
    if (token == null || _disposed) return;

    try {
      final wsUrl = _getWebSocketUrl(token);
      _socket = await WebSocket.connect(wsUrl);
      if (_disposed) {
        _socket?.close();
        return;
      }
      _isWsConnected = true;
      _reconnectAttempts = 0;

      _wsSubscription = _socket!.listen(
        _onWsMessage,
        onDone: _onWsDone,
        onError: (err) => _onWsDone(),
      );

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        if (_isWsConnected) {
          _socket?.add(jsonEncode({'type': 'ping'}));
        }
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  String _getWebSocketUrl(String token) {
    var base = auth.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    if (!base.endsWith('/')) base = '$base/';
    return '${base}v1/chat/ws?token=$token';
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'ready':
          _isWsConnected = true;
          notifyListeners();
          break;
        case 'message:new':
          _handleIncomingMessage(data['message'] as Map<String, dynamic>);
          break;
        case 'message:status':
          _handleMessageStatus(
            data['messageId'] as String,
            data['conversationId'] as String,
            data['status'] as String,
          );
          break;
        case 'message:reaction':
          _handleMessageReaction(
            data['messageId'] as String,
            data['conversationId'] as String,
            data['userId'] as String,
            data['emoji'] as String,
          );
          break;
        case 'message:deleted':
          _handleMessageDeleted(
            data['messageId'] as String,
            data['conversationId'] as String,
          );
          break;
        case 'typing':
          _handleTypingEvent(
            data['conversationId'] as String,
            (data['username'] as String? ?? data['userId'] as String? ?? '')
                .trim(),
            data['isTyping'] as bool? ?? false,
          );
          break;
      }
    } catch (_) {}
  }

  void _handleIncomingMessage(Map<String, dynamic> json) {
    final msg = OnlineMessage.fromJson(json, auth.currentUserId ?? '');
    final convId = msg.conversationId;

    _repository.saveIncomingMessage(msg,
        currentUserId: auth.currentUserId ?? '');

    final list = _messagesByConversation.putIfAbsent(convId, () => []);
    if (!list.any((m) => m.id == msg.id)) {
      list.add(msg);
    }

    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx >= 0) {
      final conv = _conversations.removeAt(idx);
      _conversations.insert(
        0,
        conv.copyWith(
          lastMessage: msg,
          unreadCount: msg.isMe ? conv.unreadCount : conv.unreadCount + 1,
          updatedAt: msg.createdAt,
        ),
      );
    }

    // Auto acknowledge delivery to sender
    if (!msg.isMe) {
      _sendStatusUpdate(msg.id, 'delivered');
    }

    notifyListeners();
  }

  void _handleMessageStatus(String messageId, String convId, String status) {
    MessageDeliveryStatus newStatus = MessageDeliveryStatus.delivered;
    if (status == 'read') newStatus = MessageDeliveryStatus.read;
    if (status == 'sent') newStatus = MessageDeliveryStatus.sent;

    _repository.updateMessageStatus(
      conversationId: convId,
      messageId: messageId,
      status: newStatus,
    );

    final list = _messagesByConversation[convId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(status: newStatus);
        notifyListeners();
      }
    }
  }

  void _handleMessageReaction(
      String messageId, String convId, String userId, String emoji) {
    final list = _messagesByConversation[convId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final currentReactions =
            List<MessageReaction>.from(list[idx].reactions);
        currentReactions.removeWhere((r) => r.userId == userId);
        currentReactions.add(MessageReaction(userId: userId, emoji: emoji));
        list[idx] = list[idx].copyWith(reactions: currentReactions);
        notifyListeners();
      }
    }
  }

  void _handleMessageDeleted(String messageId, String convId) {
    final list = _messagesByConversation[convId];
    if (list != null) {
      list.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
  }

  void _handleTypingEvent(String convId, String username, bool isTyping) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx >= 0) {
      final conv = _conversations[idx];
      final newTyping = Set<String>.from(conv.typingUsers);
      if (isTyping) {
        newTyping.add(username);
        _typingTimers[username]?.cancel();
        _typingTimers[username] = Timer(const Duration(seconds: 3), () {
          _handleTypingEvent(convId, username, false);
        });
      } else {
        newTyping.remove(username);
      }
      _conversations[idx] = conv.copyWith(typingUsers: newTyping);
      notifyListeners();
    }
  }

  void _onWsDone() {
    _isWsConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    if (!auth.isAuthenticated || _disposed) return;

    final delaySeconds =
        (_reconnectAttempts < 4) ? (1 << _reconnectAttempts) : 10;
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (auth.isAuthenticated && !_disposed) {
        _connectWs();
        loadConversations();
      }
    });
  }

  void _disconnectWs() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _socket?.close();
    _socket = null;
    _isWsConnected = false;
  }

  // â”€â”€ REST & Offline Operations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (auth.isConfigured && _networkMonitor.isOnline) {
        final response = await _request('GET', '/v1/chat/conversations');
        final list = response['conversations'] as List<dynamic>;
        _conversations.clear();
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final participantMap = map['participant'] as Map<String, dynamic>?;
          final avatar = participantMap?['avatar'] as Map<String, dynamic>?;

          final participant = participantMap != null
              ? PublicProfile(
                  id: participantMap['id'] as String? ?? '',
                  username: participantMap['username'] as String? ?? 'user',
                  displayName:
                      participantMap['displayName'] as String? ?? 'User',
                  avatarBytes: avatar == null
                      ? null
                      : Uint8List.fromList(base64Url.decode(
                          base64Url.normalize(avatar['data'] as String))),
                )
              : const PublicProfile(
                  id: 'unknown', username: 'user', displayName: 'User');

          final lastMsgMap = map['lastMessage'] as Map<String, dynamic>?;
          final lastMsg = lastMsgMap != null
              ? OnlineMessage.fromJson(lastMsgMap, auth.currentUserId ?? '')
              : null;

          final conv = OnlineConversation(
            id: map['id'] as String,
            kind: map['kind'] as String? ?? 'direct',
            title: map['title'] as String?,
            participant: participant,
            lastMessage: lastMsg,
            unreadCount: map['unreadCount'] as int? ?? 0,
            updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
                DateTime.now(),
            isOnline: participantMap?['isOnline'] as bool? ?? false,
          );

          _conversations.add(conv);
          await _repository.saveConversation(conv);
        }
      } else {
        if (_repository.cachedConversations.isEmpty) {
          _conversations.clear();
        } else {
          _conversations.clear();
          _conversations.addAll(_repository.cachedConversations);
        }
      }
    } catch (e) {
      _error = e.toString();
      if (_conversations.isEmpty && _repository.cachedConversations.isEmpty) {
        _conversations.clear();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<OnlineMessage> getMessages(String conversationId) {
    final cached =
        _repository.getMessages(conversationId, auth.currentUserId ?? '');
    if (cached.isNotEmpty) {
      return cached;
    }
    return List.unmodifiable(_messagesByConversation[conversationId] ?? []);
  }

  OnlineConversation? getConversation(String conversationId) {
    try {
      return _conversations.firstWhere(
        (c) => c.id == conversationId,
        orElse: () => _repository.cachedConversations
            .firstWhere((c) => c.id == conversationId),
      );
    } catch (_) {
      return null;
    }
  }

  Future<OnlineConversation> startConversationWith(PublicProfile user) async {
    final existingIndex = _conversations.indexWhere(
      (c) =>
          c.participant.username.toLowerCase() == user.username.toLowerCase(),
    );

    if (existingIndex >= 0) {
      return _conversations[existingIndex];
    }

    String convId = 'conv-${user.username.toLowerCase()}';

    if (auth.isConfigured && user.id.isNotEmpty && _networkMonitor.isOnline) {
      try {
        final res = await _request('POST', '/v1/chat/conversations', {
          'kind': 'direct',
          'recipientUserId': user.id,
        });
        convId = res['id'] as String;
      } catch (_) {}
    }

    final newConv = OnlineConversation(
      id: convId,
      participant: user,
      updatedAt: DateTime.now(),
      unreadCount: 0,
      isOnline: false,
    );

    _conversations.insert(0, newConv);
    _messagesByConversation[newConv.id] = [];
    await _repository.saveConversation(newConv);
    notifyListeners();
    return newConv;
  }

  Future<void> loadMessages(String conversationId) async {
    if (!auth.isConfigured || !_networkMonitor.isOnline) return;
    try {
      final res = await _request(
          'GET', '/v1/chat/conversations/$conversationId/messages');
      final list = res['messages'] as List<dynamic>;
      final messages = list
          .map((m) => OnlineMessage.fromJson(
              m as Map<String, dynamic>, auth.currentUserId ?? ''))
          .toList();

      _messagesByConversation[conversationId] = messages;
      for (final m in messages) {
        await _repository.saveIncomingMessage(m,
            currentUserId: auth.currentUserId ?? '');
      }
      notifyListeners();
    } catch (_) {}
  }

  void markAsRead(String conversationId) {
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0 && _conversations[idx].unreadCount > 0) {
      _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
      _repository.saveConversation(_conversations[idx]);
      notifyListeners();
    }

    final msgs = getMessages(conversationId);
    if (msgs.isNotEmpty) {
      final lastMsg = msgs.last;
      if (!lastMsg.isMe) {
        _sendStatusUpdate(lastMsg.id, 'read');
      }
    }
  }

  /// Send message offline-first: persists locally immediately, updates UI instantly,
  /// and automatically uploads via SyncManager when connectivity is available.
  Future<void> sendMessage({
    required String conversationId,
    required String text,
    Uint8List? mediaBytes,
    String? mediaMimeType,
    String? replyToMessageId,
    bool isVoiceNote = false,
    int voiceDurationSeconds = 0,
    String? expiresIn, // '1m', '5m', '1h', '24h', '7d'
  }) async {
    final profile = auth.profile;
    if (profile == null) return;

    final conv = getConversation(conversationId);
    if (conv == null) return;

    // 1. Optimistic offline-first write to persistent DB & SyncQueue
    final newMsg = await _repository.createLocalPendingMessage(
      conversationId: conversationId,
      sender: profile,
      text: text,
      mediaBytes: mediaBytes,
      mediaMimeType: mediaMimeType,
      replyToMessageId: replyToMessageId,
      expiresIn: expiresIn,
    );

    final list = _messagesByConversation.putIfAbsent(conversationId, () => []);
    list.add(newMsg);

    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      _conversations.removeAt(idx);
      _conversations.insert(
        0,
        conv.copyWith(
          lastMessage: newMsg,
          updatedAt: newMsg.createdAt,
        ),
      );
    }
    notifyListeners();

    // 2. If online and configured, trigger SyncManager immediately
    if (auth.isConfigured && _networkMonitor.isOnline) {
      await _syncManager.triggerSync();
    } else if (!auth.isConfigured) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final sentIdx = list.indexWhere((m) => m.id == newMsg.id);
      if (sentIdx >= 0) {
        list[sentIdx] =
            list[sentIdx].copyWith(status: MessageDeliveryStatus.delivered);
        await _repository.updateMessageStatus(
          conversationId: conversationId,
          messageId: newMsg.id,
          status: MessageDeliveryStatus.delivered,
        );
        notifyListeners();
      }
    }
  }

  void sendTyping(String conversationId, bool isTyping) {
    if (_isWsConnected) {
      _socket?.add(jsonEncode({
        'type': 'typing',
        'conversationId': conversationId,
        'isTyping': isTyping,
      }));
    }
  }

  Future<void> addReaction(String messageId, String emoji) async {
    for (final entry in _messagesByConversation.entries) {
      final list = entry.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final current = List<MessageReaction>.from(list[idx].reactions);
        current.removeWhere((r) => r.userId == (auth.currentUserId ?? ''));
        current.add(
            MessageReaction(userId: auth.currentUserId ?? 'me', emoji: emoji));
        list[idx] = list[idx].copyWith(reactions: current);
        await _repository.addReaction(
          conversationId: entry.key,
          messageId: messageId,
          userId: auth.currentUserId ?? 'me',
          emoji: emoji,
        );
        notifyListeners();
        break;
      }
    }

    if (auth.isConfigured && _networkMonitor.isOnline) {
      try {
        await _request(
            'POST', '/v1/chat/messages/$messageId/reactions', {'emoji': emoji});
      } catch (_) {}
    }
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    final list = _messagesByConversation[conversationId];
    if (list != null) {
      list.removeWhere((m) => m.id == messageId);
      await _repository.deleteMessage(
        conversationId: conversationId,
        messageId: messageId,
      );
      notifyListeners();
    }

    if (auth.isConfigured && _networkMonitor.isOnline) {
      try {
        await _request('DELETE', '/v1/chat/messages/$messageId');
      } catch (_) {}
    }
  }

  Future<void> _sendStatusUpdate(String messageId, String status) async {
    if (auth.isConfigured && _networkMonitor.isOnline) {
      try {
        await _request(
            'POST', '/v1/chat/messages/$messageId/status', {'status': status});
      } catch (_) {}
    }
  }

  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
    _messagesByConversation.remove(conversationId);
    notifyListeners();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = auth.token;
    var base = auth.baseUrl;
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
        response = await _client.post(uri,
            headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        response = await _client.put(uri,
            headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PATCH':
        response = await _client.patch(uri,
            headers: headers, body: body != null ? jsonEncode(body) : null);
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
    throw Exception(
        'Request failed with status ${response.statusCode}: ${response.body}');
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnectWs();
    _typingTimers.forEach((_, t) => t.cancel());
    _repository.removeListener(notifyListeners);
    _hybridManager.removeListener(notifyListeners);
    auth.removeListener(_onAuthChanged);
    _syncManager.stop();
    _hybridManager.dispose();
    _meshRouter.dispose();
    _networkMonitor.dispose();
    super.dispose();
  }
}
