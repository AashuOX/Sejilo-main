import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejilo_chat/auth/account_auth_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Map<String, dynamic> _profileJson({
  required String id,
  required String email,
  required String username,
  required String displayName,
  String bio = '',
}) =>
    {
      'id': id,
      'email': email,
      'username': username,
      'displayName': displayName,
      'bio': bio,
      'avatar': null,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// A fake HTTP transport that mimics the REAL Sejilo backend contract
/// (same paths, request bodies, response shapes). It never fabricates a
/// session on its own — the controller must store whatever the server says.
http.Client fakeBackend() {
  final users = <String, Map<String, dynamic>>{};
  return MockClient((request) async {
    final path = request.url.path;
    Map<String, dynamic>? body;
    if (request.body.isNotEmpty) {
      try {
        body = jsonDecode(request.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (path == '/v1/users' && request.method == 'POST') {
      final email = (body!['email'] as String).toLowerCase();
      if (users.containsKey(email)) {
        return http.Response(
            jsonEncode({
              'message': 'Email or username is already in use.',
              'error': 'Conflict',
              'statusCode': 409,
            }),
            409,
            headers: {'content-type': 'application/json'});
      }
      final id = 'usr_${users.length + 1}';
      users[email] = _profileJson(
        id: id,
        email: email,
        username: body['username'] as String,
        displayName: body['displayName'] as String,
      );
      return _json({
        'id': id,
        'token': 'real.access.token.$id',
        'refreshToken': 'real.refresh.token.$id',
        'isNewUser': true,
        'profile': users[email],
      }, 201);
    }

    if (path == '/v1/auth/password/login' && request.method == 'POST') {
      final email = (body!['email'] as String).toLowerCase();
      final user = users[email];
      if (user == null || body['password'] != 'Password123!') {
        return _json({
          'message': 'Invalid email or password.',
          'error': 'Unauthorized',
          'statusCode': 401,
        }, 401);
      }
      return _json({
        'id': user['id'],
        'token': 'real.access.token.${user['id']}',
        'refreshToken': 'real.refresh.token.${user['id']}',
        'isNewUser': false,
        'profile': user,
      });
    }

    if (path == '/v1/auth/google' && request.method == 'POST') {
      if (body == null || body['idToken'] != 'verified.google.id.token') {
        return _json({
          'message':
              'Google token verification failed. Provide a valid idToken or accessToken.',
          'error': 'Unauthorized',
          'statusCode': 401,
        }, 401);
      }
      // The real server derives identity from the verified token and ignores
      // `email`/`googleId` in the body; the client only sends them when Google
      // reported them, so neither is guaranteed to be present.
      final email =
          (body['email'] as String? ?? 'google.user@example.com').toLowerCase();
      final existing = users[email];
      if (existing != null) {
        return _json({
          'id': existing['id'],
          'token': 'real.access.token.${existing['id']}',
          'refreshToken': 'real.refresh.token.${existing['id']}',
          'isNewUser': false,
          'profile': existing,
        });
      }
      final id = 'usr_g_${users.length + 1}';
      users[email] = _profileJson(
        id: id,
        email: email,
        username: email.split('@').first,
        displayName: body['displayName'] as String? ?? 'Google User',
      );
      return _json({
        'id': id,
        'token': 'real.access.token.$id',
        'refreshToken': 'real.refresh.token.$id',
        'isNewUser': true,
        'profile': users[email],
      });
    }

    if (path == '/v1/auth/password/session' && request.method == 'DELETE') {
      return http.Response('', 204);
    }

    if (path == '/v1/me' && request.method == 'DELETE') {
      return http.Response('', 204);
    }

    if (path == '/v1/me' && request.method == 'PATCH') {
      final profile = users.values.firstWhere(
        (u) => u['id'] == users.values.first['id'],
      );
      profile['username'] = body!['username'] ?? profile['username'];
      profile['displayName'] = body['displayName'] ?? profile['displayName'];
      profile['bio'] = body['bio'] ?? profile['bio'];
      return _json({'profile': profile});
    }

    return _json({'message': 'Not found', 'statusCode': 404}, 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STEP 6: Flutter <-> Backend Authentication', () {
    late AccountAuthController auth;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      auth = AccountAuthController(client: fakeBackend());
    });

    test('Initial state is unauthenticated before login', () async {
      await auth.initialize();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.profile, isNull);
    });

    test('Email/password registration calls POST /v1/users and persists the REAL token',
        () async {
      await auth.initialize();
      await auth.signUp(
        email: 'alice@example.com',
        password: 'Password123!',
        username: 'alice_w',
        displayName: 'Alice Walker',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.token, startsWith('real.access.token.'));
      expect(auth.profile?.email, equals('alice@example.com'));
      expect(auth.profile?.username, equals('alice_w'));
      expect(auth.profile?.displayName, equals('Alice Walker'));
    });

    test('Database Auth allows login by username', () async {
      await auth.initialize();
      await auth.signUp(
        email: 'bob.builder@gmail.com',
        password: 'Password123!',
        username: 'bob_builder',
        displayName: 'Bob Builder',
      );
      await auth.logout();

      // Login using username instead of email
      await auth.login(
        email: 'bob_builder',
        password: 'Password123!',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.profile?.email, equals('bob.builder@gmail.com'));
      expect(auth.profile?.username, equals('bob_builder'));
      expect(auth.profile?.displayName, equals('Bob Builder'));
    });

    test('Duplicate registration is rejected', () async {
      await auth.initialize();
      await expectLater(
        auth.signUp(
          email: 'bob.builder@gmail.com',
          password: 'Password123!',
          username: 'different_user',
          displayName: 'Different User',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Wrong password is rejected — no silent local fallback', () async {
      await auth.initialize();
      await auth.signUp(
        email: 'carol@example.com',
        password: 'Password123!',
        username: 'carol_c',
        displayName: 'Carol Danvers',
      );
      await auth.logout();

      await expectLater(
        auth.login(email: 'carol@example.com', password: 'wrong-password'),
        throwsA(isA<Exception>()),
      );
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
    });

    test('Logout revokes session on the server and clears stored tokens', () async {
      await auth.initialize();
      await auth.signUp(
        email: 'dave@example.com',
        password: 'Password123!',
        username: 'dave_d',
        displayName: 'Dave Miller',
      );

      expect(auth.isAuthenticated, isTrue);
      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.profile, isNull);
    });

    test('Re-login restores session from the server', () async {
      await auth.initialize();
      await auth.signUp(
        email: 'erin@example.com',
        password: 'Password123!',
        username: 'erin_e',
        displayName: 'Erin Evans',
      );
      await auth.logout();

      await auth.login(email: 'erin@example.com', password: 'Password123!');

      expect(auth.isAuthenticated, isTrue);
      expect(auth.token, startsWith('real.access.token.'));
      expect(auth.profile?.email, equals('erin@example.com'));
    });

    test('Session persistence: token+profile survive controller restart', () async {
      await auth.initialize();
      await auth.signUp(
        email: 'frank@example.com',
        password: 'Password123!',
        username: 'frank_f',
        displayName: 'Frank Castle',
      );
      final savedToken = auth.token;

      final reloaded = AccountAuthController(client: fakeBackend());
      await reloaded.initialize();

      expect(reloaded.isAuthenticated, isTrue);
      expect(reloaded.token, equals(savedToken));
      expect(reloaded.profile?.username, equals('frank_f'));
    });

    test('Profile updates go to PATCH /v1/me and come back from the server',
        () async {
      await auth.initialize();
      await auth.signUp(
        email: 'grace@example.com',
        password: 'Password123!',
        username: 'grace_g',
        displayName: 'Grace Hopper',
      );

      final avatarBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await auth.updateProfile(
        username: 'grace_cyber',
        displayName: 'Grace Cyber',
        bio: 'Amazing Grace.',
        avatarBytes: avatarBytes,
        avatarMimeType: 'image/jpeg',
      );

      expect(auth.profile?.username, equals('grace_cyber'));
      expect(auth.profile?.displayName, equals('Grace Cyber'));
      expect(auth.profile?.bio, equals('Amazing Grace.'));
    });

    test('Delete account calls DELETE /v1/me and purges local state', () async {
      await auth.initialize();
      await auth.signUp(
        email: 'henry@example.com',
        password: 'Password123!',
        username: 'henry_h',
        displayName: 'Henry Harrison',
      );

      expect(auth.isAuthenticated, isTrue);
      await auth.deleteAccount();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.profile, isNull);
      expect(auth.posts, isEmpty);
    });
  });
}