import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../security/device_identity.dart';
import '../security/attachment_policy.dart';
import '../security/secure_message_store.dart';
import '../security/secure_outbox_store.dart';
import 'app_preferences.dart';
import 'ble_mesh_service.dart';
import 'mesh_wire_protocol.dart';

class LocalMessage {
  const LocalMessage({
    required this.author,
    required this.body,
    required this.createdAt,
    this.id = '',
    this.attachmentPath,
    this.attachmentType,
    this.replyToId,
    this.reactions = const <String, int>{},
    this.isPinned = false,
    this.deliveryState = 'queued',
    this.conversationId,
  });

  final String id;
  final String author;
  final String body;
  final DateTime createdAt;
  final String? attachmentPath;
  final String? attachmentType;
  final String? replyToId;
  final Map<String, int> reactions;
  final bool isPinned;
  final String deliveryState;
  final String? conversationId;

  String get timeLabel {
    final local = createdAt.toLocal();
    final now = DateTime.now();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Today $time';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $time';
  }

  LocalMessage copyWith(
          {String? body,
          Map<String, int>? reactions,
          bool? isPinned,
          String? deliveryState}) =>
      LocalMessage(
        id: id,
        author: author,
        body: body ?? this.body,
        createdAt: createdAt,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
        replyToId: replyToId,
        reactions: reactions ?? this.reactions,
        isPinned: isPinned ?? this.isPinned,
        deliveryState: deliveryState ?? this.deliveryState,
        conversationId: conversationId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'attachmentPath': attachmentPath,
        'attachmentType': attachmentType,
        'replyToId': replyToId,
        'reactions': reactions,
        'isPinned': isPinned,
        'deliveryState': deliveryState,
        'conversationId': conversationId,
      };

  factory LocalMessage.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final author = json['author'] as String;
    return LocalMessage(
      id: json['id'] as String? ??
          '${createdAt.microsecondsSinceEpoch}-$author',
      author: author,
      body: json['body'] as String,
      createdAt: createdAt,
      attachmentPath: json['attachmentPath'] as String?,
      attachmentType: json['attachmentType'] as String?,
      replyToId: json['replyToId'] as String?,
      reactions: (json['reactions'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value as int)),
      isPinned: json['isPinned'] as bool? ?? false,
      deliveryState: json['deliveryState'] as String? ?? 'delivered',
      conversationId: json['conversationId'] as String?,
    );
  }
}

class FriendProfile {
  const FriendProfile(
      {required this.id, required this.username, required this.addedAt});

  final String id;
  final String username;
  final DateTime addedAt;

  String get verificationCode =>
      DeviceIdentity.verificationCodeForFingerprint(id) ?? id;

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'addedAt': addedAt.toIso8601String()};

  factory FriendProfile.fromJson(Map<String, dynamic> json) => FriendProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

class MeshClient extends ChangeNotifier {
  MeshClient({AppPreferences? preferences})
      : preferences = preferences ?? AppPreferences(),
        _storage = const FlutterSecureStorage();

  final AppPreferences preferences;
  final FlutterSecureStorage _storage;
  late final SecureMessageStore _messageStore = SecureMessageStore(_storage);
  late final SecureOutboxStore _outboxStore = SecureOutboxStore(_storage);
  final List<LocalMessage> _messages = [];
  final List<FriendProfile> _friends = [];
  final Set<String> _blockedPeerIds = <String>{};
  String _username = 'Sejilo user';
  int _avatarIndex = 0;
  bool _needsOnboarding = false;
  bool _shareNearby = false;
  String? _localityName;
  String? _localityGroupId;
  double? _localityLatitude;
  double? _localityLongitude;
  String? _activeConversationId;
  String? _activeConversationName;
  String? _activeGroupId;
  BleMeshService? _meshService;
  StreamSubscription<IncomingMeshMessage>? _incomingSubscription;
  StreamSubscription<MeshDeliveryUpdate>? _deliverySubscription;

