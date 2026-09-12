import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../auth/account_auth_controller.dart';
import '../core/sync_queue.dart';
import '../storage/offline_database.dart';
import 'online_messaging_controller.dart';

/// Single Source of Truth repository providing offline-first persistence,
/// reactive streams, optimistic writes, and sync orchestration.
class MessageRepository extends ChangeNotifier {
  MessageRepository({
    required OfflineDatabase db,
    required SyncQueue syncQueue,
  })  : _db = db,
        _syncQueue = syncQueue;

  final OfflineDatabase _db;
  final SyncQueue _syncQueue;

  static const String _tableConversations = 'conversations';
  static const String _tableMessages = 'messages';

  final Map<String, List<OnlineMessage>> _memoryMessages = {};
  final List<OnlineConversation> _memoryConversations = [];

  List<OnlineConversation> get cachedConversations =>
      List.unmodifiable(_memoryConversations);

  Future<void> initialize() async {
    await _db.initialize();
    await _loadFromLocalDb();
  }

  Future<void> _loadFromLocalDb() async {
    final convRecords = await _db.query(
      _tableConversations,
      orderBy: (a, b) {
        final dateA = DateTime.tryParse(a['updatedAt'] as String? ?? '') ??
            DateTime.now();
        final dateB = DateTime.tryParse(b['updatedAt'] as String? ?? '') ??
            DateTime.now();
        return dateB.compareTo(dateA);
      },
    );

    _memoryConversations.clear();
    for (final r in convRecords) {
      final participantMap = r['participant'] as Map<String, dynamic>?;
      final avatar = participantMap?['avatar'] as Map<String, dynamic>?;
      final participant = participantMap != null
          ? PublicProfile(
              id: participantMap['id'] as String? ?? '',
              username: participantMap['username'] as String? ?? 'user',
              displayName: participantMap['displayName'] as String? ?? 'User',
              avatarBytes: avatar == null
                  ? null
                  : Uint8List.fromList(base64Url
                      .decode(base64Url.normalize(avatar['data'] as String))),
            )
          : const PublicProfile(
              id: 'unknown', username: 'user', displayName: 'User');

      final lastMsgMap = r['lastMessage'] as Map<String, dynamic>?;
      final lastMsg =
          lastMsgMap != null ? OnlineMessage.fromJson(lastMsgMap, '') : null;

      _memoryConversations.add(
        OnlineConversation(
          id: r['id'] as String,
          kind: r['kind'] as String? ?? 'direct',
          title: r['title'] as String?,
          participant: participant,
          lastMessage: lastMsg,
          unreadCount: r['unreadCount'] as int? ?? 0,
          updatedAt: DateTime.tryParse(r['updatedAt'] as String? ?? '') ??
              DateTime.now(),
          isOnline: r['isOnline'] as bool? ?? false,
        ),
      );
    }

    final msgRecords = await _db.query(
      _tableMessages,
      orderBy: (a, b) {
        final dateA = DateTime.tryParse(a['createdAt'] as String? ?? '') ??
            DateTime.now();
        final dateB = DateTime.tryParse(b['createdAt'] as String? ?? '') ??
            DateTime.now();
        return dateA.compareTo(dateB);
      },
    );

    _memoryMessages.clear();
    for (final m in msgRecords) {
      final convId = m['conversationId'] as String? ?? '';
      if (convId.isNotEmpty) {
        final msg = OnlineMessage.fromJson(m, '');
        _memoryMessages.putIfAbsent(convId, () => []).add(msg);
      }
    }

    notifyListeners();
  }

  // ── Query Methods ──────────────────────────────────────────

  List<OnlineMessage> getMessages(String conversationId, String currentUserId) {
    final list = _memoryMessages[conversationId] ?? [];
    return list
        .map((m) => m.copyWith(isMe: m.senderId == currentUserId))
        .toList();
  }

  OnlineConversation? getConversation(String conversationId) {
    try {
      return _memoryConversations.firstWhere((c) => c.id == conversationId);
    } catch (_) {
      return null;
    }
  }

  String? findConversationIdForMessage(String messageId) {
    for (final entry in _memoryMessages.entries) {
      if (entry.value.any((m) => m.id == messageId)) {
        return entry.key;
      }
    }
    return null;
  }

