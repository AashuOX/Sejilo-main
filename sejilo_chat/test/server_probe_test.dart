import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';

/// Answers `/health` and `/health/ready` with the given statuses and records
/// which paths were asked for.
http.Client _server({
  required int health,
  required int ready,
  List<String>? seen,
}) =>
    MockClient((request) async {
      seen?.add(request.url.path);
      return switch (request.url.path) {
        '/health' => http.Response('{"status":"ok"}', health,
            headers: {'content-type': 'application/json'}),
        '/health/ready' => http.Response('{"status":"degraded"}', ready,
            headers: {'content-type': 'application/json'}),
        _ => http.Response('Not Found', 404),
      };
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('probeServer', () {
    test('a hostname with no service deployed is not "OK"', () async {
      // What Render's edge really answers for a blueprint that was never
      // applied: 404, text/plain, `x-render-routing: no-server`. The old probe
      // accepted anything under 500 — and then fell back to `/`, which is a 404
      // on a healthy server too — so this exact case displayed "Server OK".
      final auth = AccountAuthController(
        client: MockClient((_) async => http.Response('Not Found', 404,
            headers: {'x-render-routing': 'no-server'})),
      );
      addTearDown(auth.dispose);

      final probe = await auth.probeServer();

      expect(probe.reachable, isFalse);
      expect(probe.isReady, isFalse);
      expect(probe.detail, contains('404'));
      expect(await auth.testServerConnection(), isNull);
    });

    test('a server whose database is missing is up but not ready', () async {
      // The state a fresh deploy sits in until DATABASE_URL is set: /health is
      // served by the process alone, /health/ready runs SELECT 1 and 503s.
      final seen = <String>[];
      final auth = AccountAuthController(
        client: _server(health: 200, ready: 503, seen: seen),
      );
      addTearDown(auth.dispose);

      final probe = await auth.probeServer();

      expect(probe.reachable, isTrue);
      expect(probe.databaseReady, isFalse);
      expect(probe.isReady, isFalse,
          reason: 'No account can be created without a database, so this must '
              'not read as a working server.');
      expect(probe.detail, contains('database'));
      expect(seen, containsAllInOrder(['/health', '/health/ready']));
    });

    test('both checks passing is the only green state', () async {
      final auth = AccountAuthController(
        client: _server(health: 200, ready: 200),
      );
      addTearDown(auth.dispose);

      final probe = await auth.probeServer();

      expect(probe.isReady, isTrue);
      expect(probe.latencyMs, isNotNull);
      expect(await auth.testServerConnection(), isNotNull);
    });

    test('a refused connection reports unreachable rather than throwing',
        () async {
      final auth = AccountAuthController(
        client: MockClient(
            (_) async => throw http.ClientException('Connection refused')),
      );
      addTearDown(auth.dispose);

      final probe = await auth.probeServer();

      expect(probe.reachable, isFalse);
      expect(probe.latencyMs, isNull);
      expect(probe.detail, equals('Server unreachable'));
    });
  });
}