  List<LocalMessage> get messages => List.unmodifiable(_messages);
  List<LocalMessage> get activeMessages => _messages
      .where((message) => message.conversationId == _activeConversationId)
      .toList(growable: false);
  List<FriendProfile> get friends => List.unmodifiable(_friends);
  Set<String> get blockedPeerIds => Set.unmodifiable(_blockedPeerIds);
  List<LocalMessage> searchMessages(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return activeMessages;
    return activeMessages
        .where((message) =>
            message.body.toLowerCase().contains(needle) ||
            message.author.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  List<LocalMessage> get pinnedMessages => activeMessages
      .where((message) => message.isPinned)
      .toList(growable: false);
  String get username => _username;
  int get avatarIndex => _avatarIndex;
  bool get needsOnboarding => _needsOnboarding;
  bool get shareNearby => _shareNearby;
  String? get localityName => _localityName;
  String? get localityGroupId => _localityGroupId;
  double? get localityLatitude => _localityLatitude;
  double? get localityLongitude => _localityLongitude;
  String? get activeConversationId => _activeConversationId;
  String get activeConversationName =>
      _activeConversationName ?? 'Nearby mesh channel';
  bool get isDirectConversation =>
      _activeConversationId != null && _activeGroupId == null;
  bool get isGroupConversation => _activeGroupId != null;
  List<NearbyMeshPeer> get nearbyPeers => _meshService?.peers ?? const [];
  String? get meshError => _meshService?.error;
  DeviceIdentity? _identity;
  DeviceIdentity? get identity => _identity;
  String? _initializationError;
  String? get initializationError => _initializationError;
  bool get isReady => _identity != null;
  bool get isMeshAvailable => _meshService?.isStarted ?? false;
  String? get myVerificationCode => _identity?.verificationCode;
  String? get myFullVerificationKey => _identity?.fingerprint;
  String get meshDiagnostics {
    final service = _meshService;
    if (service == null) return 'BLE service is not initialized';
    return 'radio ${service.radioScanHits} | Sejilo ${service.scanHits} | links ${service.peripheralLinks}/${service.centralLinks} | sent ${service.sentFrames} | received ${service.receivedFrames} | verified ${service.verifiedPackets} | rejected ${service.invalidFrames}';
  }

  int get queuedMessageCount => _messages
      .where((message) =>
          message.deliveryState.startsWith('queued') ||
          message.deliveryState.startsWith('sent'))
      .length;

  String get redactedDiagnostics => <String>[
        'SejiloChat 0.4.1',
        'Platform: ${Platform.operatingSystem}',
        'Bluetooth service: ${isMeshAvailable ? 'running' : 'stopped'}',
        'Visible nearby: $shareNearby',
        'Direct peers: ${nearbyPeers.where((peer) => peer.hops == 0).length}',
        'Reachable peers: ${nearbyPeers.length}',
        'Queued messages: $queuedMessageCount',
        'Storage: ${isReady ? 'ready' : 'unavailable'}',
        if (meshError != null)
          'Recent connection issue: ${_safeError(meshError!)}',
      ].join('\n');

  String _safeError(String value) => value
      .replaceAll(RegExp(r'[A-Za-z0-9_-]{20,}'), '[redacted]')
      .replaceAll(RegExp(r'([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'), '[device]');

  Future<void> initialize() async {
    try {
      _identity = await DeviceIdentityStore(_storage).loadOrCreate();
      final storedUsername = await _storage.read(key: 'profile.username.v1');
      _needsOnboarding = storedUsername == null;
      _username = storedUsername ?? _username;
      _avatarIndex =
          int.tryParse(await _storage.read(key: 'profile.avatar.v1') ?? '') ??
              0;
      _shareNearby = await _storage.read(key: 'presence.enabled.v1') == 'true';
      _localityName = await _storage.read(key: 'presence.locality.v1');
      _localityGroupId = await _storage.read(key: 'presence.group.v1');
      _localityLatitude = double.tryParse(
          await _storage.read(key: 'presence.latitude.v1') ?? '');
      _localityLongitude = double.tryParse(
          await _storage.read(key: 'presence.longitude.v1') ?? '');
      final storedFriends = await _storage.read(key: 'friends.v1');
      if (storedFriends != null) {
        _friends
          ..clear()
          ..addAll((jsonDecode(storedFriends) as List<dynamic>).map((friend) =>
              FriendProfile.fromJson(friend as Map<String, dynamic>)));
      }
      final storedBlocked = await _storage.read(key: 'blocked_peers.v1');
      if (storedBlocked != null) {
        _blockedPeerIds.addAll(
          (jsonDecode(storedBlocked) as List<dynamic>).whereType<String>(),
        );
      }
      _messages
        ..clear()
        ..addAll(await _messageStore.load());
      await _configureMeshService();
    } catch (_) {
      _initializationError = 'Secure local storage is unavailable.';
    }
    notifyListeners();
  }

  Future<void> queueMessage(String body,
      {String? attachmentPath,
      String? attachmentType,
      String? replyToId}) async {
    if (!isReady) return;
    final now = DateTime.now();
    final id =
        '${_identity!.shortId}-${now.microsecondsSinceEpoch}-${_messages.length}';
    _messages.add(LocalMessage(
        id: id,
        author: 'You',
        body: body,
        createdAt: now,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
        replyToId: replyToId,
        conversationId: _activeConversationId));
    await _messageStore.save(_messages);
    Uint8List? attachmentBytes;
    if (attachmentPath != null && attachmentType != null) {
      final file = File(attachmentPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length <= MeshContentCodec.maxAttachmentBytes) {
          attachmentBytes = bytes;
        }
      }
    }
    if ((body.trim().isNotEmpty || attachmentBytes != null) &&
        _meshService?.isStarted == true) {
      final sent = _activeConversationId == null
          ? await _meshService!.broadcastMessage(
              id,
              body,
              attachmentType: attachmentType,
              attachmentBytes: attachmentBytes,
            )
          : _activeGroupId != null
              ? await _meshService!.sendGroupMessage(
                  id,
                  body,
                  groupId: _activeGroupId!,
                  attachmentType: attachmentType,
                  attachmentBytes: attachmentBytes,
                )
              : await _meshService!.sendDirectMessage(
                  id,
                  body,
                  recipientId: _activeConversationId!,
                  attachmentType: attachmentType,
                  attachmentBytes: attachmentBytes,
                );
      final index = _messages.indexWhere((message) => message.id == id);
      if (index >= 0) {
        _messages[index] = _messages[index].copyWith(
          deliveryState: sent
              ? 'sent - awaiting acknowledgement'
              : 'queued - waiting for a peer',
        );
        await _messageStore.save(_messages);
      }
    }
    notifyListeners();
  }

  Future<void> _receiveMeshMessage(IncomingMeshMessage incoming) async {
    if (_messages.any((message) => message.id == incoming.id)) return;
    if (_blockedPeerIds.contains(incoming.senderFingerprint)) return;
    final trusted = isFriend(incoming.senderFingerprint);
    if (preferences.trustedOnly && !trusted) return;
    String? attachmentPath;
    final acceptsAttachment = switch (preferences.autoDownloadPolicy) {
      AutoDownloadPolicy.never => false,
      AutoDownloadPolicy.trustedPeers => trusted,
      AutoDownloadPolicy.everyone => true,
    };
    if (acceptsAttachment &&
        incoming.attachmentBytes != null &&
        incoming.attachmentType != null) {
      final directory = await getApplicationDocumentsDirectory();
      final attachmentDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}mesh_attachments');
      await attachmentDirectory.create(recursive: true);
      if (!AttachmentPolicy.accepts(
        incoming.attachmentType!,
        incoming.attachmentBytes!,
      )) {
        return;
      }
      final safeName = await AttachmentPolicy.safeStorageName(
        incoming.id,
        incoming.attachmentType!,
      );
      final file =
          File('${attachmentDirectory.path}${Platform.pathSeparator}$safeName');
      await file.writeAsBytes(incoming.attachmentBytes!, flush: true);
      attachmentPath = file.path;
    }
    _messages.add(LocalMessage(
      id: incoming.id,
      author: incoming.author,
      body: incoming.body,
      createdAt: incoming.createdAt,
      conversationId: incoming.conversationId,
      attachmentPath: attachmentPath,
      attachmentType: acceptsAttachment ? incoming.attachmentType : null,
      deliveryState: incoming.isVerified
          ? incoming.hops == 0
              ? 'received - verified direct peer'
              : 'received - verified via ${incoming.hops} relays'
          : 'received - unverified',
    ));
    await _messageStore.save(_messages);
    unawaited(_showIncomingNotification(incoming));
    notifyListeners();
  }

