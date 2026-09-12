import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/mesh_client.dart';

class SecureMessageStore {
  SecureMessageStore(this._storage);

  static const _keyName = 'messages.key.v1';
  static const _messagesName = 'messages.log.v1';

  final FlutterSecureStorage _storage;
  final Cipher _cipher = Chacha20.poly1305Aead();

  Future<List<LocalMessage>> load() async {
    final encryptedMessages = await _storage.read(key: _messagesName);
    if (encryptedMessages == null) return const [];
    final secretKey = await _loadKey();
    final encoded = jsonDecode(encryptedMessages) as Map<String, dynamic>;
    final secretBox = SecretBox(
      base64Url.decode(encoded['cipherText'] as String),
      nonce: base64Url.decode(encoded['nonce'] as String),
      mac: Mac(base64Url.decode(encoded['mac'] as String)),
    );
    final clearText = await _cipher.decrypt(secretBox, secretKey: secretKey);
    final records = jsonDecode(utf8.decode(clearText)) as List<dynamic>;
    return records
        .map((record) => LocalMessage.fromJson(record as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<LocalMessage> messages) async {
    final secretKey = await _loadKey();
    final clearText = utf8.encode(
        jsonEncode(messages.map((message) => message.toJson()).toList()));
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final secretBox =
        await _cipher.encrypt(clearText, secretKey: secretKey, nonce: nonce);
    await _storage.write(
      key: _messagesName,
      value: jsonEncode({
        'cipherText': base64Url.encode(secretBox.cipherText),
        'nonce': base64Url.encode(secretBox.nonce),
        'mac': base64Url.encode(secretBox.mac.bytes),
      }),
    );
  }

  Future<void> clear() => _storage.delete(key: _messagesName);

  Future<SecretKey> _loadKey() async {
    final storedKey = await _storage.read(key: _keyName);
    if (storedKey != null) return SecretKey(base64Url.decode(storedKey));
    final generatedKey = await _cipher.newSecretKey();
    final bytes = await generatedKey.extractBytes();
    await _storage.write(key: _keyName, value: base64Url.encode(bytes));
    return generatedKey;
  }
}
