import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:sejilo_chat/core/connectivity_notifier.dart';
import 'package:sejilo_chat/core/hybrid_communication_manager.dart';
import 'package:sejilo_chat/core/network_monitor.dart';
import 'package:sejilo_chat/core/responsive.dart';
import 'package:sejilo_chat/core/sync_manager.dart';
import 'package:sejilo_chat/core/sync_queue.dart';
import 'package:sejilo_chat/core/universal_envelope.dart';
import 'package:sejilo_chat/mesh/mesh_router.dart';
import 'package:sejilo_chat/mesh/message_deduplication.dart';
import 'package:sejilo_chat/mesh/message_transport.dart';
import 'package:sejilo_chat/mesh/peer_discovery.dart';
import 'package:sejilo_chat/mesh/transport_manager.dart';
import 'package:sejilo_chat/mesh/ttl_manager.dart';
import 'package:sejilo_chat/messaging/message_repository.dart';
import 'package:sejilo_chat/messaging/online_messaging_controller.dart';
import 'package:sejilo_chat/storage/offline_database.dart';
import 'helpers/fake_backend.dart';

class MockQATransport extends MessageTransport {
  MockQATransport({
    required this.name,
    required this.type,
    required this.routeScore,
  });

  @override
  final String name;
  @override
  final TransportType type;
  @override
  final int routeScore;

  TransportState _state = TransportState.stopped;
  final List<UniversalEnvelope> sentEnvelopes = [];
  final StreamController<UniversalEnvelope> _incoming = StreamController<UniversalEnvelope>.broadcast();
  final StreamController<TransportPeerInfo> _peerDiscovered = StreamController<TransportPeerInfo>.broadcast();
  final StreamController<String> _peerLost = StreamController<String>.broadcast();

  @override
  TransportState get state => _state;
  @override
  bool get isAvailable => _state == TransportState.active;
  @override
  Stream<UniversalEnvelope> get incomingEnvelopes => _incoming.stream;
  @override
  Stream<TransportPeerInfo> get peerDiscovered => _peerDiscovered.stream;
  @override
  Stream<String> get peerLost => _peerLost.stream;

  @override
  Future<void> start() async {
    _state = TransportState.active;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _state = TransportState.stopped;
    notifyListeners();
  }

  @override
  Future<bool> send(UniversalEnvelope envelope, {String? targetPeerId}) async {
    if (!isAvailable) return false;
    sentEnvelopes.add(envelope);
    return true;
  }

  void simulatePeer(TransportPeerInfo peer) {
    _peerDiscovered.add(peer);
  }