  Future<void> _showIncomingNotification(IncomingMeshMessage incoming) async {
    final level = preferences.notificationLevel;
    if (level == NotificationLevel.none) return;
    // "Important only" narrows alerts to peers whose key you have verified in
    // person. An unverified stranger's message still arrives and is stored — it
    // just does not light up the screen.
    if (level == NotificationLevel.important &&
        !isFriend(incoming.senderFingerprint)) {
      return;
    }
    final preview = incoming.body.trim().isNotEmpty
        ? incoming.body.trim()
        : incoming.attachmentType == 'photo'
            ? 'Sent a photo'
            : 'Sent a voice note';
    try {
      await const MethodChannel('sejilo/notifications').invokeMethod<void>(
        'showIncoming',
        {
          'title': incoming.author,
          'body':
              preferences.notificationPreviews ? preview : 'New nearby message',
          'sound': preferences.notificationSound,
        },
      );
    } on MissingPluginException {
      // Notifications are implemented on Android and Windows only.
    } on PlatformException {
      // Message delivery must not fail because the OS rejected a notification.
    }
  }

  Future<void> togglePin(String messageId) async {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    _messages[index] =
        _messages[index].copyWith(isPinned: !_messages[index].isPinned);
    await _messageStore.save(_messages);
    notifyListeners();
  }

