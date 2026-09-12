import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.publicKey,
    required this.keyPair,
    required this.x25519PublicKey,
    required this.x25519KeyPair,
  });

  /// Ed25519 identity key — authenticates and pins the peer identity.
  final SimplePublicKey publicKey;
  final SimpleKeyPairData keyPair;

  /// X25519 key-exchange key — enables encrypted direct messages via
  /// static ECDH. Bound to the Ed25519 identity because it is carried inside
  /// signed packets and announcements.
  final SimplePublicKey x25519PublicKey;
  final SimpleKeyPairData x25519KeyPair;

  /// Minimal identity used by unit tests that only exercise signing.
  factory DeviceIdentity.ed25519Only({required SimplePublicKey publicKey, required SimpleKeyPairData keyPair}) {
    return DeviceIdentity(
      publicKey: publicKey,
      keyPair: keyPair,
      x25519PublicKey: SimplePublicKey(
        Uint8List(32),
        type: KeyPairType.x25519,
      ),
      x25519KeyPair: SimpleKeyPairData(
        Uint8List(32),
        publicKey: SimplePublicKey(Uint8List(32), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      ),
    );
  }

  String get fingerprint =>
      base64Url.encode(publicKey.bytes).replaceAll('=', '');

  String get verificationCode => verificationCodeForPublicKey(publicKey.bytes);

  /// Human-friendly locator only. Security verification must still compare the
  /// full fingerprint encoded in the contact QR.
  String get shortId => shortIdForPublicKey(publicKey.bytes);

  static bool isValidFingerprint(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value.trim())).length == 32;
    } on FormatException {
      return false;
    }
  }

  static String shortIdForPublicKey(List<int> publicKeyBytes) {
    if (publicKeyBytes.length != 32) {
      throw ArgumentError.value(
        publicKeyBytes.length,
        'publicKeyBytes',
        'An Ed25519 public key must contain 32 bytes.',
      );
    }
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var value = 0;
    for (final byte in publicKeyBytes.take(5)) {
      value = (value << 8) | byte;
    }
    final output = StringBuffer();
    for (var index = 0; index < 8; index++) {
      output.write(alphabet[value & 31]);
      value >>= 5;
    }
    final code = output.toString().split('').reversed.join();
    return '${code.substring(0, 4)}-${code.substring(4)}';
  }

  /// Short code for comparing two already-discovered identities. The full
  /// public key remains the actual stored identity and is carried in QR links.
  static String verificationCodeForPublicKey(List<int> publicKeyBytes) {
    final shortId = shortIdForPublicKey(publicKeyBytes);
    var checksum = 0x1D0F;
    for (final byte in publicKeyBytes) {
      checksum ^= byte << 8;
      for (var bit = 0; bit < 8; bit++) {
        checksum = (checksum & 0x8000) != 0
            ? ((checksum << 1) ^ 0x1021) & 0xFFFF
            : (checksum << 1) & 0xFFFF;
      }
    }
    return 'SJ-$shortId-${(checksum % 1000).toString().padLeft(3, '0')}';
  }

  static String? verificationCodeForFingerprint(String fingerprint) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(fingerprint.trim()));
      if (bytes.length != 32) return null;
      return verificationCodeForPublicKey(bytes);
    } on FormatException {
      return null;
    }
  }
}

class DeviceIdentityStore {
  DeviceIdentityStore(this._storage);

  static const _privateKeyName = 'identity.ed25519.private.v1';
  static const _publicKeyName = 'identity.ed25519.public.v1';
  static const _x25519PrivateKeyName = 'identity.x25519.private.v1';
  static const _x25519PublicKeyName = 'identity.x25519.public.v1';

  final FlutterSecureStorage _storage;
  final Ed25519 _algorithm = Ed25519();
  final X25519 _x25519 = X25519();

  Future<DeviceIdentity> loadOrCreate() async {
    final privateKey = await _storage.read(key: _privateKeyName);
    final publicKey = await _storage.read(key: _publicKeyName);
    final x25519PrivateKey = await _storage.read(key: _x25519PrivateKeyName);
    final x25519PublicKey = await _storage.read(key: _x25519PublicKeyName);

    if (privateKey != null &&
        publicKey != null &&
        x25519PrivateKey != null &&
        x25519PublicKey != null) {
      final publicKeyBytes = base64Url.decode(publicKey);
      final x25519PubBytes = base64Url.decode(x25519PublicKey);
      return DeviceIdentity(
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        keyPair: SimpleKeyPairData(
          base64Url.decode(privateKey),
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
          type: KeyPairType.ed25519,
        ),
        x25519PublicKey:
            SimplePublicKey(x25519PubBytes, type: KeyPairType.x25519),
        x25519KeyPair: SimpleKeyPairData(
          base64Url.decode(x25519PrivateKey),
          publicKey: SimplePublicKey(x25519PubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        ),
      );
    }

    final keyPair = await _algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final privateKeyBytes = await keyPairData.extractPrivateKeyBytes();
    final generatedPublicKey = await keyPairData.extractPublicKey();

    final x25519KeyPair = await _x25519.newKeyPair();
    final x25519KeyPairData = await x25519KeyPair.extract();
    final x25519PrivateBytes = await x25519KeyPairData.extractPrivateKeyBytes();
    final x25519GeneratedPublic = await x25519KeyPairData.extractPublicKey();

    await _storage.write(
        key: _privateKeyName, value: base64Url.encode(privateKeyBytes));
    await _storage.write(
        key: _publicKeyName, value: base64Url.encode(generatedPublicKey.bytes));
    await _storage.write(
        key: _x25519PrivateKeyName, value: base64Url.encode(x25519PrivateBytes));
    await _storage.write(
        key: _x25519PublicKeyName,
        value: base64Url.encode(x25519GeneratedPublic.bytes));

    return DeviceIdentity(
      publicKey: SimplePublicKey(Uint8List.fromList(generatedPublicKey.bytes),
          type: KeyPairType.ed25519),
      keyPair: SimpleKeyPairData(
        privateKeyBytes,
        publicKey: SimplePublicKey(Uint8List.fromList(generatedPublicKey.bytes),
            type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      ),
      x25519PublicKey:
          SimplePublicKey(Uint8List.fromList(x25519GeneratedPublic.bytes),
              type: KeyPairType.x25519),
      x25519KeyPair: SimpleKeyPairData(
        x25519PrivateBytes,
        publicKey: SimplePublicKey(Uint8List.fromList(x25519GeneratedPublic.bytes),
            type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      ),
    );
  }
}
