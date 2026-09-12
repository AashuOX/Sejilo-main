import 'package:flutter/foundation.dart';
import '../storage/offline_database.dart';

enum SyncOperationType { sendMessage, sendReaction, markAsRead, deleteMessage }

enum SyncItemStatus { pending, inProgress, failed, completed }

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.type,
    required this.conversationId,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastAttemptAt,
    this.status = SyncItemStatus.pending,
    this.lastError,
  });

  final String id;
  final SyncOperationType type;
  final String conversationId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final DateTime? lastAttemptAt;
  final SyncItemStatus status;
  final String? lastError;

  SyncQueueItem copyWith({
    String? id,
    SyncOperationType? type,
    String? conversationId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? attempts,
    DateTime? lastAttemptAt,
    SyncItemStatus? status,
    String? lastError,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      type: type ?? this.type,
      conversationId: conversationId ?? this.conversationId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'conversationId': conversationId,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'status': status.name,
        'lastError': lastError,
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    SyncOperationType parseType(String? name) {
      return SyncOperationType.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SyncOperationType.sendMessage,
      );
    }

    SyncItemStatus parseStatus(String? name) {
      return SyncItemStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SyncItemStatus.pending,
      );
    }

    return SyncQueueItem(
      id: json['id'] as String,
      type: parseType(json['type'] as String?),
      conversationId: json['conversationId'] as String? ?? '',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      attempts: json['attempts'] as int? ?? 0,
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.tryParse(json['lastAttemptAt'] as String)
          : null,
      status: parseStatus(json['status'] as String?),
      lastError: json['lastError'] as String?,
    );
  }
}

/// Persistent synchronization queue maintaining ordered pending actions across app restarts.
class SyncQueue extends ChangeNotifier {
  SyncQueue({required OfflineDatabase db}) : _db = db;

  final OfflineDatabase _db;
  static const String _tableName = 'sync_queue';

  Future<void> enqueue(SyncQueueItem item) async {
    await _db.insert(_tableName, item.id, item.toJson());
    notifyListeners();
  }

  Future<List<SyncQueueItem>> getPendingItems() async {
    final records = await _db.query(
      _tableName,
      where: (r) => r['status'] != SyncItemStatus.completed.name,
      orderBy: (a, b) {
        final dateA = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime.now();
        final dateB = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime.now();
        return dateA.compareTo(dateB);
      },
    );
    return records.map((r) => SyncQueueItem.fromJson(r)).toList();
  }

  Future<void> markInProgress(String id) async {
    await _db.update(_tableName, id, {
      'status': SyncItemStatus.inProgress.name,
      'lastAttemptAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> markFailed(String id, String error) async {
    final record = await _db.get(_tableName, id);
    final attempts = (record?['attempts'] as int? ?? 0) + 1;
    await _db.update(_tableName, id, {
      'status': SyncItemStatus.failed.name,
      'attempts': attempts,
      'lastError': error,
      'lastAttemptAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> markCompleted(String id) async {
    await _db.delete(_tableName, id);
    notifyListeners();
  }

  Future<void> clear() async {
    await _db.clearTable(_tableName);
    notifyListeners();
  }
}