  Future<void> react(String messageId, String emoji) async {
    if (!const {'👍', '❤️', '😂', '😮', '🙏'}.contains(emoji)) return;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    final reactions = Map<String, int>.from(_messages[index].reactions);
    reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    _messages[index] = _messages[index].copyWith(reactions: reactions);
    await _messageStore.save(_messages);
    notifyListeners();
  }

  Future<void> clearLocalMessages() async {
    if (!isReady) return;
    final attachments = [
      for (final message in _messages)
        if (message.attachmentPath != null) message.attachmentPath!,
    ];
    _messages.clear();
    await _messageStore.clear();
    for (final path in attachments) {
      await _deleteAttachmentFile(path);
    }
    notifyListeners();
  }

  Future<void> deleteMessage(String messageId) async {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    final attachmentPath = _messages[index].attachmentPath;
    _messages.removeAt(index);
    await _messageStore.save(_messages);
    if (attachmentPath != null) {
      await _deleteAttachmentFile(attachmentPath);
    }
    notifyListeners();
  }

  /// Removes a stored attachment once no message references it.
  ///
  /// Without this the files stayed on disk forever after their message was
  /// deleted, so "delete" left the photo readable to anyone with the device.
  Future<void> _deleteAttachmentFile(String path) async {
    if (_messages.any((message) => message.attachmentPath == path)) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Locked or already gone; the message record is what the UI reads.
    }
  }

  Future<void> editMessage(String messageId, String body) async {
    final normalized = body.trim();
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0 || normalized.isEmpty || _messages[index].author != 'You') {
      return;
    }
    _messages[index] = _messages[index].copyWith(body: normalized);
    await _messageStore.save(_messages);
    notifyListeners();
  }

  Future<void> setUsername(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 32) return;
    _username = normalized;
    await _storage.write(key: 'profile.username.v1', value: _username);
    _needsOnboarding = false;
    if (_identity != null) await _configureMeshService();
    notifyListeners();
  }

  Future<void> setAvatar(int value) async {
    _avatarIndex = value.clamp(0, 5);
    await _storage.write(key: 'profile.avatar.v1', value: '$_avatarIndex');
    notifyListeners();
  }

  Future<void> _configureMeshService() async {
    await _incomingSubscription?.cancel();
    await _deliverySubscription?.cancel();
    _meshService?.dispose();
    _meshService = BleMeshService(
      identity: _identity!,
      username: _username,
      outboxStore: _outboxStore,
    )
      ..setLocalGroupId(_localityGroupId)
      ..addListener(notifyListeners);
    _incomingSubscription = _meshService!.incoming.listen(_receiveMeshMessage);
    _deliverySubscription =
        _meshService!.deliveryUpdates.listen(_receiveDeliveryUpdate);
    await _meshService!.restorePendingDeliveries();
    if (_shareNearby) await _meshService!.start();
  }

  Future<void> _receiveDeliveryUpdate(MeshDeliveryUpdate update) async {
    final index =
        _messages.indexWhere((message) => message.id == update.messageId);
    if (index < 0) return;
    final label = switch (update.status) {
      MeshDeliveryStatus.queued => 'queued - waiting for a peer',
      MeshDeliveryStatus.sent => 'sent - awaiting acknowledgement',
      MeshDeliveryStatus.delivered => 'delivered - verified acknowledgement',
      MeshDeliveryStatus.failed => 'failed - retry limit reached',
    };
    if (_messages[index].deliveryState == label) return;
    _messages[index] = _messages[index].copyWith(deliveryState: label);
    await _messageStore.save(_messages);
    notifyListeners();
  }

  Future<void> setPresence({required bool enabled, String? locality}) async {
    _shareNearby = enabled;
    final previousLocality = _localityName;
    final normalized = locality?.trim();
    _localityName =
        normalized == null || normalized.isEmpty ? null : normalized;
    await _storage.write(key: 'presence.enabled.v1', value: enabled.toString());
    if (_localityName == null) {
      await _storage.delete(key: 'presence.locality.v1');
    } else {
      await _storage.write(key: 'presence.locality.v1', value: _localityName);
      if (_localityGroupId == null || previousLocality != _localityName) {
        _localityGroupId = _manualGroupId(_localityName!);
        _localityLatitude = null;
        _localityLongitude = null;
        await _storage.delete(key: 'presence.latitude.v1');
        await _storage.delete(key: 'presence.longitude.v1');
      }
      await _storage.write(key: 'presence.group.v1', value: _localityGroupId);
    }
    _meshService?.setLocalGroupId(_localityGroupId);
    if (enabled) {
      await _meshService?.start();
    } else {
      await _meshService?.stop();
    }
    notifyListeners();
  }

  Future<void> restartNearbyMesh() async {
    if (!_shareNearby) return;
    await _meshService?.restart();
    notifyListeners();
  }

  void openPublicChannel() {
    _activeConversationId = null;
    _activeConversationName = null;
    _activeGroupId = null;
    notifyListeners();
  }

  bool openPeerConversation(NearbyMeshPeer peer) {
    final verificationCode = peer.verificationCode;
    if (!peer.isVerified || verificationCode == null) return false;
    _activeConversationId = verificationCode;
    _activeConversationName = peer.username;
    _activeGroupId = null;
    notifyListeners();
    return true;
  }

  void openFriendConversation(FriendProfile friend) {
    _activeConversationId = friend.id;
    _activeConversationName = friend.username;
    _activeGroupId = null;
    notifyListeners();
  }

  bool isFriend(String? verificationCode) =>
      verificationCode != null &&
      _friends.any((friend) => friend.id == verificationCode);

  void openLocalGroup() {
    if (_localityGroupId == null || _localityName == null) return;
    _activeGroupId = _localityGroupId;
    _activeConversationId = 'group:$_localityGroupId';
    _activeConversationName = '$_localityName GC';
    notifyListeners();
  }

  Future<void> useDetectedLocality({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    _localityName = name.trim().isEmpty ? 'Local area' : name.trim();
    _localityLatitude = latitude;
    _localityLongitude = longitude;
    _localityGroupId = 'geo:${_geohash(latitude, longitude)}';
    await _storage.write(key: 'presence.locality.v1', value: _localityName);
    await _storage.write(key: 'presence.group.v1', value: _localityGroupId);
    await _storage.write(
        key: 'presence.latitude.v1', value: latitude.toString());
    await _storage.write(
        key: 'presence.longitude.v1', value: longitude.toString());
    _meshService?.setLocalGroupId(_localityGroupId);
    await setPresence(enabled: true, locality: _localityName);
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _deliverySubscription?.cancel();
    _meshService?.dispose();
    super.dispose();
  }

  Future<bool> addFriend({required String username, required String id}) async {
    final normalizedName = username.trim();
    final enteredId = id.trim();
    final normalizedCode = enteredId.toUpperCase();
    final normalizedId = DeviceIdentity.isValidFingerprint(enteredId)
        ? enteredId
        : nearbyPeers
            .where((peer) => peer.verificationCode != null)
            .where((peer) =>
                DeviceIdentity.verificationCodeForFingerprint(
                        peer.verificationCode!)
                    ?.toUpperCase() ==
                normalizedCode)
            .map((peer) => peer.verificationCode!)
            .firstOrNull;
    if (normalizedName.isEmpty ||
        normalizedId == null ||
        _friends.any((friend) => friend.id == normalizedId)) {
      return false;
    }
    _friends.add(FriendProfile(
        id: normalizedId, username: normalizedName, addedAt: DateTime.now()));
    await _saveFriends();
    notifyListeners();
    return true;
  }

  Future<void> removeFriend(String id) async {
    _friends.removeWhere((friend) => friend.id == id);
    if (_activeConversationId == id) {
      _activeConversationId = null;
      _activeConversationName = null;
    }
    await _saveFriends();
    notifyListeners();
  }

  Future<void> blockPeer(String fingerprint) async {
    if (!DeviceIdentity.isValidFingerprint(fingerprint)) return;
    _blockedPeerIds.add(fingerprint);
    await _saveBlockedPeers();
    notifyListeners();
  }

  Future<void> unblockPeer(String fingerprint) async {
    _blockedPeerIds.remove(fingerprint);
    await _saveBlockedPeers();
    notifyListeners();
  }

  Future<void> _saveBlockedPeers() => _storage.write(
        key: 'blocked_peers.v1',
        value: jsonEncode(_blockedPeerIds.toList(growable: false)),
      );

  Future<void> _saveFriends() => _storage.write(
        key: 'friends.v1',
        value: jsonEncode(_friends.map((friend) => friend.toJson()).toList()),
      );

  String _manualGroupId(String name) {
    final normalized =
        name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final limited =
        normalized.length > 48 ? normalized.substring(0, 48) : normalized;
    return 'name:$limited';
  }

  String _geohash(double latitude, double longitude) {
    const alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0;
    var latMax = 90.0;
    var lonMin = -180.0;
    var lonMax = 180.0;
    var even = true;
    var bit = 0;
    var value = 0;
    final result = StringBuffer();
    while (result.length < 5) {
      if (even) {
        final middle = (lonMin + lonMax) / 2;
        if (longitude >= middle) {
          value = (value << 1) | 1;
          lonMin = middle;
        } else {
          value <<= 1;
          lonMax = middle;
        }
      } else {
        final middle = (latMin + latMax) / 2;
        if (latitude >= middle) {
          value = (value << 1) | 1;
          latMin = middle;
        } else {
          value <<= 1;
          latMax = middle;
        }
      }
      even = !even;
      bit++;
      if (bit == 5) {
        result.write(alphabet[value]);
        bit = 0;
        value = 0;
      }
    }
    return result.toString();
  }
}
