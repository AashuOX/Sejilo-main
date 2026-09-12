import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/device_identity.dart';
import '../security/attachment_policy.dart';
import 'mesh_frames.dart';

enum MeshContentType {
  announce,
  publicMessage,
  acknowledgement,
  directMessage,
  groupMessage,
}

class VerifiedMeshContent {
  VerifiedMeshContent({
    required this.type,
    required this.id,
    required this.senderId,
    required this.author,
    required this.createdAt,
    required this.maxHops,
    required this.publicKey,
    required this.signature,
    this.body,
    this.acknowledges,
    this.recipientId,
    this.groupId,
    this.attachmentType,
    this.attachmentBytes,
    this.kxPublicKey,
    this.neighbors,
    this.encryptedBody = false,
  });

  final MeshContentType type;
  final String id;
  final String senderId;
  final String author;
  final DateTime createdAt;
  final int maxHops;
  final SimplePublicKey publicKey;
  final Uint8List signature;
  final String? body;
  final String? acknowledges;
  final String? recipientId;
  final String? groupId;
  final String? attachmentType;
  final Uint8List? attachmentBytes;

  /// Sender's X25519 public key, carried by announcements and encrypted direct
  /// messages so recipients can derive a shared secret for E2EE.
  final Uint8List? kxPublicKey;

  /// Direct radio neighbors reported by this peer during announcement (up to 10).
  /// Used for distributed mesh topology discovery.
  final List<String>? neighbors;

  /// True when the [body] is an AEAD ciphertext envelope that must be decrypted
  /// with a derived session key before delivery.
  final bool encryptedBody;
}

/// Authenticated application payload carried inside BLE fragments.
///
/// Relay hop count is intentionally outside the signature because relays must
/// mutate it. The signed [VerifiedMeshContent.maxHops] is the immutable upper
/// bound, so a relay cannot extend a packet beyond its origin policy.
class MeshContentCodec {
  MeshContentCodec({Ed25519? signatureAlgorithm})
      : _signatureAlgorithm = signatureAlgorithm ?? Ed25519();

  static const version = 4;

  /// Oldest wire version this codec can decode and verify. Kept at 3 so devices
  /// still accept pre-E2EE packets from older installs; they simply carry no
  /// key-exchange material or encrypted bodies.
  static const oldestCompatibleVersion = 3;

  static const maxAuthorCharacters = 32;
  static const maxBodyBytes = 16 * 1024;
  static const maxAttachmentBytes = AttachmentPolicy.maximumBytes;
  static const maxEncodedBytes = 144 * 1024;
  static const maxIdCharacters = 128;
  static const maxClockSkew = Duration(minutes: 2);

  final Ed25519 _signatureAlgorithm;

  Future<Uint8List> sign({
    required MeshContentType type,
    required String id,
    required String author,
    required DateTime createdAt,
    required int maxHops,
    required DeviceIdentity identity,
    String? body,
    String? acknowledges,
    String? recipientId,
    String? groupId,
    String? attachmentType,
    Uint8List? attachmentBytes,
    Uint8List? kxPublicKey,
    List<String>? neighbors,
    bool encryptedBody = false,
  }) async {
    final normalizedAuthor = author.trim();
    _validateFields(
      type: type,
      id: id,
      senderId: identity.shortId,
      author: normalizedAuthor,
      createdAt: createdAt,
      maxHops: maxHops,
      publicKeyBytes: identity.publicKey.bytes,
      body: body,
      acknowledges: acknowledges,
      recipientId: recipientId,
      groupId: groupId,
      attachmentType: attachmentType,
      attachmentBytes: attachmentBytes,
      kxPublicKey: kxPublicKey,
      neighbors: neighbors,
      encryptedBody: encryptedBody,
    );
    final unsigned = _unsignedMap(
      type: type,
      id: id,
      senderId: identity.shortId,
      author: normalizedAuthor,
      createdAt: createdAt,
      maxHops: maxHops,
      publicKeyBytes: identity.publicKey.bytes,
      body: body,
      acknowledges: acknowledges,
      recipientId: recipientId,
      groupId: groupId,
      attachmentType: attachmentType,
      attachmentBytes: attachmentBytes,
      kxPublicKey: kxPublicKey,
      neighbors: neighbors,
      encryptedBody: encryptedBody,
    );
    final canonical = utf8.encode(jsonEncode(unsigned));
    final signature = await _signatureAlgorithm.sign(
      canonical,
      keyPair: identity.keyPair,
    );
    final encoded = Uint8List.fromList(utf8.encode(jsonEncode({
      ...unsigned,
      'sig': _base64(signature.bytes),
    })));
    if (encoded.length > maxEncodedBytes) {
      throw ArgumentError(
          'The signed mesh payload exceeds $maxEncodedBytes bytes.');
    }
    return encoded;
  }

