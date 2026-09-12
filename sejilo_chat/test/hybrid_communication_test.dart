import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:sejilo_chat/core/connectivity_notifier.dart';
import 'package:sejilo_chat/core/hybrid_communication_manager.dart';
import 'package:sejilo_chat/core/network_monitor.dart';
import 'package:sejilo_chat/core/sync_manager.dart';
import 'package:sejilo_chat/core/sync_queue.dart';
import 'package:sejilo_chat/core/universal_envelope.dart';
import 'package:sejilo_chat/mesh/message_transport.dart';
import 'package:sejilo_chat/mesh/mesh_router.dart';
import 'package:sejilo_chat/mesh/peer_discovery.dart';
import 'package:sejilo_chat/mesh/transport_manager.dart';
import 'package:sejilo_chat/messaging/message_repository.dart';
import 'package:sejilo_chat/messaging/online_messaging_controller.dart';
import 'package:sejilo_chat/storage/offline_database.dart';

class MockTestTransport extends MessageTransport {
  MockTestTransport({
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

  void simulatePeerLoss(String peerId) {
    _peerLost.add(peerId);
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

  late OfflineDatabase db;
  late SyncQueue syncQueue;
  late MessageRepository repository;
  late NetworkMonitor networkMonitor;
  late AccountAuthController auth;
  late MockTestTransport wifiTransport;
  late MockTestTransport bleTransport;
  late TransportManager transportManager;
  late PeerDiscovery peerDiscovery;
  late MeshRouter meshRouter;
  late SyncManager syncManager;
  late HybridCommunicationManager hybridManager;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});

    final tempDir = Directory.systemTemp.createTempSync('sejilo_hybrid_test_');
    final dbFile = File('${tempDir.path}/test_db.json');
    db = OfflineDatabase(customPath: dbFile.path);
    await db.initialize();

    syncQueue = SyncQueue(db: db);
    repository = MessageRepository(db: db, syncQueue: syncQueue);
    await repository.initialize();

    networkMonitor = NetworkMonitor();
    networkMonitor.setOnlineOverride(true);

    final mockClient = MockClient((request) async {
      if (request.url.path == '/v1/users' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'user-me',
            'token': 'real.access.token.hybrid',
            'refreshToken': 'real.refresh.token.hybrid',
            'isNewUser': true,
            'profile': {
              'id': 'user-me',
              'email': body['email'],
              'username': body['username'],
              'displayName': body['displayName'],
              'bio': '',
              'avatar': null,
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.contains('/v1/chat/messages')) {
        return http.Response(
          jsonEncode({
            'message': {
              'id': 'srv-msg-${DateTime.now().millisecondsSinceEpoch}',
              'conversationId': 'conv-alice',
              'senderId': 'user-me',
              'senderUsername': 'me_user',
              'senderDisplayName': 'Me User',
              'text': 'Test Message',
              'status': 'sent',
              'createdAt': DateTime.now().toIso8601String(),
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    auth = AccountAuthController(client: mockClient);
    await auth.signUp(
      email: 'me@example.com',
      password: 'ValidPassword123!',
      username: 'me_user',
      displayName: 'Me User',
    );

    syncManager = SyncManager(
      connectivity: ConnectivityNotifier(),
      networkMonitor: networkMonitor,
      syncQueue: syncQueue,
      repository: repository,
      auth: auth,
      httpClient: mockClient,
    );

    wifiTransport = MockTestTransport(name: 'Mock Wi-Fi', type: TransportType.wifi, routeScore: 10000);
    bleTransport = MockTestTransport(name: 'Mock BLE', type: TransportType.bluetooth, routeScore: 9500);
    transportManager = TransportManager(transports: [wifiTransport, bleTransport]);
    await transportManager.startAll();

    peerDiscovery = PeerDiscovery(transportManager: transportManager, localDeviceId: 'user-me');
    meshRouter = MeshRouter(localDeviceId: 'user-me', transportManager: transportManager, peerDiscovery: peerDiscovery);

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
  });

  tearDown(() {
    hybridManager.dispose();
    meshRouter.dispose();
    peerDiscovery.dispose();
    transportManager.dispose();
    syncManager.stop();
    networkMonitor.dispose();
    auth.dispose();
  });

  group('Phase 8 — Hybrid Communication Manager Tests', () {
    test('Initial state is ONLINE and routes message via Internet with instant delivery', () async {
      expect(hybridManager.isOnline, isTrue);
      expect(hybridManager.statusLabel, 'Online');

      final msg = await hybridManager.sendMessageAuto(
        conversationId: 'conv-alice',
        text: 'Hello from Online Mode',
      );

      expect(msg, isNotNull);
      expect(msg!.text, 'Hello from Online Mode');

      final cached = repository.getMessages('conv-alice', auth.currentUserId ?? '');
      expect(cached.isNotEmpty, isTrue);
    });

    test('ONLINE → OFFLINE transition retains messages in local storage without data loss', () async {
      // 1. Drop Internet
      networkMonitor.setOnlineOverride(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(hybridManager.isOffline, isTrue);
      expect(hybridManager.statusLabel, 'Offline');

      // 2. Compose message offline
      final offlineMsg = await hybridManager.sendMessageAuto(
        conversationId: 'conv-alice',
        text: 'Message composed entirely offline',
      );

      expect(offlineMsg, isNotNull);
      expect(offlineMsg!.status, MessageDeliveryStatus.sending);

      // Verify message is persisted in local DB and sync queue
      final pendingQueue = await syncQueue.getPendingItems();
      expect(pendingQueue.any((i) => i.id == offlineMsg.id), isTrue);
    });

    test('OFFLINE → MESH transition detects nearby peer and routes packets over local mesh', () async {
      // 1. Drop Internet
      networkMonitor.setOnlineOverride(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hybridManager.isOffline, isTrue);

      // 2. Nearby BLE peer appears
      final peer = TransportPeerInfo(
        id: 'dev-neighbor-001',
        displayName: 'Alice Peer',
        transportType: TransportType.bluetooth,
        rssi: -50,
        lastSeen: DateTime.now(),
      );
      bleTransport.simulatePeer(peer);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(hybridManager.isMeshConnected, isTrue);
      expect(hybridManager.networkState, HybridNetworkState.meshConnected);

      // 3. Send message in Mesh mode
      final meshMsg = await hybridManager.sendMessageAuto(
        conversationId: 'dev-neighbor-001',
        text: 'Hello over Bluetooth Mesh!',
      );

      expect(meshMsg, isNotNull);
      expect(wifiTransport.sentEnvelopes.isNotEmpty || bleTransport.sentEnvelopes.isNotEmpty, isTrue);
    });

    test('MESH → ONLINE transition automatically uploads pending messages to backend', () async {
      // 1. Offline with pending message
      networkMonitor.setOnlineOverride(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await hybridManager.sendMessageAuto(
        conversationId: 'conv-alice',
        text: 'Pending sync message',
      );

      final initialPending = await syncQueue.getPendingItems();
      expect(initialPending.isNotEmpty, isTrue);

      // 2. Internet returns
      networkMonitor.setOnlineOverride(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(hybridManager.isOnline, isTrue);

      // 3. Verify sync queue has drained and uploaded
      final remainingPending = await syncQueue.getPendingItems();
      expect(remainingPending.isEmpty, isTrue);
    });

    test('ONLINE → MESH → ONLINE complete lifecycle preserves all messages and state', () async {
      // Phase 1: Online initial message
      await hybridManager.sendMessageAuto(conversationId: 'conv-lifecycle', text: 'Online Msg 1');

      // Phase 2: Switch to Mesh
      networkMonitor.setOnlineOverride(false);
      bleTransport.simulatePeer(
        TransportPeerInfo(
          id: 'dev-node-peer',
          displayName: 'Relay Peer',
          transportType: TransportType.bluetooth,
          rssi: -45,
          lastSeen: DateTime.now(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(hybridManager.isMeshConnected, isTrue);

      await hybridManager.sendMessageAuto(conversationId: 'conv-lifecycle', text: 'Mesh Msg 2');

      // Phase 3: Switch back to Online
      networkMonitor.setOnlineOverride(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hybridManager.isOnline, isTrue);

      // Verify all messages exist in repository without duplication
      final allMsgs = repository.getMessages('conv-lifecycle', auth.currentUserId ?? '');
      expect(allMsgs.length, 2);
      expect(allMsgs[0].text, 'Online Msg 1');
      expect(allMsgs[1].text, 'Mesh Msg 2');
    });
  });
}
