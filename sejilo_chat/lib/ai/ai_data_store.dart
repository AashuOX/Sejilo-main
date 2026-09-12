import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Private derived AI data. The platform secure-storage backend protects this
/// small index; no conversation content is sent to a server by this class.
class AiPrivateDataStore {
  AiPrivateDataStore(this._storage);

  static const _recordsKey = 'ai.private.records.v1';
  static const maximumRecords = 100;
  final FlutterSecureStorage _storage;

  Future<Map<String, String>> load() async {
    final raw = await _storage.read(key: _recordsKey);
    if (raw == null) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded.length > maximumRecords) {
      throw const FormatException('Invalid AI private data.');
    }
    return decoded.map((key, value) {
      if (key.length > 128 || value is! String || value.length > 4096) {
        throw const FormatException('Invalid AI private record.');
      }
      return MapEntry(key, value);
    });
  }

  Future<void> save(Map<String, String> records) async {
    if (records.length > maximumRecords ||
        records.entries.any(
            (entry) => entry.key.length > 128 || entry.value.length > 4096)) {
      throw ArgumentError('AI private data exceeds its local quota.');
    }
    await _storage.write(key: _recordsKey, value: jsonEncode(records));
  }

  Future<void> deleteConversation(String conversationId) async {
    final records = Map<String, String>.from(await load())
      ..removeWhere((key, _) => key.startsWith('$conversationId:'));
    await save(records);
  }

  Future<void> clearAll() => _storage.delete(key: _recordsKey);
}
