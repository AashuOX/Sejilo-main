import 'package:flutter/foundation.dart';
import '../auth/account_auth_controller.dart';
import '../core/mesh_client.dart';
import '../core/platform_capabilities.dart';
import 'online_messaging_controller.dart';

enum MessageTransport {
  online,
  nearbyMesh,
}

/// Unified Messaging Service coordinating between Bluetooth Mesh and Online WebSocket/REST Relay.
class MessageService extends ChangeNotifier {
  MessageService({
    required this.meshClient,
    required this.authController,
    required this.onlineController,
  });

  final MeshClient meshClient;
  final AccountAuthController authController;
  final OnlineMessagingController onlineController;

  MessageTransport _preferredTransport = MessageTransport.online;
  MessageTransport get preferredTransport => _preferredTransport;

  bool get isMeshAvailable => PlatformCapabilities.meshSupported && meshClient.isReady;
  bool get isOnlineAvailable => authController.isAuthenticated;

  int get totalNearbyPeers => isMeshAvailable ? meshClient.nearbyPeers.length : 0;
  int get totalOnlineUnread => isOnlineAvailable ? onlineController.totalUnreadCount : 0;
  int get totalBadgeCount => totalOnlineUnread;

  void setPreferredTransport(MessageTransport transport) {
    if (_preferredTransport != transport) {
      _preferredTransport = transport;
      notifyListeners();
    }
  }

  /// Automatically select best transport for a contact
  MessageTransport resolveTransport({required bool isNearby}) {
    if (isNearby && isMeshAvailable) {
      return MessageTransport.nearbyMesh;
    }
    return MessageTransport.online;
  }
}