  Future<VerifiedMeshContent?> decodeAndVerify(
    Uint8List bytes, {
    DateTime? now,
  }) async {
    if (bytes.isEmpty || bytes.length > maxEncodedBytes) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      final versionValue = decoded['v'];
      final typeIndex = decoded['t'];
      final timestamp = decoded['ts'];
      final maxHops = decoded['mh'];
      if ((versionValue != version && versionValue != oldestCompatibleVersion) ||
          typeIndex is! int ||
          typeIndex < 0 ||
          typeIndex >= MeshContentType.values.length ||
          timestamp is! int ||
          maxHops is! int) {
        return null;
      }
      final wireVersion = versionValue as int;
      final type = MeshContentType.values[typeIndex];
      final id = decoded['id'] as String?;
      final senderId = decoded['sid'] as String?;
      final author = decoded['name'] as String?;
      final publicKeyText = decoded['pub'] as String?;
      final signatureText = decoded['sig'] as String?;
      final body = decoded['body'] as String?;
      final acknowledges = decoded['ack'] as String?;
      final recipientId = decoded['to'] as String?;
      final groupId = decoded['group'] as String?;
      final attachmentType = decoded['at'] as String?;
      final attachmentText = decoded['att'] as String?;
      final kxText = decoded['kx'] as String?;
      final encrypted = decoded['enc'] == 1;
      final rawNeighbors = decoded['nbr'];
      final neighbors = rawNeighbors is List
          ? rawNeighbors.whereType<String>().toList()
          : null;
      if (id == null ||
          senderId == null ||
          author == null ||
          publicKeyText == null ||
          signatureText == null) {
        return null;
      }
      final publicKeyBytes = _decodeBase64(publicKeyText);
      final signatureBytes = _decodeBase64(signatureText);
      final attachmentBytes =
          attachmentText == null ? null : _decodeBase64(attachmentText);
      final kxPublicKey = kxText == null ? null : _decodeBase64(kxText);
      if (publicKeyBytes == null || signatureBytes == null) return null;
      if (attachmentText != null && attachmentBytes == null) return null;
      if (kxText != null && kxPublicKey == null) return null;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      );
      _validateFields(
        type: type,
        id: id,
        senderId: senderId,
        author: author,
        createdAt: createdAt,
        maxHops: maxHops,
        publicKeyBytes: publicKeyBytes,
        body: body,
        acknowledges: acknowledges,
        recipientId: recipientId,
        groupId: groupId,
        attachmentType: attachmentType,
        attachmentBytes: attachmentBytes,
        kxPublicKey: kxPublicKey,
        neighbors: neighbors,
        encryptedBody: encrypted,
      );
      final timestampNow = (now ?? DateTime.now()).toUtc();
      if (createdAt.isAfter(timestampNow.add(maxClockSkew))) return null;
      if (DeviceIdentity.shortIdForPublicKey(publicKeyBytes) != senderId) {
        return null;
      }
      final unsigned = _unsignedMap(
        type: type,
        id: id,
        senderId: senderId,
        author: author,
        createdAt: createdAt,
        maxHops: maxHops,
        publicKeyBytes: publicKeyBytes,
        body: body,
        acknowledges: acknowledges,
        recipientId: recipientId,
        groupId: groupId,
        attachmentType: attachmentType,
        attachmentBytes: attachmentBytes,
        kxPublicKey: kxPublicKey,
        neighbors: neighbors,
        encryptedBody: encrypted,
        wireVersion: wireVersion,
      );
      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      final verified = await _signatureAlgorithm.verify(
        utf8.encode(jsonEncode(unsigned)),
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
      if (!verified) return null;
      return VerifiedMeshContent(
        type: type,
        id: id,
        senderId: senderId,
        author: author,
        createdAt: createdAt,
        maxHops: maxHops,
        publicKey: publicKey,
        signature: Uint8List.fromList(signatureBytes),
        body: body,
        acknowledges: acknowledges,
        recipientId: recipientId,
        groupId: groupId,
        attachmentType: attachmentType,
        attachmentBytes: attachmentBytes,
        kxPublicKey: kxPublicKey,
        neighbors: neighbors,
        encryptedBody: encrypted,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on StateError {
      return null;
    }
  }

  Map<String, dynamic> _unsignedMap({
    required MeshContentType type,
    required String id,
    required String senderId,
    required String author,
    required DateTime createdAt,
    required int maxHops,
    required List<int> publicKeyBytes,
    String? body,
    String? acknowledges,
    String? recipientId,
    String? groupId,
    String? attachmentType,
    Uint8List? attachmentBytes,
    Uint8List? kxPublicKey,
    List<String>? neighbors,
    bool encryptedBody = false,
    int wireVersion = version,
  }) {
    return <String, dynamic>{
      'v': wireVersion,
      't': type.index,
      'id': id,
      'sid': senderId,
      'name': author,
      'ts': createdAt.toUtc().millisecondsSinceEpoch,
      'mh': maxHops,
      'pub': _base64(publicKeyBytes),
      if (body != null) 'body': body,
      if (acknowledges != null) 'ack': acknowledges,
      if (recipientId != null) 'to': recipientId,
      if (groupId != null) 'group': groupId,
      if (attachmentType != null) 'at': attachmentType,
      if (attachmentBytes != null) 'att': _base64(attachmentBytes),
      if (kxPublicKey != null) 'kx': _base64(kxPublicKey),
      if (neighbors != null && neighbors.isNotEmpty) 'nbr': neighbors,
      if (encryptedBody) 'enc': 1,
    };
  }

  void _validateFields({
    required MeshContentType type,
    required String id,
    required String senderId,
    required String author,
    required DateTime createdAt,
    required int maxHops,
    required List<int> publicKeyBytes,
    String? body,
    String? acknowledges,
    String? recipientId,
    String? groupId,
    String? attachmentType,
    Uint8List? attachmentBytes,
    Uint8List? kxPublicKey,
    List<String>? neighbors,
    bool encryptedBody = false,
  }) {
    if (id.isEmpty || id.length > maxIdCharacters) {
      throw ArgumentError('Invalid mesh message ID.');
    }
    if (senderId.isEmpty || senderId.length > 32) {
      throw ArgumentError('Invalid mesh sender ID.');
    }
    if (author.isEmpty || author.length > maxAuthorCharacters) {
      throw ArgumentError('Invalid mesh author.');
    }
    if (createdAt.millisecondsSinceEpoch <= 0 || maxHops < 0 || maxHops > 7) {
      throw ArgumentError('Invalid mesh time or hop limit.');
    }
    if (publicKeyBytes.length != 32) {
      throw ArgumentError('Invalid Ed25519 public key.');
    }
    if (kxPublicKey != null && kxPublicKey.length != 32) {
      throw ArgumentError('Invalid X25519 key-exchange key.');
    }
    final bodyLength = body == null ? 0 : utf8.encode(body).length;
    if (bodyLength > maxBodyBytes) {
      throw ArgumentError('Mesh message body is too large.');
    }
    final hasAttachment = attachmentType != null || attachmentBytes != null;
    if (hasAttachment &&
        (attachmentType == null ||
            attachmentBytes == null ||
            !AttachmentPolicy.accepts(attachmentType, attachmentBytes))) {
      throw ArgumentError('Invalid or oversized mesh attachment.');
    }
    final hasMessageContent =
        (body != null && body.trim().isNotEmpty) || hasAttachment;
    if (neighbors != null) {
      if (type != MeshContentType.announce) {
        throw ArgumentError('Neighbor gossip is only permitted in announcements.');
      }
      if (neighbors.length > 10) {
        throw ArgumentError('An announcement can carry at most 10 neighbors.');
      }
      for (final n in neighbors) {
        if (n.isEmpty || n.length > 32) {
          throw ArgumentError('Invalid neighbor ID in announcement.');
        }
      }
    }
    switch (type) {
      case MeshContentType.announce:
        if (body != null ||
            acknowledges != null ||
            recipientId != null ||
            groupId != null ||
            hasAttachment ||
            encryptedBody) {
          throw ArgumentError('An announcement cannot contain message data.');
        }
        break;
      case MeshContentType.publicMessage:
        if (!hasMessageContent ||
            acknowledges != null ||
            recipientId != null ||
            groupId != null ||
            kxPublicKey != null ||
            encryptedBody) {
          throw ArgumentError('Invalid public message.');
        }
        break;
      case MeshContentType.acknowledgement:
        if (body != null ||
            recipientId != null ||
            groupId != null ||
            hasAttachment ||
            kxPublicKey != null ||
            encryptedBody ||
            acknowledges == null ||
            acknowledges.isEmpty ||
            acknowledges.length > maxIdCharacters) {
          throw ArgumentError('An acknowledgement must reference one message.');
        }
        break;
      case MeshContentType.directMessage:
        if (!hasMessageContent ||
            acknowledges != null ||
            recipientId == null ||
            !DeviceIdentity.isValidFingerprint(recipientId) ||
            groupId != null) {
          throw ArgumentError(
              'A direct message requires a body and recipient fingerprint.');
        }
        if (encryptedBody && kxPublicKey == null) {
          throw ArgumentError(
              'An encrypted direct message must carry a key-exchange key.');
        }
        break;
      case MeshContentType.groupMessage:
        if (!hasMessageContent ||
            acknowledges != null ||
            recipientId != null ||
            groupId == null ||
            groupId.isEmpty ||
            groupId.length > 64) {
          throw ArgumentError('Invalid locality group message.');
        }
        break;
    }
  }

  String _base64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  Uint8List? _decodeBase64(String value) {
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
    } on FormatException {
      return null;
    }
  }
}

