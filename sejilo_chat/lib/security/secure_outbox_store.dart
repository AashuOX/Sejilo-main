import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PersistedOutboxItem {
  const PersistedOutboxItem({
    required this.messageId,
    required this.signedPayload,
    required this.createdAt,
    required this.nextAttemptAt,
    required this.attempts,
    this.expectedAcknowledgementFrom,
  });

  final String messageId;
  final Uint8List signedPayload;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
  final int attempts;
  final String? expectedAcknowledgementFrom;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': messageId,
        'payload': base64Url.encode(signedPayload),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'expectedAcknowledgementFrom': expectedAcknowledgementFrom,
      };

  factory PersistedOutboxItem.fromJson(Map<String, dynamic> json) {
    final messageId = json['id'] as String;
    final payload =
        base64Url.decode(base64Url.normalize(json['payload'] as String));
    final attempts = json['attempts'] as int;
    if (messageId.isEmpty || payload.isEmpty || attempts < 0) {
      throw const FormatException('Invalid persisted outbox item.');
    }
    return PersistedOutboxItem(
      messageId: messageId,
      signedPayload: Uint8List.fromList(payload),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      nextAttemptAt: DateTime.parse(json['nextAttemptAt'] as String).toUtc(),
      attempts: attempts,
      expectedAcknowledgementFrom:
          json['expectedAcknowledgementFrom'] as String?,
    );
  }
}

/// Encrypts the bounded transport outbox independently from chat history.
/// The ciphertext is retained only on this device and is safe to retry after
/// an application restart without rebuilding a message or changing its ID.
class SecureOutboxStore {
  SecureOutboxStore(this._storage);

  static const _keyName = 'outbox.key.v1';
  static const _outboxName = 'outbox.records.v1';

  final FlutterSecureStorage _storage;
  final Cipher _cipher = Chacha20.poly1305Aead();

  Future<List<PersistedOutboxItem>> load() async {
    final encrypted = await _storage.read(key: _outboxName);
    if (encrypted == null) return const <PersistedOutboxItem>[];
    final secretBox = _secretBoxFromJson(encrypted);
    final clearText =
        await _cipher.decrypt(secretBox, secretKey: await _loadKey());
    final records = jsonDecode(utf8.decode(clearText)) as List<dynamic>;
    return records
        .map((record) => PersistedOutboxItem.fromJson(
              Map<String, dynamic>.from(record as Map<dynamic, dynamic>),
            ))
        .toList(growable: false);
  }

  Future<void> save(Iterable<PersistedOutboxItem> items) async {
    final clearText =
        utf8.encode(jsonEncode(items.map((item) => item.toJson()).toList()));
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: await _loadKey(),
      nonce: _newNonce(),
    );
    await _storage.write(
      key: _outboxName,
      value: jsonEncode(<String, String>{
        'cipherText': base64Url.encode(secretBox.cipherText),
        'nonce': base64Url.encode(secretBox.nonce),
        'mac': base64Url.encode(secretBox.mac.bytes),
      }),
    );
  }

  Future<void> clear() => _storage.delete(key: _outboxName);

  Future<SecretKey> _loadKey() async {
    final storedKey = await _storage.read(key: _keyName);
    if (storedKey != null) return SecretKey(base64Url.decode(storedKey));
    final generatedKey = await _cipher.newSecretKey();
    final bytes = await generatedKey.extractBytes();
    await _storage.write(key: _keyName, value: base64Url.encode(bytes));
    return generatedKey;
  }

  SecretBox _secretBoxFromJson(String encrypted) {
    final json = jsonDecode(encrypted) as Map<String, dynamic>;
    return SecretBox(
      base64Url.decode(json['cipherText'] as String),
      nonce: base64Url.decode(json['nonce'] as String),
      mac: Mac(base64Url.decode(json['mac'] as String)),
    );
  }

  Uint8List _newNonce() => Uint8List.fromList(
        List<int>.generate(12, (_) => Random.secure().nextInt(256)),
      );
}
