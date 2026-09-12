import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';

/// The backend runs on a free instance that is stopped after 15 minutes without
/// traffic and takes roughly a minute to start again. Every request in this file
/// simulates that by timing out once and then answering — which is exactly what
/// the first sign-in of the day looks like.
http.Client _wakesOnSecondTry(
  http.Response Function(http.BaseRequest request) answer, {
  required List<String> attempts,
}) =>
    MockClient((request) async {
      attempts.add('${request.method} ${request.url.path}');
      if (attempts.length == 1) {
        throw TimeoutException('deadline elapsed');
      }
      return answer(request);
    });

String _loginBody() => jsonEncode({
      'token': 'jwt-token',
      'refreshToken': 'refresh-token',
      'profile': {
        'id': 'usr_1',
        'email': 'a@b.com',
        'username': 'aashu',
        'displayName': 'Aashu',
        'bio': '',
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('cold start', () {
    test('a sign-in that outlives the first deadline still succeeds', () async {
      // Before this, the 15-second deadline in _request was shorter than the
      // host's wake-up, so the very first sign-in after an idle period failed
      // and read to the user as a broken server or wrong password.
      final attempts = <String>[];
      final auth = AccountAuthController(
        client: _wakesOnSecondTry(
          (_) => http.Response(_loginBody(), 200,
              headers: {'content-type': 'application/json'}),
          attempts: attempts,
        ),
      );
      addTearDown(auth.dispose);

      await auth.login(email: 'a@b.com', password: 'correct-horse');

      expect(auth.profile?.username, equals('aashu'));
      expect(attempts, hasLength(2),
          reason: 'The timed-out attempt must be retried exactly once, not '
              'abandoned and not looped.');
      expect(attempts.last, equals('POST /v1/auth/password/login'));
    });

    test('a probe waits out the wake-up instead of reporting unreachable',
        () async {
      final attempts = <String>[];
      final auth = AccountAuthController(
        client: _wakesOnSecondTry(
          (request) => http.Response('{"status":"ok"}', 200,
              headers: {'content-type': 'application/json'}),
          attempts: attempts,
        ),
      );
      addTearDown(auth.dispose);

      final probe = await auth.probeServer();

      expect(probe.isReady, isTrue,
          reason: 'A host that is merely starting up is not a host that is '
              'missing, and the chip must not say it is.');
      expect(attempts, containsAllInOrder(['GET /health', 'GET /health']));
    });

    test('only requests that are safe to repeat are retried', () {
      // A timeout means the response was lost, not that the request was: a
      // retry may well be the second time the server sees it.
      expect(AccountAuthController.isColdStartRetryable('GET', '/v1/posts'),
          isTrue);
      expect(
          AccountAuthController.isColdStartRetryable(
              'POST', '/v1/auth/password/login'),
          isTrue);
      expect(AccountAuthController.isColdStartRetryable('POST', '/v1/auth/google'),
          isTrue);

      expect(AccountAuthController.isColdStartRetryable('POST', '/v1/users'),
          isFalse,
          reason: 'Repeating a signup answers 409 for an account that was in '
              'fact created.');
      expect(
          AccountAuthController.isColdStartRetryable(
              'POST', '/v1/auth/phone/otp-requests'),
          isFalse,
          reason: 'Repeating this sends a second SMS.');
      expect(
          AccountAuthController.isColdStartRetryable(
              'POST', '/v1/auth/phone/verify'),
          isFalse,
          reason: 'A code consumed by the first attempt is invalid on the '
              'second, turning a success into "wrong code".');
      expect(
          AccountAuthController.isColdStartRetryable('POST', '/v1/posts'),
          isFalse,
          reason: 'Repeating this posts twice.');
    });
  });
}