class DecodedMeshFrame {
  const DecodedMeshFrame({required this.frame, required this.hopsTravelled});

  final MeshFrame frame;
  final int hopsTravelled;
}

/// Compact framing around [MeshFrame]. The 16-byte header leaves room for a
/// useful payload even on conservative negotiated BLE MTUs.
class MeshWireFrameCodec {
  const MeshWireFrameCodec();

  static const version = 2;
  static const headerBytes = 16;
  static const maxFrameBytes = 180;
  static const maxFragmentPayloadBytes = maxFrameBytes - headerBytes;
  static const _magic0 = 0x53; // S
  static const _magic1 = 0x4A; // J

  Uint8List encode(MeshFrame frame, {required int hopsTravelled}) {
    if (!frame.isValid ||
        hopsTravelled < 0 ||
        hopsTravelled > 7 ||
        frame.payload.length > maxFragmentPayloadBytes ||
        frame.fragmentCount > 1024) {
      throw ArgumentError('Invalid Sejilo BLE frame.');
    }
    final transferId = _decodeTransferId(frame.messageId);
    if (transferId == null) {
      throw ArgumentError('A transfer ID must be exactly 8 bytes.');
    }
    final output = Uint8List(headerBytes + frame.payload.length);
    final data = ByteData.sublistView(output);
    output[0] = _magic0;
    output[1] = _magic1;
    output[2] = version;
    output[3] = hopsTravelled;
    output.setRange(4, 12, transferId);
    data.setUint16(12, frame.fragmentIndex, Endian.big);
    data.setUint16(14, frame.fragmentCount, Endian.big);
    output.setRange(headerBytes, output.length, frame.payload);
    return output;
  }

  DecodedMeshFrame? decode(Uint8List bytes) {
    if (bytes.length <= headerBytes ||
        bytes.length > maxFrameBytes ||
        bytes[0] != _magic0 ||
        bytes[1] != _magic1 ||
        bytes[2] != version ||
        bytes[3] > 7) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final index = data.getUint16(12, Endian.big);
    final count = data.getUint16(14, Endian.big);
    if (count == 0 || count > 1024 || index >= count) return null;
    final transferId = _base64(bytes.sublist(4, 12));
    final frame = MeshFrame(
      messageId: transferId,
      fragmentIndex: index,
      fragmentCount: count,
      payload: Uint8List.sublistView(bytes, headerBytes),
    );
    return DecodedMeshFrame(frame: frame, hopsTravelled: bytes[3]);
  }

  String transferIdForDigest(List<int> digest) {
    if (digest.length < 8) throw ArgumentError('Digest is too short.');
    return _base64(digest.take(8).toList(growable: false));
  }

  Uint8List? _decodeTransferId(String value) {
    try {
      final decoded = base64Url.decode(base64Url.normalize(value));
      return decoded.length == 8 ? Uint8List.fromList(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  String _base64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
