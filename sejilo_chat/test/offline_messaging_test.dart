import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:sejilo_chat/core/connectivity_notifier.dart';
import 'package:sejilo_chat/core/network_monitor.dart';
import 'package:sejilo_chat/core/sync_manager.dart';
import 'package:sejilo_chat/core/sync_queue.dart';
import 'package:sejilo_chat/messaging/message_repository.dart';
import 'package:sejilo_chat/messaging/online_messaging_controller.dart';
import 'package:sejilo_chat/storage/offline_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock secure storage
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'write') {
      store[call.arguments['key'] as String] =
          call.arguments['value'] as String;
      return null;
    } else if (call.method == 'read') {
      return store[call.arguments['key'] as String];
    } else if (call.method == 'delete') {
      store.remove(call.arguments['key'] as String);
      return null;
    } else if (call.method == 'deleteAll') {
      store.clear();
      return null;
    }
    return null;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sejilo_offline_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 6 — Offline Database & Sync Queue Tests', () {
    test('OfflineDatabase stores, retrieves, and survives simulated reload',
        () async {
      final dbPath = '${tempDir.path}/test_db.json';
      final db1 = OfflineDatabase(customPath: dbPath);
      await db1.initialize();

      await db1.insert(
          'conversations', 'conv-1', {'id': 'conv-1', 'title': 'Test Conv'});
      await db1.insert(
          'messages', 'msg-1', {'id': 'msg-1', 'text': 'Offline message 1'});

      final loaded = await db1.get('messages', 'msg-1');
      expect(loaded?['text'], 'Offline message 1');

      // Simulate app restart by initializing a new instance with the same path
      final db2 = OfflineDatabase(customPath: dbPath);
      await db2.initialize();

      final reloadedMsg = await db2.get('messages', 'msg-1');
      expect(reloadedMsg?['text'], 'Offline message 1');
      final reloadedConv = await db2.get('conversations', 'conv-1');
      expect(reloadedConv?['title'], 'Test Conv');
    });

    test('SyncQueue manages FIFO queue, status transitions, and retries',
        () async {
      final dbPath = '${tempDir.path}/test_sync_queue.json';
      final db = OfflineDatabase(customPath: dbPath);
      await db.initialize();
      final syncQueue = SyncQueue(db: db);

      final item1 = SyncQueueItem(
        id: 'sync-1',
        type: SyncOperationType.sendMessage,
        conversationId: 'conv-1',
        payload: {'text': 'First message'},
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final item2 = SyncQueueItem(
        id: 'sync-2',
        type: SyncOperationType.sendMessage,
        conversationId: 'conv-1',
        payload: {'text': 'Second message'},
        createdAt: DateTime.now(),
      );

      await syncQueue.enqueue(item1);
      await syncQueue.enqueue(item2);

      final pending = await syncQueue.getPendingItems();
      expect(pending.length, 2);
      expect(pending.first.id, 'sync-1');

      await syncQueue.markInProgress('sync-1');
      await syncQueue.markFailed('sync-1', 'Network timeout');

      final pendingAfterFail = await syncQueue.getPendingItems();
      expect(pendingAfterFail.first.attempts, 1);
      expect(pendingAfterFail.first.lastError, 'Network timeout');

      await syncQueue.markCompleted('sync-1');
      final remaining = await syncQueue.getPendingItems();
      expect(remaining.length, 1);
      expect(remaining.first.id, 'sync-2');
    });
  });

  group('Phase 6 — Offline-First MessageRepository Tests', () {
    test('composes offline pending message immediately with PENDING status',
        () async {
      final dbPath = '${tempDir.path}/test_repo.json';
      final db = OfflineDatabase(customPath: dbPath);
      await db.initialize();
      final syncQueue = SyncQueue(db: db);
      final repo = MessageRepository(db: db, syncQueue: syncQueue);
      await repo.initialize();

      const sender = AccountProfile(
        id: 'user-me',
        username: 'alice',
        displayName: 'Alice',
        email: 'alice@example.com',
      );

      final pendingMsg = await repo.createLocalPendingMessage(
        conversationId: 'conv-offline-1',
        sender: sender,
        text: 'This was written with zero internet!',
      );

      expect(pendingMsg.status, MessageDeliveryStatus.sending);
      expect(pendingMsg.text, 'This was written with zero internet!');

      final messages = repo.getMessages('conv-offline-1', 'user-me');
      expect(messages.length, 1);
      expect(messages.first.id, pendingMsg.id);

      final queued = await syncQueue.getPendingItems();
      expect(queued.length, 1);
      expect(
          queued.first.payload['text'], 'This was written with zero internet!');
    });

    test('server acknowledgement converts local pending message to SENT status',
        () async {
      final dbPath = '${tempDir.path}/test_repo_ack.json';
      final db = OfflineDatabase(customPath: dbPath);
      await db.initialize();
      final syncQueue = SyncQueue(db: db);
      final repo = MessageRepository(db: db, syncQueue: syncQueue);
      await repo.initialize();

      const sender = AccountProfile(
        id: 'user-me',
        username: 'alice',
        displayName: 'Alice',
        email: 'alice@example.com',
      );

      final pendingMsg = await repo.createLocalPendingMessage(
        conversationId: 'conv-1',
        sender: sender,
        text: 'Hello server',
      );

      await repo.markMessageSent(
        conversationId: 'conv-1',
        localTempId: pendingMsg.id,
        serverId: 'server-canonical-101',
        status: MessageDeliveryStatus.sent,
      );

      final msgs = repo.getMessages('conv-1', 'user-me');
      expect(msgs.length, 1);
      expect(msgs.first.id, 'server-canonical-101');
      expect(msgs.first.status, MessageDeliveryStatus.sent);
    });
  });

  group('Phase 6 — SyncManager Automatic Upload & Network Recovery Tests', () {
    test('uploads queued messages upon connectivity restoration', () async {
      final dbPath = '${tempDir.path}/test_sync_manager.json';
      final db = OfflineDatabase(customPath: dbPath);
      await db.initialize();
      final syncQueue = SyncQueue(db: db);
      final repo = MessageRepository(db: db, syncQueue: syncQueue);
      await repo.initialize();

      var serverReceivedMessage = false;
      final mockClient = MockClient((req) async {
        if (req.url.path == '/v1/auth/phone/otp-requests' &&
            req.method == 'POST') {
          return http.Response(jsonEncode({'devCode': '123456'}), 200);
        }
        if (req.url.path == '/v1/auth/phone/verify' && req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'token': 'token-server-1',
              'refreshToken': 'rt-1',
              'isNewUser': false,
              'profile': {
                'id': 'server-user-1',
                'email': 'sync_user@phone.sejilochat.net',
                'username': 'sync_user',
                'displayName': 'Sync User',
                'bio': '',
                'avatar': null,
              },
            }),
            200,
          );
        }
        if (req.url.path.contains('/messages') && req.method == 'POST') {
          serverReceivedMessage = true;
          return http.Response(
            jsonEncode({'id': 'server-msg-999', 'status': 'sent'}),
            201,
          );
        }
        return http.Response('{}', 200);
      });

      final auth = AccountAuthController(client: mockClient);
      final code = await auth.sendPhoneOtp('+15551112222');
      await auth.verifyPhoneOtp(
        phoneNumber: '+15551112222',
        otp: code,
        username: 'sync_user',
        displayName: 'Sync User',
      );

      final networkMonitor = NetworkMonitor();
      networkMonitor.setOnlineOverride(false); // Start offline

      final syncManager = SyncManager(
        connectivity: ConnectivityNotifier(),
        networkMonitor: networkMonitor,
        syncQueue: syncQueue,
        repository: repo,
        auth: auth,
        httpClient: mockClient,
      );
      await syncManager.start();

      // Create message while offline
      await repo.createLocalPendingMessage(
        conversationId: 'conv-test-sync',
        sender: auth.profile!,
        text: 'Waiting for internet...',
      );

      expect(serverReceivedMessage, isFalse);
      expect((await syncQueue.getPendingItems()).length, 1);

      // Internet returns!
      networkMonitor.setOnlineOverride(true);
      await syncManager.triggerSync();

      expect(serverReceivedMessage, isTrue);
      expect((await syncQueue.getPendingItems()).isEmpty, isTrue);

      final messages = repo.getMessages('conv-test-sync', auth.currentUserId!);
      expect(messages.first.id, 'server-msg-999');
      expect(messages.first.status, MessageDeliveryStatus.sent);

      await syncManager.stop();
      auth.dispose();
    });

    test(
        'retains messages and retries when server temporarily fails with 500 error',
        () async {
      final dbPath = '${tempDir.path}/test_server_fail.json';
      final db = OfflineDatabase(customPath: dbPath);
      await db.initialize();
      final syncQueue = SyncQueue(db: db);
      final repo = MessageRepository(db: db, syncQueue: syncQueue);
      await repo.initialize();

      var shouldFail = true;
      final mockClient = MockClient((req) async {
        if (req.url.path == '/v1/auth/phone/otp-requests' &&
            req.method == 'POST') {
          return http.Response(jsonEncode({'devCode': '654321'}), 200);
        }
        if (req.url.path == '/v1/auth/phone/verify' && req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'token': 'token-server-2',
              'refreshToken': 'rt-2',
              'isNewUser': false,
              'profile': {
                'id': 'server-user-2',
                'email': 'retry_user@phone.sejilochat.net',
                'username': 'retry_user',
                'displayName': 'Retry User',
                'bio': '',
                'avatar': null,
              },
            }),
            200,
          );
        }
        if (shouldFail) {
          return http.Response('{"error":"Internal Server Error"}', 500);
        }
        return http.Response(jsonEncode({'id': 'server-recovered-1'}), 200);
      });

      final auth = AccountAuthController(client: mockClient);
      final code = await auth.sendPhoneOtp('+15553334444');
      await auth.verifyPhoneOtp(
        phoneNumber: '+15553334444',
        otp: code,
        username: 'retry_user',
        displayName: 'Retry User',
      );

      final networkMonitor = NetworkMonitor();
      networkMonitor.setOnlineOverride(true);

      final syncManager = SyncManager(
        connectivity: ConnectivityNotifier(),
        networkMonitor: networkMonitor,
        syncQueue: syncQueue,
        repository: repo,
        auth: auth,
        httpClient: mockClient,
      );
      await syncManager.start();

      await repo.createLocalPendingMessage(
        conversationId: 'conv-retry',
        sender: auth.profile!,
        text: 'Important message!',
      );

      // First sync attempt fails with 500
      await syncManager.triggerSync();

      final queueAfterFail = await syncQueue.getPendingItems();
      expect(queueAfterFail.length, 1);
      expect(queueAfterFail.first.attempts, 1);
      expect(queueAfterFail.first.status, SyncItemStatus.failed);

      // Server recovers!
      shouldFail = false;
      await syncManager.triggerSync();

      final queueAfterSuccess = await syncQueue.getPendingItems();
      expect(queueAfterSuccess.isEmpty, isTrue);

      final msgs = repo.getMessages('conv-retry', auth.currentUserId!);
      expect(msgs.first.id, 'server-recovered-1');
      expect(msgs.first.status, MessageDeliveryStatus.sent);

      await syncManager.stop();
      auth.dispose();
    });
  });
}