  // ── Offline-First Write & Optimistic Mutation ─────────────

  /// Create and save a new message locally with PENDING status immediately.
  Future<OnlineMessage> createLocalPendingMessage({
    required String conversationId,
    required AccountProfile sender,
    required String text,
    Uint8List? mediaBytes,
    String? mediaMimeType,
    String? replyToMessageId,
    String? expiresIn,
  }) async {
    final tempId =
        'pending-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
    final createdAt = DateTime.now();
    final msg = OnlineMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: sender.id,
      senderUsername: sender.username,
      senderDisplayName: sender.displayName,
      senderAvatar: sender.avatarBytes,
      text: text.trim(),
      mediaBytes: mediaBytes,
      mediaMimeType: mediaMimeType,
      replyToMessageId: replyToMessageId,
      createdAt: createdAt,
      isMe: true,
      status: MessageDeliveryStatus.sending,
      expiresIn: expiresIn,
      expiresAt: _expirationFor(createdAt, expiresIn),
    );

    // 1. Add to in-memory store
    final list = _memoryMessages.putIfAbsent(conversationId, () => []);
    list.add(msg);

    // 2. Update conversation order and last message
    final idx = _memoryConversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      final conv = _memoryConversations.removeAt(idx);
      final updatedConv = conv.copyWith(
        lastMessage: msg,
        updatedAt: msg.createdAt,
      );
      _memoryConversations.insert(0, updatedConv);
      await _saveConversationToDb(updatedConv);
    }

    // 3. Persist message to local DB
    await _saveMessageToDb(msg);

    // 4. Enqueue in persistent sync queue
    final syncItem = SyncQueueItem(
      id: tempId,
      type: SyncOperationType.sendMessage,
      conversationId: conversationId,
      payload: {
        'clientMessageId': tempId,
        'conversationId': conversationId,
        'text': text.trim(),
        if (mediaBytes != null)
          'media': {
            'mimeType': mediaMimeType ?? 'image/jpeg',
            'data': base64Url.encode(mediaBytes).replaceAll('=', ''),
          },
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (expiresIn != null) 'expiresIn': expiresIn,
      },
      createdAt: msg.createdAt,
    );
    await _syncQueue.enqueue(syncItem);

    notifyListeners();
    return msg;
  }

  DateTime? _expirationFor(DateTime createdAt, String? expiresIn) =>
      switch (expiresIn) {
        '1m' => createdAt.add(const Duration(minutes: 1)),
        '5m' => createdAt.add(const Duration(minutes: 5)),
        '1h' => createdAt.add(const Duration(hours: 1)),
        '24h' => createdAt.add(const Duration(hours: 24)),
        '7d' => createdAt.add(const Duration(days: 7)),
        _ => null,
      };

  /// Mark message acknowledged and sent by server.
  Future<void> markMessageSent({
    required String conversationId,
    required String localTempId,
    required String serverId,
    MessageDeliveryStatus status = MessageDeliveryStatus.sent,
  }) async {
    final list = _memoryMessages[conversationId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == localTempId);
      if (idx >= 0) {
        final updated = list[idx].copyWith(id: serverId, status: status);
        list[idx] = updated;
        await _db.delete(_tableMessages, localTempId);
        await _saveMessageToDb(updated);
        notifyListeners();
      }
    }
  }

  /// Update delivery status of a local message.
  Future<void> updateMessageStatus({
    required String conversationId,
    required String messageId,
    required MessageDeliveryStatus status,
  }) async {
    final list = _memoryMessages[conversationId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final updated = list[idx].copyWith(status: status);
        list[idx] = updated;
        await _saveMessageToDb(updated);
        notifyListeners();
      }
    }
  }

  /// Add a reaction to a message in memory and local DB.
  Future<void> addReaction({
    required String conversationId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    final list = _memoryMessages[conversationId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final current = List<MessageReaction>.from(list[idx].reactions);
        current.removeWhere((r) => r.userId == userId);
        current.add(MessageReaction(userId: userId, emoji: emoji));
        final updated = list[idx].copyWith(reactions: current);
        list[idx] = updated;
        await _saveMessageToDb(updated);
        notifyListeners();
      }
    }
  }

  /// Delete a message from memory and local DB.
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final list = _memoryMessages[conversationId];
    if (list != null) {
      list.removeWhere((m) => m.id == messageId);
      await _db.delete(_tableMessages, messageId);
      notifyListeners();
    }
  }

  /// Save or reconcile an incoming message from server or sync.
  Future<void> saveIncomingMessage(OnlineMessage msg,
      {required String currentUserId}) async {
    final convId = msg.conversationId;
    final list = _memoryMessages.putIfAbsent(convId, () => []);

    final existingIdx = list.indexWhere((m) => m.id == msg.id);
    if (existingIdx >= 0) {
      list[existingIdx] = msg;
    } else {
      list.add(msg);
    }

    final idx = _memoryConversations.indexWhere((c) => c.id == convId);
    if (idx >= 0) {
      final conv = _memoryConversations.removeAt(idx);
      final updatedConv = conv.copyWith(
        lastMessage: msg,
        unreadCount: msg.senderId == currentUserId
            ? conv.unreadCount
            : conv.unreadCount + 1,
        updatedAt: msg.createdAt,
      );
      _memoryConversations.insert(0, updatedConv);
      await _saveConversationToDb(updatedConv);
    }

    await _saveMessageToDb(msg);
    notifyListeners();
  }

  /// Save or update conversation locally.
  Future<void> saveConversation(OnlineConversation conv) async {
    final idx = _memoryConversations.indexWhere((c) => c.id == conv.id);
    if (idx >= 0) {
      _memoryConversations[idx] = conv;
    } else {
      _memoryConversations.insert(0, conv);
    }
    await _saveConversationToDb(conv);
    notifyListeners();
  }

  // ── Database Helper Serialization ─────────────────────────

  static const String _tableMetadata = 'metadata';
  static const String _cursorKey = 'sync_cursor';

  /// Persisted cursor of the last successfully pulled server sync event.
  Future<String?> loadSyncCursor() async {
    try {
      final record = await _db.get(_tableMetadata, _cursorKey);
      return record?['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Store the sync cursor so incremental pulls resume across restarts.
  Future<void> saveSyncCursor(String cursor) async {
    try {
      await _db.insert(_tableMetadata, _cursorKey, {'value': cursor});
    } catch (_) {
      // Non-fatal: cursor is an optimization, not correctness-critical.
    }
  }

  Future<void> _saveMessageToDb(OnlineMessage msg) async {
    final json = {
      'id': msg.id,
      'conversationId': msg.conversationId,
      'senderId': msg.senderId,
      'senderUsername': msg.senderUsername,
      'senderDisplayName': msg.senderDisplayName,
      if (msg.senderAvatar != null)
        'avatar': {
          'mimeType': 'image/jpeg',
          'data': base64Url.encode(msg.senderAvatar!).replaceAll('=', ''),
        },
      'text': msg.text,
      if (msg.mediaBytes != null)
        'media': {
          'mimeType': msg.mediaMimeType ?? 'image/jpeg',
          'data': base64Url.encode(msg.mediaBytes!).replaceAll('=', ''),
        },
      'replyToMessageId': msg.replyToMessageId,
      'reactions': msg.reactions.map((r) => r.toJson()).toList(),
      'isVoiceNote': msg.isVoiceNote,
      'voiceDurationSeconds': msg.voiceDurationSeconds,
      'createdAt': msg.createdAt.toIso8601String(),
      'status': msg.status.name,
    };
    await _db.insert(_tableMessages, msg.id, json);
  }

  Future<void> _saveConversationToDb(OnlineConversation conv) async {
    final json = {
      'id': conv.id,
      'kind': conv.kind,
      'title': conv.title,
      'participant': {
        'id': conv.participant.id,
        'username': conv.participant.username,
        'displayName': conv.participant.displayName,
        if (conv.participant.avatarBytes != null)
          'avatar': {
            'mimeType': 'image/jpeg',
            'data': base64Url
                .encode(conv.participant.avatarBytes!)
                .replaceAll('=', ''),
          },
      },
      'unreadCount': conv.unreadCount,
      'updatedAt': conv.updatedAt.toIso8601String(),
      'isOnline': conv.isOnline,
    };
    await _db.insert(_tableConversations, conv.id, json);
  }
}