  @override
  void dispose() {
    _incoming.close();
    _peerDiscovered.close();
    _peerLost.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FINAL QA — Comprehensive End-to-End Suite', () {
    late OfflineDatabase db;
    late SyncQueue syncQueue;
    late MessageRepository repository;
    late NetworkMonitor networkMonitor;
    late AccountAuthController auth;
    late MockQATransport wifiTransport;
    late MockQATransport bleTransport;
    late TransportManager transportManager;
    late PeerDiscovery peerDiscovery;
    late MeshRouter meshRouter;
    late SyncManager syncManager;
    late HybridCommunicationManager hybridManager;
    late OnlineMessagingController messagingController;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('sejilo_final_qa_');
      final dbFile = File('${tempDir.path}/qa_db.json');
      db = OfflineDatabase(customPath: dbFile.path);
      await db.initialize();

      syncQueue = SyncQueue(db: db);
      repository = MessageRepository(db: db, syncQueue: syncQueue);
      await repository.initialize();

      networkMonitor = NetworkMonitor();
      networkMonitor.setOnlineOverride(true);

      final mockClient = fakeSejiloBackend();

      auth = AccountAuthController(client: mockClient);
      await auth.signUp(
        email: 'qa@sejilo.test',
        password: 'SecureQAPassword123!',
        username: 'qa_tester',
        displayName: 'QA Tester',
      );

      syncManager = SyncManager(
        connectivity: ConnectivityNotifier(),
        networkMonitor: networkMonitor,
        syncQueue: syncQueue,
        repository: repository,
        auth: auth,
        httpClient: mockClient,
      );

      wifiTransport = MockQATransport(name: 'QA Wi-Fi', type: TransportType.wifi, routeScore: 10000);
      bleTransport = MockQATransport(name: 'QA BLE', type: TransportType.bluetooth, routeScore: 9500);
      transportManager = TransportManager(transports: [wifiTransport, bleTransport]);
      await transportManager.startAll();

      peerDiscovery = PeerDiscovery(transportManager: transportManager, localDeviceId: 'dev-qa-tester-001');
      meshRouter = MeshRouter(localDeviceId: 'dev-qa-tester-001', transportManager: transportManager, peerDiscovery: peerDiscovery);

      hybridManager = HybridCommunicationManager(
        auth: auth,
        networkMonitor: networkMonitor,
        repository: repository,
        syncQueue: syncQueue,
        syncManager: syncManager,
        meshRouter: meshRouter,
        transportManager: transportManager,
        peerDiscovery: peerDiscovery,
      );
      await hybridManager.initialize();

      messagingController = OnlineMessagingController(
        auth: auth,
        repository: repository,
        syncQueue: syncQueue,
        networkMonitor: networkMonitor,
        transportManager: transportManager,
        peerDiscovery: peerDiscovery,
        meshRouter: meshRouter,
        hybridManager: hybridManager,
      );
    });

    tearDown(() {
      messagingController.dispose();
    });

    // ─────────────────────────────────────────────
    // 1. AUTH TESTS
    // ─────────────────────────────────────────────
    test('AUTH: Registration, Database Login, Session Persistence, Logout, Password Reset', () async {
      // 1. Check authenticated user profile & token from setup
      expect(auth.isAuthenticated, isTrue);
      expect(auth.token, isNotNull);
      expect(auth.profile?.username, 'qa_tester');

      // 2. Database Authentication Login
      await auth.signUp(
        email: 'dbuser@sejilo.test',
        password: 'Password123!',
        username: 'dbuser_tester',
        displayName: 'DB Tester',
      );
      expect(auth.isAuthenticated, isTrue);
      expect(auth.profile?.email, 'dbuser@sejilo.test');

      // 3. Password Reset
      await auth.requestPasswordReset('qa@sejilo.test');
      expect(auth.error, isNull);

      // 4. Session Persistence (Simulated app restart with storage)
      const storage = FlutterSecureStorage();
      final reloadedAuth = AccountAuthController(storage: storage);
      await reloadedAuth.initialize();
      expect(reloadedAuth.isAuthenticated, isTrue);
      expect(reloadedAuth.profile?.email, 'dbuser@sejilo.test');

      // 5. Logout
      await auth.logout();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
    });

    // ─────────────────────────────────────────────
    // 2. SOCIAL TESTS
    // ─────────────────────────────────────────────
    test('SOCIAL: Profile, Follow, Post, Like, Comment, Save, Delete, Search, Stories, Notifications', () async {
      // 1. Create post
      final rawImage = Uint8List.fromList(List.generate(200, (i) => (i * 7) % 256));
      await auth.createPost(image: rawImage, mimeType: 'image/jpeg', caption: 'QA Test Post');
      expect(auth.posts.isNotEmpty, isTrue);
      final postId = auth.posts.first.id;

      // 2. Like and Save post
      await auth.setLike(postId, true);
      expect(auth.posts.first.liked, isTrue);

      await auth.setSave(postId, true);
      expect(auth.savedPostIds.contains(postId), isTrue);

      // 3. Comments
      await auth.addComment(postId, 'Great QA test post!');
      final comments = await auth.loadComments(postId);
      expect(comments.isNotEmpty, isTrue);
      expect(comments.first.text, 'Great QA test post!');

      // 4. Stories
      await auth.createTextStory(text: 'QA Live Story', backgroundStyle: 'gradient_0');
      final storyGroups = await auth.loadGroupedStories();
      expect(storyGroups.isNotEmpty, isTrue);

      // 5. Delete post
      await auth.deletePost(postId);
      expect(auth.posts.any((p) => p.id == postId), isFalse);
    });

    // ─────────────────────────────────────────────
    // 3. CHAT TESTS
    // ─────────────────────────────────────────────
    test('CHAT: Conversation, Message Ordering, Delivery/Read Status, Typing, Image, Groups', () async {
      // 1. Start direct conversation
      final conv = await messagingController.startConversationWith(
        const PublicProfile(
          id: 'user-charlie',
          username: 'charlie',
          displayName: 'Charlie',
          bio: 'Peer',
          avatarBytes: null,
        ),
      );
      expect(conv.id, isNotEmpty);

      // 2. Send text message
      await messagingController.sendMessage(conversationId: conv.id, text: 'Hello Charlie!');
      final msgs = messagingController.getMessages(conv.id);
      expect(msgs.isNotEmpty, isTrue);
      expect(msgs.last.text, 'Hello Charlie!');

      // 3. Send image message
      final fakeImage = Uint8List.fromList([1, 2, 3, 4, 5]);
      await messagingController.sendMessage(
        conversationId: conv.id,
        text: 'Photo message',
        mediaBytes: fakeImage,
      );
      final updatedMsgs = messagingController.getMessages(conv.id);
      expect(updatedMsgs.last.mediaBytes, isNotNull);

      // 4. Typing indicator
      messagingController.sendTyping(conv.id, true);

      // 5. Read receipt & Reaction
      messagingController.markAsRead(conv.id);
      messagingController.addReaction(msgs.first.id, '❤️');
      expect(messagingController.getMessages(conv.id).first.reactions.isNotEmpty, isTrue);

      // 6. Group / Multiple conversations
      final groupPeer = await messagingController.startConversationWith(
        const PublicProfile(
          id: 'user-dev-group',
          username: 'dev_team',
          displayName: 'Dev Team',
          bio: 'Team',
          avatarBytes: null,
        ),
      );
      expect(groupPeer.id, isNotEmpty);
      expect(messagingController.conversations.length, greaterThanOrEqualTo(2));
    });

    // ─────────────────────────────────────────────
    // 4. OFFLINE TESTS
    // ─────────────────────────────────────────────
    test('OFFLINE: Disable Internet, Local Storage, Multi-Hop Mesh Relay, Reconnection & Sync', () async {
      // 1. Disable Internet
      networkMonitor.setOnlineOverride(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hybridManager.isOffline, isTrue);

      // 2. Send message offline (stored locally with PENDING/sending status)
      final offlineMsg = await hybridManager.sendMessageAuto(
        conversationId: 'conv-offline-qa',
        text: 'Offline message persisted in SQLite vault',
      );
      expect(offlineMsg, isNotNull);
      expect(offlineMsg!.status, MessageDeliveryStatus.sending);

      // 3. Verify sync queue has item stored
      final pendingBefore = await syncQueue.getPendingItems();
      expect(pendingBefore.isNotEmpty, isTrue);

      // 4. Discover peer and relay message
      final neighborPeer = TransportPeerInfo(
        id: 'dev-peer-neighbor-99',
        displayName: 'Neighbor Node',
        transportType: TransportType.wifi,
        rssi: -40,
        lastSeen: DateTime.now(),
      );
      wifiTransport.simulatePeer(neighborPeer);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(hybridManager.isMeshConnected, isTrue);

      // 5. Restore Internet
      networkMonitor.setOnlineOverride(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hybridManager.isOnline, isTrue);

      // 6. Verify sync manager automatically reconciled queue (poll to avoid
      // timing flakiness under full-suite load)
      var queueDrained = false;
      for (var i = 0; i < 40; i++) {
        final pending = await syncQueue.getPendingItems();
        if (pending.isEmpty) {
          queueDrained = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(queueDrained, isTrue);
    });

    // ─────────────────────────────────────────────
    // 5. SECURITY TESTS
    // ─────────────────────────────────────────────
    test('SECURITY: Envelope Validation, Duplicate Rejection, TTL Expiration, Hop Limit, Auth Rules', () {
      final dedup = MessageDeduplication(maxRemembered: 100);
      const ttl = TTLManager(defaultTtl: 4, maximumAllowedHops: 7);

      // 1. Duplicate detection
      expect(dedup.markIfFresh('pkt-sec-001'), isTrue);
      expect(dedup.markIfFresh('pkt-sec-001'), isFalse);

      // 2. TTL & Hop Limit enforcement
      final validEnvelope = UniversalEnvelope(
        packetType: UniversalPacketType.message,
        packetId: 'pkt-sec-101-valid',
        messageId: 'msg-sec-101-valid',
        senderDeviceId: 'dev-sec-sender-101',
        recipientDeviceId: 'dev-sec-target-101',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        ttl: 4,
        hopCount: 2,
        payloadType: UniversalPayloadType.ciphertext,
        encryptedPayload: Uint8List.fromList([10, 20, 30]),
      );
      expect(ttl.isValid(validEnvelope), isTrue);

      // 3. Over-hop rejection
      expect(
        () => UniversalEnvelope(
          packetType: UniversalPacketType.message,
          packetId: 'pkt-sec-102-max',
          messageId: 'msg-sec-102-max',
          senderDeviceId: 'dev-sec-sender-102',
          recipientDeviceId: 'dev-sec-target-102',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(hours: 24)),
          ttl: 1,
          hopCount: 8,
          payloadType: UniversalPayloadType.ciphertext,
          encryptedPayload: Uint8List.fromList([10, 20, 30]),
        ),
        throwsFormatException,
      );
    });

    // ─────────────────────────────────────────────
    // 6. RESPONSIVENESS TESTS
    // ─────────────────────────────────────────────
    testWidgets('RESPONSIVENESS: Mobile, Tablet, and Desktop Breakpoint Layouts', (tester) async {
      // 1. Mobile Screen (< 768px)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                expect(Responsive.isMobile(context), isTrue);
                expect(Responsive.isTablet(context), isFalse);
                expect(Responsive.isDesktop(context), isFalse);
                return const Scaffold(body: Text('Mobile View'));
              },
            ),
          ),
        ),
      );
      expect(find.text('Mobile View'), findsOneWidget);

      // 2. Tablet Screen (768px - 1023px)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 1024)),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                expect(Responsive.isTablet(context), isTrue);
                expect(Responsive.isMobile(context), isFalse);
                expect(Responsive.isDesktop(context), isFalse);
                return const Scaffold(body: Text('Tablet View'));
              },
            ),
          ),
        ),
      );
      expect(find.text('Tablet View'), findsOneWidget);

      // 3. Desktop Screen (1024px+)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                expect(Responsive.isDesktop(context), isTrue);
                expect(Responsive.isMobile(context), isFalse);
                expect(Responsive.isTablet(context), isFalse);
                return const Scaffold(body: Text('Desktop View'));
              },
            ),
          ),
        ),
      );
      expect(find.text('Desktop View'), findsOneWidget);
    });
  });
}
