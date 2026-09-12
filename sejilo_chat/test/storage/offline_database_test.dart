import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sejilo_chat/storage/offline_database.dart';

String _tempPath() {
  final dir = Directory.systemTemp;
  final name = 'sejilo_test_${DateTime.now().microsecondsSinceEpoch}_'
      '${_counter++}.json';
  return '${dir.path}/$name';
}

int _counter = 0;

void main() {
  group('OfflineDatabase (offline-first storage)', () {
    late String path;

    setUp(() {
      path = _tempPath();
    });

    tearDown(() {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      final tmp = File('$path.tmp');
      if (tmp.existsSync()) tmp.deleteSync();
    });

    test('initialize sets isInitialized flag', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      expect(db.isInitialized, equals(true));
    });

    test('insert then get round-trips a record', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('messages', 'm1', {
        'text': 'hello',
        'ts': 123,
      });
      final got = await db.get('messages', 'm1');
      expect(got, isNotNull);
      expect(got!['text'], 'hello');
      expect(got['ts'], 123);
    });

    test('insert is reflected on disk (crash-resilient persistence)', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('conversations', 'c1', {'title': 'trip'});

      // Read the raw file directly — simulates a crash + cold restart.
      final raw = File(path).readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['conversations']['c1']['title'], 'trip');
    });

    test('data survives a full re-instantiation from disk', () async {
      final db1 = OfflineDatabase(customPath: path);
      await db1.initialize();
      await db1.insert('messages', 'm1', {'text': 'persist me'});
      await db1.insert('metadata', 'user', {'id': 'u1'});

      final db2 = OfflineDatabase(customPath: path);
      await db2.initialize();
      final msg = await db2.get('messages', 'm1');
      final meta = await db2.get('metadata', 'user');
      expect(msg?['text'], 'persist me');
      expect(meta?['id'], 'u1');
    });

    test('query filters with where and orders with orderBy', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('messages', 'a', {'ts': 3});
      await db.insert('messages', 'b', {'ts': 1});
      await db.insert('messages', 'c', {'ts': 2});

      final all = await db.query('messages');
      expect(all.length, 3);

      final ordered = await db.query('messages',
          orderBy: (x, y) => (x['ts'] as int).compareTo(y['ts'] as int));
      expect(ordered.map((m) => m['ts']).toList(), [1, 2, 3]);

      final filtered = await db.query('messages',
          where: (m) => (m['ts'] as int) > 1);
      expect(filtered.length, 2);
    });

    test('update merges fields without dropping others', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('messages', 'm1', {'text': 'old', 'seen': false});
      await db.update('messages', 'm1', {'seen': true});
      final got = await db.get('messages', 'm1');
      expect(got?['text'], 'old'); // preserved
      expect(got?['seen'], true); // merged
    });

    test('delete removes a record', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('messages', 'm1', {'text': 'x'});
      await db.delete('messages', 'm1');
      expect(await db.get('messages', 'm1'), isNull);
    });

    test('clearTable and clearAll reset state', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('messages', 'm1', {'text': 'x'});
      await db.insert('conversations', 'c1', {'title': 'y'});

      await db.clearTable('messages');
      expect(await db.get('messages', 'm1'), isNull);
      expect(await db.get('conversations', 'c1'), isNotNull);

      await db.clearAll();
      expect(await db.get('conversations', 'c1'), isNull);
    });

    test('supports dynamic (non-predefined) tables', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      await db.insert('drafts', 'd1', {'body': 'wip'});
      expect(await db.get('drafts', 'd1'), isNotNull);
    });

    test('get returns null for unknown table or id', () async {
      final db = OfflineDatabase(customPath: path);
      await db.initialize();
      expect(await db.get('nope', 'x'), isNull);
      await db.insert('messages', 'm1', {'t': 1});
      expect(await db.get('messages', 'missing'), isNull);
    });
  });
}
